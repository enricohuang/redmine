# frozen_string_literal: true

# Background job for asynchronously indexing documents in Elasticsearch.
# Uses Active Job for queue management.
class ElasticsearchIndexJob < ApplicationJob
  queue_as :elasticsearch

  # Retry on transient failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(model_class, record_id, action = :index)
    return unless RedmineElasticsearch.available?

    indexer = Elasticsearch::Indexer.new

    case action.to_sym
    when :index
      record = model_class.constantize.find_by(id: record_id)
      if record
        indexer.index(record)
        Rails.logger.debug { "Elasticsearch: Indexed #{model_class}##{record_id}" }
      end
    when :delete
      indexer.delete(model_class, record_id)
      Rails.logger.debug { "Elasticsearch: Deleted #{model_class}##{record_id}" }
    end
  rescue => e
    Rails.logger.error "ElasticsearchIndexJob failed: #{e.message}"
    raise # Re-raise for retry
  end
end
