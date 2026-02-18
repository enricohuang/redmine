# frozen_string_literal: true

module Elasticsearch
  # Adapter that wraps Elasticsearch::Searcher to provide a compatible interface
  # with Redmine::Search::Fetcher for seamless integration.
  class SearchAdapter
    attr_reader :tokens, :question, :user, :scope, :projects, :options

    def initialize(question, user, scope, projects, options = {})
      @question = question.to_s.strip
      @user = user
      @scope = scope
      @projects = projects
      @options = options
      @tokens = tokenize(@question)
    end

    def result_count
      @result_count ||= @tokens.blank? ? 0 : searcher.count(@question)
    end

    def result_count_by_type
      @result_count_by_type ||= compute_result_count_by_type
    end

    def results(offset, limit)
      return [] if @tokens.blank?

      es_results = searcher.search(@question, offset: offset, limit: limit)

      # Convert ES results to Redmine objects
      es_results.filter_map do |result|
        load_record(result)
      end
    end

    private

    def compute_result_count_by_type
      return {} if @tokens.blank?

      counts = {}
      @scope.each do |type|
        type_searcher = Searcher.new(@user, @projects, search_options.merge(scope: [type]))
        counts[type] = type_searcher.count(@question)
      end
      counts
    end

    def searcher
      @searcher ||= Searcher.new(@user, @projects, search_options)
    end

    def search_options
      {
        scope: @scope,
        all_words: @options[:all_words],
        titles_only: @options[:titles_only],
        open_issues: @options[:open_issues],
        attachments: @options[:attachments]
      }
    end

    def tokenize(query)
      # Match Redmine's tokenizer behavior
      query.to_s.scan(/\w+/).select { |token| token.length >= 2 }.first(5)
    end

    def load_record(result)
      type = result[:type]
      id = result[:id]

      case type
      when 'issue'
        Issue.find_by(id: id)
      when 'wiki_page'
        WikiPage.find_by(id: id)
      when 'news'
        News.find_by(id: id)
      when 'message'
        Message.find_by(id: id)
      when 'changeset'
        Changeset.find_by(id: id)
      when 'document'
        Document.find_by(id: id)
      when 'project'
        Project.find_by(id: id)
      end
    end
  end
end
