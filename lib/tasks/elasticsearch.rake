# frozen_string_literal: true

namespace :redmine do
  namespace :elasticsearch do
    desc 'Create Elasticsearch index with mappings'
    task create_index: :environment do
      if RedmineElasticsearch.client.nil?
        puts "Elasticsearch client not configured. Check config/elasticsearch.yml"
        exit 1
      end

      indexer = Elasticsearch::Indexer.new

      if indexer.index_exists?
        puts "Index '#{RedmineElasticsearch.index_name}' already exists."
        print "Delete and recreate? [y/N]: "
        response = STDIN.gets.chomp.downcase
        if response == 'y'
          indexer.delete_index
          puts "Deleted existing index."
        else
          puts "Aborted."
          exit 0
        end
      end

      if indexer.create_index
        puts "Created index '#{RedmineElasticsearch.index_name}' successfully."
      else
        puts "Failed to create index."
        exit 1
      end
    end

    desc 'Delete Elasticsearch index'
    task delete_index: :environment do
      if RedmineElasticsearch.client.nil?
        puts "Elasticsearch client not configured."
        exit 1
      end

      indexer = Elasticsearch::Indexer.new

      unless indexer.index_exists?
        puts "Index '#{RedmineElasticsearch.index_name}' does not exist."
        exit 0
      end

      print "Are you sure you want to delete the index? [y/N]: "
      response = STDIN.gets.chomp.downcase
      if response == 'y'
        indexer.delete_index
        puts "Deleted index '#{RedmineElasticsearch.index_name}'."
      else
        puts "Aborted."
      end
    end

    desc 'Reindex all searchable content'
    task reindex_all: :environment do
      Rake::Task['redmine:elasticsearch:reindex_issues'].invoke
      Rake::Task['redmine:elasticsearch:reindex_wiki_pages'].invoke
      Rake::Task['redmine:elasticsearch:reindex_news'].invoke
      Rake::Task['redmine:elasticsearch:reindex_messages'].invoke
      Rake::Task['redmine:elasticsearch:reindex_changesets'].invoke
      Rake::Task['redmine:elasticsearch:reindex_documents'].invoke
      Rake::Task['redmine:elasticsearch:reindex_projects'].invoke

      puts "\nAll content reindexed successfully!"
    end

    desc 'Reindex all issues'
    task reindex_issues: :environment do
      reindex_model(Issue, 'issues')
    end

    desc 'Reindex all wiki pages'
    task reindex_wiki_pages: :environment do
      reindex_model(WikiPage, 'wiki pages')
    end

    desc 'Reindex all news'
    task reindex_news: :environment do
      reindex_model(News, 'news')
    end

    desc 'Reindex all forum messages'
    task reindex_messages: :environment do
      reindex_model(Message, 'messages')
    end

    desc 'Reindex all changesets'
    task reindex_changesets: :environment do
      reindex_model(Changeset, 'changesets')
    end

    desc 'Reindex all documents'
    task reindex_documents: :environment do
      reindex_model(Document, 'documents')
    end

    desc 'Reindex all projects'
    task reindex_projects: :environment do
      reindex_model(Project.active, 'projects')
    end

    desc 'Show Elasticsearch index statistics'
    task stats: :environment do
      if RedmineElasticsearch.client.nil?
        puts "Elasticsearch client not configured."
        exit 1
      end

      indexer = Elasticsearch::Indexer.new

      unless indexer.index_exists?
        puts "Index '#{RedmineElasticsearch.index_name}' does not exist."
        exit 0
      end

      stats = indexer.stats
      if stats
        index_stats = stats.dig('indices', RedmineElasticsearch.index_name)
        if index_stats
          primaries = index_stats['primaries']
          puts "Index: #{RedmineElasticsearch.index_name}"
          puts "  Documents: #{primaries.dig('docs', 'count')}"
          puts "  Size: #{primaries.dig('store', 'size_in_bytes')} bytes"
          puts "  Deleted: #{primaries.dig('docs', 'deleted')}"
        end
      else
        puts "Failed to retrieve statistics."
      end
    end

    desc 'Check Elasticsearch connectivity'
    task check: :environment do
      if RedmineElasticsearch.client.nil?
        puts "Elasticsearch client not configured."
        puts "Check config/elasticsearch.yml exists and has valid settings."
        exit 1
      end

      begin
        info = RedmineElasticsearch.client.info
        puts "Connected to Elasticsearch:"
        puts "  Cluster: #{info.dig('cluster_name')}"
        puts "  Version: #{info.dig('version', 'number')}"
        puts "  Node: #{info.dig('name')}"

        indexer = Elasticsearch::Indexer.new
        if indexer.index_exists?
          puts "  Index '#{RedmineElasticsearch.index_name}': exists"
        else
          puts "  Index '#{RedmineElasticsearch.index_name}': not created"
          puts "  Run: bundle exec rake redmine:elasticsearch:create_index"
        end
      rescue => e
        puts "Failed to connect to Elasticsearch: #{e.message}"
        exit 1
      end
    end

    desc 'Check index consistency with database'
    task check_consistency: :environment do
      if RedmineElasticsearch.client.nil?
        puts "Elasticsearch client not configured."
        exit 1
      end

      models = [Issue, WikiPage, News, Message, Changeset, Document, Project]
      total_missing = 0
      total_orphaned = 0

      models.each do |model|
        print "Checking #{model.name}... "

        # Get all IDs from database
        db_ids = if model == Project
                   model.active.pluck(:id)
                 else
                   model.pluck(:id)
                 end

        # Get all IDs from Elasticsearch
        type_name = model.name.underscore
        begin
          response = RedmineElasticsearch.client.search(
            index: RedmineElasticsearch.index_name,
            body: {
              query: { term: { type: type_name } },
              _source: ['id'],
              size: 100000
            }
          )
          es_ids = response.dig('hits', 'hits')&.map { |h| h.dig('_source', 'id') } || []
        rescue
          es_ids = []
        end

        missing = db_ids - es_ids
        orphaned = es_ids - db_ids

        total_missing += missing.size
        total_orphaned += orphaned.size

        if missing.empty? && orphaned.empty?
          puts "OK"
        else
          puts ""
          puts "  Missing in ES: #{missing.size}" if missing.any?
          puts "  Orphaned in ES: #{orphaned.size}" if orphaned.any?
        end
      end

      puts "\nSummary:"
      puts "  Total missing in ES: #{total_missing}"
      puts "  Total orphaned in ES: #{total_orphaned}"

      if total_missing > 0 || total_orphaned > 0
        puts "\nRun 'bundle exec rake redmine:elasticsearch:reindex_all' to fix."
      end
    end

    def reindex_model(scope, name)
      if RedmineElasticsearch.client.nil?
        puts "Elasticsearch client not configured."
        exit 1
      end

      indexer = Elasticsearch::Indexer.new

      unless indexer.index_exists?
        puts "Index does not exist. Run: bundle exec rake redmine:elasticsearch:create_index"
        exit 1
      end

      count = scope.count
      puts "Reindexing #{count} #{name}..."

      batch_size = ENV.fetch('BATCH_SIZE', 500).to_i
      indexed = 0
      errors = 0

      scope.find_in_batches(batch_size: batch_size) do |batch|
        if indexer.bulk_index(batch)
          indexed += batch.size
        else
          errors += batch.size
        end

        print "\r  Progress: #{indexed}/#{count} (#{errors} errors)"
      end

      puts "\n  Done! Indexed: #{indexed}, Errors: #{errors}"
    end
  end
end
