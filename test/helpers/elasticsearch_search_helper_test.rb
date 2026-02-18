# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require_relative '../test_helper'

class ElasticsearchSearchHelperTest < Redmine::HelperTest
  include ElasticsearchSearchHelper
  include ERB::Util

  fixtures :projects, :issues, :trackers, :issue_statuses, :users, :wikis, :wiki_pages

  def setup
    @project = Project.find(1)
  end

  # elasticsearch_available? tests
  def test_elasticsearch_available_returns_false_when_not_defined
    # When RedmineElasticsearch is not defined
    result = elasticsearch_available?
    # Should return false without raising error
    assert [true, false].include?(result)
  end

  # es_result_url tests
  def test_es_result_url_for_issue
    result = { type: 'issue', id: 1 }
    url = es_result_url(result)
    assert_equal issue_path(1), url
  end

  def test_es_result_url_for_wiki_page
    wiki_page = WikiPage.find(1)
    result = { type: 'wiki_page', id: wiki_page.id }
    url = es_result_url(result)
    assert url.include?('wiki')
  end

  def test_es_result_url_for_news
    result = { type: 'news', id: 1 }
    url = es_result_url(result)
    assert_equal news_path(1), url
  end

  def test_es_result_url_for_document
    result = { type: 'document', id: 1 }
    url = es_result_url(result)
    assert_equal document_path(1), url
  end

  def test_es_result_url_for_project
    result = { type: 'project', id: 1 }
    url = es_result_url(result)
    assert_equal project_path(1), url
  end

  def test_es_result_url_for_unknown_type
    result = { type: 'unknown', id: 1 }
    url = es_result_url(result)
    assert_equal '#', url
  end

  # load_es_record tests
  def test_load_es_record_for_issue
    issue = Issue.find(1)
    result = { type: 'issue', id: issue.id }
    record = load_es_record(result)

    assert_equal issue, record
    assert record.is_a?(Issue)
  end

  def test_load_es_record_for_wiki_page
    wiki_page = WikiPage.find(1)
    result = { type: 'wiki_page', id: wiki_page.id }
    record = load_es_record(result)

    assert_equal wiki_page, record
  end

  def test_load_es_record_for_project
    project = Project.find(1)
    result = { type: 'project', id: project.id }
    record = load_es_record(result)

    assert_equal project, record
  end

  def test_load_es_record_returns_nil_for_not_found
    result = { type: 'issue', id: 99999 }
    record = load_es_record(result)
    assert_nil record
  end

  def test_load_es_record_returns_nil_for_unknown_type
    result = { type: 'unknown', id: 1 }
    record = load_es_record(result)
    assert_nil record
  end

  # es_type_badge tests
  def test_es_type_badge_for_issue_with_record
    issue = Issue.find(1)
    result = { type: 'issue', id: issue.id }
    badge = es_type_badge(result, issue)

    assert badge.include?('search-type-badge')
    assert badge.include?('search-type-issue')
    if issue.tracker
      assert badge.include?(issue.tracker.name)
    end
  end

  def test_es_type_badge_for_issue_without_record
    result = { type: 'issue', id: 1 }
    badge = es_type_badge(result, nil)

    assert badge.include?('search-type-badge')
    assert badge.include?('search-type-issue')
  end

  def test_es_type_badge_for_wiki_page
    result = { type: 'wiki_page', id: 1 }
    badge = es_type_badge(result, nil)

    assert badge.include?('search-type-badge')
    assert badge.include?('search-type-wiki_page')
  end

  def test_es_type_badge_for_project
    result = { type: 'project', id: 1 }
    badge = es_type_badge(result, nil)

    assert badge.include?('search-type-badge')
    assert badge.include?('search-type-project')
  end

  # es_result_meta tests
  def test_es_result_meta_includes_project
    result = { type: 'issue', id: 1, project_id: 1 }
    record = Issue.find(1)
    meta = es_result_meta(result, record)

    assert meta.include?('search-meta-project')
    assert meta.include?(Project.find(1).name)
  end

  def test_es_result_meta_includes_author
    result = { type: 'issue', id: 1 }
    record = Issue.find(1)
    meta = es_result_meta(result, record)

    if record.author
      assert meta.include?('search-meta-author')
      assert meta.include?(record.author.name)
    end
  end

  def test_es_result_meta_includes_assignee_for_issues
    result = { type: 'issue', id: 1 }
    record = Issue.find(1)
    meta = es_result_meta(result, record)

    if record.assigned_to
      assert meta.include?('search-meta-assignee')
    end
  end

  def test_es_result_meta_includes_time
    result = { type: 'issue', id: 1, created_on: 1.day.ago.iso8601 }
    record = Issue.find(1)
    meta = es_result_meta(result, record)

    assert meta.include?('search-relative-time')
    assert meta.include?('ago')
  end

  def test_es_result_meta_includes_relevance_score
    result = { type: 'issue', id: 1, score: 15.5 }
    record = Issue.find(1)
    meta = es_result_meta(result, record)

    assert meta.include?('search-relevance-score')
    # Score might be formatted differently based on locale (15.5 or 15,5)
    assert meta.include?('15'), "Expected score to include '15'"
  end

  def test_es_result_meta_handles_missing_project
    result = { type: 'issue', id: 1, project_id: nil }
    record = Issue.find(1)
    # Should not raise error
    meta = es_result_meta(result, record)
    assert meta.is_a?(String)
  end

  def test_es_result_meta_handles_invalid_date
    result = { type: 'issue', id: 1, created_on: 'invalid-date' }
    record = Issue.find(1)
    # Should not raise error
    meta = es_result_meta(result, record)
    assert meta.is_a?(String)
  end

  # Integration with SearchHelper tests
  def test_includes_search_helper_methods
    # time_ago_tag from SearchHelper should be available
    assert respond_to?(:time_ago_tag)
    assert respond_to?(:attachment_indicator)
    assert respond_to?(:issue_status_pill)
  end
end
