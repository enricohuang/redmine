# frozen_string_literal: true

module Elasticsearch
  # Advanced searcher with more options for the dedicated ES search page.
  # Supports field-specific search, date filtering, sorting, and aggregations.
  class AdvancedSearcher
    attr_reader :user, :options, :total_count, :aggregations

    def initialize(user, options = {})
      @user = user
      @options = options
      @client = RedmineElasticsearch.client
      @total_count = 0
      @aggregations = {}
    end

    def search(query)
      return [] unless @client && query.present?

      response = execute_search(query)
      process_response(response)
    end

    private

    def execute_search(query)
      body = build_query(query)

      @client.search(
        index: RedmineElasticsearch.index_name,
        body: body
      )
    end

    def build_query(query)
      {
        query: {
          bool: {
            must: build_search_query(query),
            filter: build_filters
          }
        },
        highlight: highlight_config,
        sort: build_sort,
        from: options[:offset] || 0,
        size: options[:limit] || 25,
        aggs: build_aggregations,
        track_total_hits: true
      }
    end

    def build_search_query(query)
      case options[:search_in]
      when 'title'
        {
          multi_match: {
            query: query,
            fields: ['title^3', 'title.raw'],
            type: 'best_fields',
            fuzziness: 'AUTO'
          }
        }
      when 'content'
        {
          multi_match: {
            query: query,
            fields: ['content', 'issue_fields.journals.notes', 'custom_fields.value'],
            type: 'best_fields',
            fuzziness: 'AUTO'
          }
        }
      else # 'all'
        {
          bool: {
            should: [
              {
                multi_match: {
                  query: query,
                  fields: ['title^3'],
                  type: 'phrase',
                  boost: 2
                }
              },
              {
                multi_match: {
                  query: query,
                  fields: ['title^2', 'content', 'custom_fields.value', 'attachments.filename'],
                  type: 'best_fields',
                  fuzziness: 'AUTO'
                }
              },
              {
                nested: {
                  path: 'issue_fields.journals',
                  query: {
                    match: { 'issue_fields.journals.notes': query }
                  },
                  score_mode: 'max'
                }
              }
            ],
            minimum_should_match: 1
          }
        }
      end
    end

    def build_filters
      filters = []

      # Type filter
      if options[:types].present?
        filters << { terms: { type: options[:types] } }
      end

      # Project filter
      if options[:project]
        filters << { term: { project_id: options[:project].id } }
      elsif options[:project_ids].present?
        filters << { terms: { project_id: options[:project_ids] } }
      end

      # Date range filter
      if options[:date_from].present? || options[:date_to].present?
        date_filter = { range: { created_on: {} } }
        date_filter[:range][:created_on][:gte] = options[:date_from] if options[:date_from].present?
        date_filter[:range][:created_on][:lte] = options[:date_to] if options[:date_to].present?
        filters << date_filter
      end

      # Closed issues filter
      unless options[:include_closed]
        filters << {
          bool: {
            should: [
              { bool: { must_not: { term: { type: 'issue' } } } },
              { term: { 'issue_fields.status_is_closed': false } }
            ],
            minimum_should_match: 1
          }
        }
      end

      # Permission filter
      permission_filter = PermissionFilter.new(@user).build(options[:types])
      filters << permission_filter if permission_filter

      { bool: { must: filters } }
    end

    def build_sort
      case options[:sort_by]
      when 'date_desc'
        [{ created_on: { order: 'desc' } }, '_score']
      when 'date_asc'
        [{ created_on: { order: 'asc' } }, '_score']
      when 'updated_desc'
        [{ updated_on: { order: 'desc', missing: '_last' } }, '_score']
      else # 'relevance'
        ['_score', { created_on: { order: 'desc' } }]
      end
    end

    def build_aggregations
      {
        by_type: {
          terms: { field: 'type', size: 10 }
        },
        by_project: {
          terms: { field: 'project_id', size: 20 }
        },
        by_date: {
          date_histogram: {
            field: 'created_on',
            calendar_interval: 'month',
            format: 'yyyy-MM',
            min_doc_count: 1
          }
        }
      }
    end

    def highlight_config
      {
        fields: {
          title: { number_of_fragments: 0 },
          content: { fragment_size: 200, number_of_fragments: 3 },
          'issue_fields.journals.notes': { fragment_size: 200, number_of_fragments: 2 }
        },
        pre_tags: ['<mark class="es-highlight">'],
        post_tags: ['</mark>']
      }
    end

    def process_response(response)
      @total_count = response.dig('hits', 'total', 'value') || 0
      @aggregations = process_aggregations(response['aggregations'])

      hits = response.dig('hits', 'hits') || []
      results = hits.map { |hit| process_hit(hit) }

      # Apply fine-grained permission filtering
      results.select { |r| can_view?(r) }
    end

    def process_aggregations(aggs)
      return {} unless aggs

      {
        by_type: (aggs.dig('by_type', 'buckets') || []).map do |b|
          { key: b['key'], count: b['doc_count'], label: type_label(b['key']) }
        end,
        by_project: (aggs.dig('by_project', 'buckets') || []).map do |b|
          project = Project.find_by(id: b['key'])
          { key: b['key'], count: b['doc_count'], label: project&.name || "Project ##{b['key']}" }
        end,
        by_date: (aggs.dig('by_date', 'buckets') || []).map do |b|
          { key: b['key_as_string'], count: b['doc_count'] }
        end
      }
    end

    def type_label(type)
      I18n.t("label_#{type}", default: type.humanize)
    end

    def process_hit(hit)
      source = hit['_source']
      highlight = hit['highlight'] || {}

      {
        type: source['type'],
        id: source['id'],
        project_id: source['project_id'],
        title: highlight['title']&.first || source['title'],
        content: extract_highlighted_content(highlight, source),
        score: hit['_score'],
        created_on: source['created_on'],
        updated_on: source['updated_on'],
        raw: source
      }
    end

    def extract_highlighted_content(highlight, source)
      highlight['content']&.join(' ... ') ||
        highlight['issue_fields.journals.notes']&.join(' ... ') ||
        truncate_text(source['content'], 300)
    end

    def truncate_text(text, length)
      return nil if text.blank?

      text.length > length ? "#{text[0, length]}..." : text
    end

    def can_view?(result)
      case result[:type]
      when 'issue'
        issue = Issue.find_by(id: result[:id])
        issue&.visible?(@user)
      when 'wiki_page'
        page = WikiPage.find_by(id: result[:id])
        page && @user.allowed_to?(:view_wiki_pages, page.wiki&.project)
      when 'news'
        news = News.find_by(id: result[:id])
        news&.visible?(@user)
      when 'message'
        message = Message.find_by(id: result[:id])
        message&.visible?(@user)
      when 'changeset'
        changeset = Changeset.find_by(id: result[:id])
        changeset && @user.allowed_to?(:view_changesets, changeset.repository&.project)
      when 'document'
        document = Document.find_by(id: result[:id])
        document&.visible?(@user)
      when 'project'
        project = Project.find_by(id: result[:id])
        project&.visible?(@user)
      else
        false
      end
    end
  end
end
