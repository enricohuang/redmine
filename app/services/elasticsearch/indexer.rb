# frozen_string_literal: true

module Elasticsearch
  # Handles indexing operations for Elasticsearch.
  # Responsible for creating, updating, and deleting documents in the index.
  class Indexer
    INDEX_MAPPINGS = {
      properties: {
        type: { type: 'keyword' },
        project_id: { type: 'integer' },
        project_is_public: { type: 'boolean' },
        created_on: { type: 'date' },
        updated_on: { type: 'date' },
        title: {
          type: 'text',
          analyzer: 'redmine_analyzer',
          fields: { raw: { type: 'keyword' } }
        },
        content: {
          type: 'text',
          analyzer: 'redmine_analyzer'
        },
        author_id: { type: 'integer' },
        issue_fields: {
          properties: {
            is_private: { type: 'boolean' },
            author_id: { type: 'integer' },
            assigned_to_id: { type: 'integer' },
            tracker_id: { type: 'integer' },
            status_id: { type: 'integer' },
            status_is_closed: { type: 'boolean' },
            priority_id: { type: 'integer' },
            journals: {
              type: 'nested',
              properties: {
                id: { type: 'integer' },
                notes: { type: 'text', analyzer: 'redmine_analyzer' },
                is_private: { type: 'boolean' },
                user_id: { type: 'integer' },
                created_on: { type: 'date' }
              }
            }
          }
        },
        custom_fields: {
          type: 'nested',
          properties: {
            id: { type: 'integer' },
            name: { type: 'keyword' },
            value: { type: 'text', analyzer: 'redmine_analyzer' }
          }
        },
        attachments: {
          type: 'nested',
          properties: {
            id: { type: 'integer' },
            filename: { type: 'text' },
            description: { type: 'text' }
          }
        },
        # Message-specific
        board_id: { type: 'integer' },
        parent_id: { type: 'integer' },
        # Changeset-specific
        repository_id: { type: 'integer' },
        # Document-specific
        category_id: { type: 'integer' },
        # Project-specific
        status: { type: 'integer' }
      }
    }.freeze

    INDEX_SETTINGS = {
      analysis: {
        analyzer: {
          redmine_analyzer: {
            type: 'custom',
            tokenizer: 'standard',
            filter: %w[lowercase asciifolding snowball]
          }
        }
      }
    }.freeze

    def initialize
      @client = RedmineElasticsearch.client
    end

    # Index a single record
    def index(record)
      return false unless @client

      document = DocumentBuilder.build(record)
      doc_id = DocumentBuilder.document_id(record)

      @client.index(
        index: index_name,
        id: doc_id,
        body: document
      )
      true
    rescue => e
      Rails.logger.error "Elasticsearch indexing failed for #{record.class}##{record.id}: #{e.message}"
      false
    end

    # Delete a document from the index
    def delete(record_or_type, id = nil)
      return false unless @client

      if record_or_type.is_a?(String) || record_or_type.is_a?(Symbol)
        doc_id = "#{record_or_type.to_s.underscore}_#{id}"
      else
        doc_id = DocumentBuilder.document_id(record_or_type)
      end

      @client.delete(
        index: index_name,
        id: doc_id,
        ignore: [404]
      )
      true
    rescue => e
      Rails.logger.error "Elasticsearch delete failed for #{doc_id}: #{e.message}"
      false
    end

    # Bulk index multiple records
    def bulk_index(records)
      return false unless @client
      return true if records.empty?

      body = records.flat_map do |record|
        document = DocumentBuilder.build(record)
        doc_id = DocumentBuilder.document_id(record)
        [
          { index: { _index: index_name, _id: doc_id } },
          document
        ]
      end

      response = @client.bulk(body: body)

      if response['errors']
        errors = response['items'].select { |item| item.dig('index', 'error') }
        errors.each do |error|
          Rails.logger.error "Elasticsearch bulk index error: #{error.dig('index', 'error')}"
        end
      end

      !response['errors']
    rescue => e
      Rails.logger.error "Elasticsearch bulk indexing failed: #{e.message}"
      false
    end

    # Create the index with mappings
    def create_index(force: false)
      return false unless @client

      if index_exists?
        return true unless force

        delete_index
      end

      @client.indices.create(
        index: index_name,
        body: {
          settings: INDEX_SETTINGS,
          mappings: INDEX_MAPPINGS
        }
      )
      true
    rescue => e
      Rails.logger.error "Elasticsearch create index failed: #{e.message}"
      false
    end

    # Delete the index
    def delete_index
      return false unless @client

      @client.indices.delete(index: index_name, ignore: [404])
      true
    rescue => e
      Rails.logger.error "Elasticsearch delete index failed: #{e.message}"
      false
    end

    # Check if index exists
    def index_exists?
      return false unless @client

      @client.indices.exists?(index: index_name)
    rescue
      false
    end

    # Refresh the index (make recent changes searchable)
    def refresh
      return false unless @client

      @client.indices.refresh(index: index_name)
      true
    rescue => e
      Rails.logger.error "Elasticsearch refresh failed: #{e.message}"
      false
    end

    # Get index statistics
    def stats
      return nil unless @client

      @client.indices.stats(index: index_name)
    rescue => e
      Rails.logger.error "Elasticsearch stats failed: #{e.message}"
      nil
    end

    private

    def index_name
      RedmineElasticsearch.index_name
    end
  end
end
