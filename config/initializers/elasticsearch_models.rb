# frozen_string_literal: true

# Include Elasticsearch callbacks in searchable models.
# This is done via initializer to avoid modifying core model files.

Rails.application.config.after_initialize do
  # Only add callbacks if Elasticsearch is configured
  if RedmineElasticsearch.config['hosts'].present?
    searchable_models = [
      Issue,
      WikiPage,
      News,
      Message,
      Changeset,
      Document,
      Project
    ]

    searchable_models.each do |model|
      model.include(ElasticsearchSearchable) unless model.included_modules.include?(ElasticsearchSearchable)
    end

    Rails.logger.info "Elasticsearch callbacks added to: #{searchable_models.map(&:name).join(', ')}"
  end
end
