# frozen_string_literal: true

require_relative '../../test_helper'

class DocumentBuilderTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :trackers, :issue_statuses,
           :journals, :journal_details, :enabled_modules,
           :wiki_pages, :wiki_contents, :wikis,
           :news, :boards, :messages, :documents

  def test_build_issue_document
    issue = issues(:issues_001)
    doc = Elasticsearch::DocumentBuilder.build(issue)

    assert_equal issue.id, doc[:id]
    assert_equal 'issue', doc[:type]
    assert_equal issue.project_id, doc[:project_id]
    assert_equal issue.subject, doc[:title]
    assert_equal issue.description, doc[:content]
    assert_not_nil doc[:issue_fields]
    assert_equal issue.is_private?, doc[:issue_fields][:is_private]
    assert_equal issue.author_id, doc[:issue_fields][:author_id]
  end

  def test_build_issue_with_journals
    issue = issues(:issues_001)
    # Add a journal with notes
    journal = issue.journals.create!(user: users(:users_002), notes: 'Test note')

    doc = Elasticsearch::DocumentBuilder.build(issue.reload)

    journals = doc[:issue_fields][:journals]
    assert journals.is_a?(Array)
    assert journals.any? { |j| j[:notes] == 'Test note' }
  end

  def test_build_wiki_page_document
    wiki_page = wiki_pages(:wiki_pages_001)
    doc = Elasticsearch::DocumentBuilder.build(wiki_page)

    assert_equal wiki_page.id, doc[:id]
    assert_equal 'wiki_page', doc[:type]
    assert_equal wiki_page.title, doc[:title]
    assert_equal wiki_page.content&.text, doc[:content]
  end

  def test_build_news_document
    news = news(:news_001)
    doc = Elasticsearch::DocumentBuilder.build(news)

    assert_equal news.id, doc[:id]
    assert_equal 'news', doc[:type]
    assert_equal news.title, doc[:title]
    assert_includes doc[:content], news.summary if news.summary.present?
  end

  def test_build_message_document
    message = messages(:messages_001)
    doc = Elasticsearch::DocumentBuilder.build(message)

    assert_equal message.id, doc[:id]
    assert_equal 'message', doc[:type]
    assert_equal message.subject, doc[:title]
    assert_equal message.content, doc[:content]
  end

  def test_build_document_document
    document = documents(:documents_001)
    doc = Elasticsearch::DocumentBuilder.build(document)

    assert_equal document.id, doc[:id]
    assert_equal 'document', doc[:type]
    assert_equal document.title, doc[:title]
    assert_equal document.description, doc[:content]
  end

  def test_build_project_document
    project = projects(:projects_001)
    doc = Elasticsearch::DocumentBuilder.build(project)

    assert_equal project.id, doc[:id]
    assert_equal 'project', doc[:type]
    assert_equal project.name, doc[:title]
    assert_equal project.is_public?, doc[:project_is_public]
  end

  def test_document_id
    issue = issues(:issues_001)
    doc_id = Elasticsearch::DocumentBuilder.document_id(issue)

    assert_equal "issue_#{issue.id}", doc_id
  end

  def test_unsupported_model_raises_error
    user = users(:users_001)

    assert_raises ArgumentError do
      Elasticsearch::DocumentBuilder.build(user)
    end
  end
end
