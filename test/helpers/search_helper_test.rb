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

class SearchHelperTest < Redmine::HelperTest
  include SearchHelper
  include ERB::Util

  def test_highlight_single_token
    assert_equal 'This is a <span class="highlight token-0">token</span>.',
                 highlight_tokens('This is a token.', %w(token))
  end

  def test_highlight_multiple_tokens
    assert_equal(
      'This is a <span class="highlight token-0">token</span> and ' \
        '<span class="highlight token-1">another</span> ' \
        '<span class="highlight token-0">token</span>.',
      highlight_tokens('This is a token and another token.', %w(token another))
    )
  end

  def test_highlight_should_not_exceed_maximum_length
    s = (('1234567890' * 100) + ' token ') * 100
    r = highlight_tokens(s, %w(token))
    assert r.include?('<span class="highlight token-0">token</span>')
    assert r.length <= 1300
  end

  def test_highlight_multibyte
    s = ('й' * 200) + ' token ' + ('й' * 200)
    r = highlight_tokens(s, %w(token))
    assert_equal(
      ('й' * 45) + ' ... ' + ('й' * 44) +
        ' <span class="highlight token-0">token</span> ' +
        ('й' * 44) + ' ... ' + ('й' * 45),
      r
    )
  end

  def test_issues_filter_path
    # rubocop:disable Layout/LineLength
    assert_equal(
      '/issues?f[]=status_id&f[]=any_searchable&f[]=project_id&op[any_searchable]=*~&op[project_id]==&op[status_id]=*&set_filter=1&sort=updated_on:desc&v[any_searchable][]=recipe&v[project_id][]=mine',
      Addressable::URI.unencode(issues_filter_path('recipe', projects_scope: 'my_projects'))
    )
    assert_equal(
      '/issues?f[]=status_id&f[]=any_searchable&f[]=project_id&op[any_searchable]=*~&op[project_id]==&op[status_id]=*&set_filter=1&sort=updated_on:desc&v[any_searchable][]=recipe&v[project_id][]=bookmarks',
      Addressable::URI.unencode(issues_filter_path('recipe', projects_scope: 'bookmarks'))
    )
    assert_equal(
      '/issues?f[]=status_id&f[]=any_searchable&op[any_searchable]=*~&op[status_id]=*&set_filter=1&sort=updated_on:desc&v[any_searchable][]=recipe',
      Addressable::URI.unencode(issues_filter_path('recipe', projects_scope: 'all'))
    )
    # f[]=subject
    assert_equal(
      '/issues?f[]=status_id&f[]=subject&op[status_id]=*&op[subject]=*~&set_filter=1&sort=updated_on:desc&v[subject][]=recipe',
      Addressable::URI.unencode(issues_filter_path('recipe', projects_scope: 'all', titles_only: '1'))
    )
    # op[subject]=~ (contains)
    assert_equal(
      '/issues?f[]=status_id&f[]=subject&op[status_id]=*&op[subject]=~&set_filter=1&sort=updated_on:desc&v[subject][]=recipe',
      Addressable::URI.unencode(issues_filter_path('recipe', projects_scope: 'all', titles_only: '1', all_words: ''))
    )
    # op[status_id]=o (open)
    assert_equal(
      '/issues?f[]=status_id&f[]=subject&op[status_id]=o&op[subject]=*~&set_filter=1&sort=updated_on:desc&v[subject][]=recipe',
      Addressable::URI.unencode(issues_filter_path('recipe', projects_scope: 'all', titles_only: '1', open_issues: '1'))
    )
    # rubocop:enable Layout/LineLength
  end

  # ============================================
  # Tests for new search UI helper methods
  # ============================================

  def test_time_ago_tag_returns_span_with_relative_time
    datetime = 2.hours.ago
    result = time_ago_tag(datetime)

    assert result.include?('<span')
    assert result.include?('class="search-relative-time"')
    assert result.include?('ago')
    assert result.include?('title=')
  end

  def test_time_ago_tag_returns_empty_for_nil
    assert_equal '', time_ago_tag(nil)
  end

  def test_time_ago_tag_with_various_times
    [1.minute.ago, 1.hour.ago, 1.day.ago, 1.week.ago].each do |time|
      result = time_ago_tag(time)
      assert result.include?('ago'), "Should include 'ago' for #{time}"
    end
  end

  def test_search_type_badge_for_issue
    issue = Issue.find(1)
    result = search_type_badge(issue)

    assert result.include?('<span')
    assert result.include?('search-type-badge')
    assert result.include?('search-type-issue')
    # Should include tracker-specific class if tracker exists
    if issue.tracker
      assert result.include?("tracker-#{issue.tracker.name.to_s.parameterize}")
    end
  end

  def test_search_type_badge_for_wiki_page
    wiki_page = WikiPage.find(1)
    result = search_type_badge(wiki_page)

    assert result.include?('search-type-badge')
    assert result.include?('search-type-wiki')
  end

  def test_issue_status_pill_for_open_issue
    issue = Issue.find(1)
    issue.status = IssueStatus.where(is_closed: false).first
    result = issue_status_pill(issue)

    assert result.include?('<span')
    assert result.include?('search-status-pill')
    assert result.include?(issue.status.name)
  end

  def test_issue_status_pill_for_closed_issue
    issue = Issue.find(1)
    issue.status = IssueStatus.where(is_closed: true).first
    result = issue_status_pill(issue)

    assert result.include?('status-closed')
  end

  def test_issue_status_pill_returns_nil_for_non_issue
    result = issue_status_pill("not an issue")
    assert_nil result
  end

  def test_attachment_indicator_with_attachments
    issue = Issue.find(1)
    # Find or create an issue with attachments
    if issue.attachments.empty?
      Attachment.create!(
        container: issue,
        file: uploaded_test_file("testfile.txt", "text/plain"),
        author: User.find(1)
      )
      issue.reload
    end

    result = attachment_indicator(issue)
    assert result.present?
    assert result.include?('search-attachment-indicator')
  end

  def test_attachment_indicator_without_attachments
    issue = Issue.new
    issue.attachments = []
    result = attachment_indicator(issue)
    assert_nil result
  end

  def test_attachment_indicator_for_object_without_attachments_method
    result = attachment_indicator("plain string")
    assert_nil result
  end

  def test_search_result_meta_includes_project
    issue = Issue.find(1)
    @project = nil # Simulate different project context
    result = search_result_meta(issue)

    assert result.include?('search-meta-project')
    assert result.include?(issue.project.name)
  end

  def test_search_result_meta_includes_author
    issue = Issue.find(1)
    result = search_result_meta(issue)

    if issue.author
      assert result.include?('search-meta-author')
      assert result.include?(issue.author.name)
    end
  end

  def test_search_result_meta_includes_time
    issue = Issue.find(1)
    result = search_result_meta(issue)

    assert result.include?('search-relative-time')
    assert result.include?('ago')
  end

  def test_extract_excerpt_basic
    text = "The quick brown fox jumps over the lazy dog"
    result = extract_excerpt(text, "fox", 10)

    assert result.include?('fox')
    assert result.length < text.length + 6 # accounting for ...
  end

  def test_extract_excerpt_with_term_at_start
    text = "fox jumps over the lazy dog"
    result = extract_excerpt(text, "fox", 10)

    assert result.start_with?('fox')
    assert result.include?('...')
  end

  def test_extract_excerpt_with_term_at_end
    text = "The quick brown fox"
    result = extract_excerpt(text, "fox", 10)

    assert result.end_with?('fox')
    assert result.include?('...')
  end

  def test_extract_excerpt_returns_nil_for_missing_term
    result = extract_excerpt("some text", "missing", 10)
    assert_nil result
  end

  def test_extract_excerpt_returns_nil_for_nil_inputs
    assert_nil extract_excerpt(nil, "term", 10)
    assert_nil extract_excerpt("text", nil, 10)
  end

  def test_find_matched_attachment_with_filename_match
    issue = Issue.find(1)
    if issue.attachments.any?
      attachment = issue.attachments.first
      tokens = [attachment.filename.split('.').first.downcase]

      result = find_matched_attachment(issue, tokens)
      if result
        assert result[:filename].present?
      end
    end
  end

  def test_find_matched_attachment_returns_nil_without_attachments
    result = find_matched_attachment("not an object", ["test"])
    assert_nil result
  end

  def test_find_matched_attachment_returns_nil_without_tokens
    issue = Issue.find(1)
    result = find_matched_attachment(issue, nil)
    assert_nil result

    result = find_matched_attachment(issue, [])
    assert_nil result
  end

  def test_type_label_returns_translated_label
    result = type_label('issues')
    assert result.is_a?(String)
    assert result.present?
  end

  def test_type_label_with_singular_form
    result = type_label('issue')
    assert result.is_a?(String)
    assert result.present?
  end

  # render_results_by_type tests are covered in functional tests
  # as they require full request context for URL generation

  private

  def uploaded_test_file(name, mime)
    ActionDispatch::Http::UploadedFile.new(
      tempfile: File.new(Rails.root.join("test/fixtures/files/#{name}")),
      filename: name,
      type: mime
    )
  end
end
