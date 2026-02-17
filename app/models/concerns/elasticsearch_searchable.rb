# frozen_string_literal: true

# Concern for models that should be indexed in Elasticsearch.
# Include this in any model that needs full-text search capabilities.
#
# Example:
#   class Issue < ApplicationRecord
#     include ElasticsearchSearchable
#   end
#
module ElasticsearchSearchable
  extend ActiveSupport::Concern

  included do
    after_commit :enqueue_elasticsearch_index, on: [:create, :update]
    after_commit :enqueue_elasticsearch_delete, on: :destroy
  end

  # Force immediate reindex (useful for testing or bulk operations)
  def reindex_elasticsearch!
    return false unless RedmineElasticsearch.available?

    Elasticsearch::Indexer.new.index(self)
  end

  private

  def enqueue_elasticsearch_index
    return unless RedmineElasticsearch.enabled?

    ElasticsearchIndexJob.perform_later(self.class.name, id, :index)
  end

  def enqueue_elasticsearch_delete
    return unless RedmineElasticsearch.enabled?

    ElasticsearchIndexJob.perform_later(self.class.name, id, :delete)
  end
end
