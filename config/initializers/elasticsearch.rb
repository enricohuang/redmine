# frozen_string_literal: true

# Elasticsearch Configuration for Redmine
#
# This initializer sets up the Elasticsearch client and configuration.
# Elasticsearch is optional - if not available, Redmine will use database search.

module RedmineElasticsearch
  class << self
    attr_accessor :client, :config

    def enabled?
      # Enable by default when client is configured
      # Can be overridden by setting ELASTICSEARCH_DISABLED=true
      return false if ENV['ELASTICSEARCH_DISABLED'] == 'true'

      client.present?
    rescue
      false
    end

    def available?
      return false unless enabled?
      return @available if defined?(@available)

      @available = begin
        client.ping
      rescue
        false
      end
    end

    def index_name(type = nil)
      prefix = config['index_prefix'] || 'redmine'
      type ? "#{prefix}_#{type}" : prefix
    end

    def refresh_availability!
      remove_instance_variable(:@available) if defined?(@available)
    end
  end
end

# Load Elasticsearch configuration
es_config_file = Rails.root.join('config', 'elasticsearch.yml')
if File.exist?(es_config_file)
  es_config = YAML.safe_load(ERB.new(File.read(es_config_file)).result, permitted_classes: [], permitted_symbols: [], aliases: true)
  RedmineElasticsearch.config = es_config[Rails.env] || es_config['default'] || {}
else
  RedmineElasticsearch.config = {}
end

# Initialize Elasticsearch client if configured
if RedmineElasticsearch.config['hosts'].present?
  begin
    require 'elasticsearch'

    RedmineElasticsearch.client = Elasticsearch::Client.new(
      hosts: RedmineElasticsearch.config['hosts'],
      request_timeout: RedmineElasticsearch.config['request_timeout'] || 30,
      retry_on_failure: RedmineElasticsearch.config['retry_on_failure'] || 3,
      log: RedmineElasticsearch.config['log'] || false
    )

    Rails.logger.info "Elasticsearch client initialized for #{RedmineElasticsearch.config['hosts']}"
  rescue LoadError => e
    Rails.logger.warn "Elasticsearch gem not loaded: #{e.message}"
  rescue => e
    Rails.logger.warn "Failed to initialize Elasticsearch client: #{e.message}"
  end
end
