# frozen_string_literal: true

module ElasticsearchSearchHelper
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
end
