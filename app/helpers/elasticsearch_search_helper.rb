# frozen_string_literal: true

module ElasticsearchSearchHelper
  include SearchHelper

  def elasticsearch_available?
    RedmineElasticsearch.available?
  rescue
    false
  end

  def advanced_search_link
    return unless elasticsearch_available?

    link_to l(:label_advanced_search), elasticsearch_search_path, class: 'advanced-search-link'
  end

  def es_result_url(result)
    case result[:type]
    when 'issue'
      issue_path(result[:id])
    when 'wiki_page'
      page = WikiPage.find_by(id: result[:id])
      page ? project_wiki_page_path(page.wiki.project, page.title) : '#'
    when 'news'
      news_path(result[:id])
    when 'message'
      message = Message.find_by(id: result[:id])
      message ? board_message_path(message.board, message) : '#'
    when 'document'
      document_path(result[:id])
    when 'changeset'
      changeset = Changeset.find_by(id: result[:id])
      changeset ? repository_revision_path(changeset.repository.project, changeset.repository.identifier_param, changeset.revision) : '#'
    when 'project'
      project_path(result[:id])
    else
      '#'
    end
  end

  # Load the actual record from ES result hash
  def load_es_record(result)
    case result[:type]
    when 'issue'
      Issue.find_by(id: result[:id])
    when 'wiki_page'
      WikiPage.find_by(id: result[:id])
    when 'news'
      News.find_by(id: result[:id])
    when 'message'
      Message.find_by(id: result[:id])
    when 'document'
      Document.find_by(id: result[:id])
    when 'changeset'
      Changeset.find_by(id: result[:id])
    when 'project'
      Project.find_by(id: result[:id])
    end
  end

  # Type badge for ES result
  def es_type_badge(result, record = nil)
    result_type = result[:type].to_s

    # For issues, use tracker name if record is available
    if result_type == 'issue' && record.is_a?(Issue) && record.tracker
      tracker_class = "tracker-#{record.tracker.name.to_s.parameterize}"
      label = record.tracker.name
    else
      tracker_class = ''
      label = l("label_#{result_type}", default: result_type.humanize)
    end

    content_tag(:span, label,
                class: "search-type-badge search-type-#{result_type} #{tracker_class}".strip)
  end

  # Meta line for ES result
  def es_result_meta(result, record = nil)
    parts = []

    # Project
    if result[:project_id]
      project = Project.find_by(id: result[:project_id])
      if project
        parts << content_tag(:span, class: 'search-meta-project') do
          link_to(project.name, project_path(project))
        end
      end
    end

    # Author (from record if available)
    if record&.respond_to?(:author) && record.author
      parts << content_tag(:span, record.author.name, class: 'search-meta-author')
    end

    # Assignee for issues
    if record.is_a?(Issue) && record.assigned_to
      parts << content_tag(:span, class: 'search-meta-assignee') do
        l(:field_assigned_to) + ': ' + record.assigned_to.name
      end
    end

    # Attachment count (from record if available)
    if record&.respond_to?(:attachments) && record.attachments.count > 0
      parts << attachment_indicator(record)
    end

    # Relative time
    if result[:created_on]
      begin
        datetime = result[:created_on].is_a?(String) ? Time.parse(result[:created_on]) : result[:created_on]
        parts << time_ago_tag(datetime)
      rescue
        # Ignore parsing errors
      end
    end

    # Relevance score
    if result[:score]
      parts << content_tag(:span, number_with_precision(result[:score], precision: 1),
                           class: 'search-relevance-score',
                           title: l(:label_relevance_score))
    end

    safe_join(parts.compact)
  end
end
