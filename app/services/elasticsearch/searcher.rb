# frozen_string_literal: true

module Elasticsearch
  # Executes search queries against Elasticsearch with permission filtering.
  # Implements the hybrid approach: ES handles coarse filtering, then Ruby applies fine-grained checks.
  class Searcher
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    OVERFETCH_RATIO = 2  # Fetch extra results to account for post-filtering

    attr_reader :user, :projects, :options

    def initialize(user, projects = nil, options = {})
      @user = user
      @projects = projects
      @options = options
      @client = RedmineElasticsearch.client
    end

    # Execute search and return results
    # Returns an array of result hashes with :type, :id, :title, :content, :project_id, :score
    def search(query, limit: DEFAULT_LIMIT, offset: 0)
      return [] unless @client && query.present?

      limit = [limit.to_i, MAX_LIMIT].min
      limit = DEFAULT_LIMIT if limit <= 0

      # Build the ES query
      es_query = build_query(query)
      es_filter = build_filter

      # Overfetch to account for post-filtering
      fetch_size = (limit + offset) * OVERFETCH_RATIO

      response = @client.search(
        index: index_name,
        body: {
          query: {
            bool: {
              must: es_query,
              filter: es_filter
            }
          },
          highlight: highlight_config,
          size: fetch_size,
          from: 0,  # We handle offset in post-processing
          _source: true
        }
      )

      # Process and filter results
      results = process_results(response)

      # Apply fine-grained permission filtering
      filtered_results = apply_post_filter(results)

      # Apply offset and limit
      filtered_results.drop(offset).take(limit)
    rescue => e
      Rails.logger.error "Elasticsearch search failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      []
    end

    # Count total results (without fetching all)
    def count(query)
      return 0 unless @client && query.present?

      es_query = build_query(query)
      es_filter = build_filter

      response = @client.count(
        index: index_name,
        body: {
          query: {
            bool: {
              must: es_query,
              filter: es_filter
            }
          }
        }
      )

      response['count']
    rescue => e
      Rails.logger.error "Elasticsearch count failed: #{e.message}"
      0
    end

    private

    def index_name
      RedmineElasticsearch.index_name
    end

    def build_query(query)
      # Parse query tokens
      tokens = tokenize(query)
      return { match_all: {} } if tokens.empty?

      # Build multi-match query
      {
        bool: {
          should: [
            # Exact phrase match (highest boost)
            {
              multi_match: {
                query: query,
                fields: ['title^3', 'content', 'attachments.filename', 'attachments.description', 'attachments.fulltext_content'],
                type: 'phrase',
                boost: 2
              }
            },
            # Individual terms match
            {
              multi_match: {
                query: query,
                fields: ['title^3', 'content', 'custom_fields.value', 'attachments.filename', 'attachments.fulltext_content'],
                type: 'best_fields',
                operator: options[:all_words] ? 'and' : 'or',
                fuzziness: 'AUTO'
              }
            },
            # Nested journal search (for issues)
            {
              nested: {
                path: 'issue_fields.journals',
                query: {
                  match: {
                    'issue_fields.journals.notes': {
                      query: query,
                      operator: options[:all_words] ? 'and' : 'or'
                    }
                  }
                },
                score_mode: 'max'
              }
            }
          ],
          minimum_should_match: 1
        }
      }
    end

    def build_filter
      filters = []

      # Document type filter
      if options[:scope].present?
        types = Array(options[:scope]).map(&:to_s)
        filters << { terms: { type: types } }
      end

      # Project filter
      if @projects.present?
        project_ids = Array(@projects).map { |p| p.is_a?(Project) ? p.id : p.to_i }
        filters << { terms: { project_id: project_ids } }
      end

      # Permission filter
      permission_filter = PermissionFilter.new(@user).build(options[:scope])
      filters << permission_filter if permission_filter

      # Open issues only
      if options[:open_issues]
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

      # Titles only
      if options[:titles_only]
        filters << {
          bool: {
            should: [
              { exists: { field: 'title' } }
            ]
          }
        }
      end

      { bool: { must: filters } }
    end

    def highlight_config
      return nil unless RedmineElasticsearch.config.dig('highlight', 'enabled')

      fragment_size = RedmineElasticsearch.config.dig('highlight', 'fragment_size') || 150
      num_fragments = RedmineElasticsearch.config.dig('highlight', 'number_of_fragments') || 3

      {
        fields: {
          title: { number_of_fragments: 0 },
          content: { fragment_size: fragment_size, number_of_fragments: num_fragments },
          'issue_fields.journals.notes': { fragment_size: fragment_size, number_of_fragments: num_fragments }
        },
        pre_tags: ['<span class="highlight">'],
        post_tags: ['</span>']
      }
    end

    def process_results(response)
      hits = response.dig('hits', 'hits') || []

      hits.map do |hit|
        source = hit['_source']
        highlight = hit['highlight'] || {}

        {
          type: source['type'],
          id: source['id'],
          project_id: source['project_id'],
          title: highlight['title']&.first || source['title'],
          content: extract_content_highlight(highlight, source),
          score: hit['_score'],
          created_on: source['created_on'],
          updated_on: source['updated_on'],
          raw: source
        }
      end
    end

    def extract_content_highlight(highlight, source)
      # Try to get highlighted content from various fields
      highlight['content']&.join('...') ||
        highlight['issue_fields.journals.notes']&.join('...') ||
        truncate_content(source['content'])
    end

    def truncate_content(content, length: 200)
      return nil if content.blank?

      if content.length > length
        content[0, length] + '...'
      else
        content
      end
    end

    # Apply fine-grained permission filtering that can't be done in ES
    def apply_post_filter(results)
      results.select do |result|
        case result[:type]
        when 'issue'
          can_view_issue?(result)
        when 'wiki_page'
          can_view_wiki_page?(result)
        when 'news'
          can_view_news?(result)
        when 'message'
          can_view_message?(result)
        when 'changeset'
          can_view_changeset?(result)
        when 'document'
          can_view_document?(result)
        when 'project'
          can_view_project?(result)
        else
          false
        end
      end
    end

    def can_view_issue?(result)
      issue = Issue.find_by(id: result[:id])
      return false unless issue

      issue.visible?(@user)
    end

    def can_view_wiki_page?(result)
      wiki_page = WikiPage.find_by(id: result[:id])
      return false unless wiki_page

      project = wiki_page.wiki&.project
      return false unless project

      @user.allowed_to?(:view_wiki_pages, project)
    end

    def can_view_news?(result)
      news = News.find_by(id: result[:id])
      return false unless news

      news.visible?(@user)
    end

    def can_view_message?(result)
      message = Message.find_by(id: result[:id])
      return false unless message

      message.visible?(@user)
    end

    def can_view_changeset?(result)
      changeset = Changeset.find_by(id: result[:id])
      return false unless changeset

      project = changeset.repository&.project
      return false unless project

      @user.allowed_to?(:view_changesets, project)
    end

    def can_view_document?(result)
      document = Document.find_by(id: result[:id])
      return false unless document

      document.visible?(@user)
    end

    def can_view_project?(result)
      project = Project.find_by(id: result[:id])
      return false unless project

      project.visible?(@user)
    end

    def tokenize(query)
      # Similar to Redmine's tokenizer
      query.to_s.scan(/\w+/).select { |token| token.length >= 2 }.first(5)
    end
  end
end
