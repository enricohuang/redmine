# frozen_string_literal: true

require_relative '../../test_helper'

class Redmine::ApiTest::IssuesBulkTest < Redmine::ApiTest::Base
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses,
           :issues, :issue_categories, :journals, :journal_details, :enumerations,
           :workflows, :custom_fields, :custom_fields_trackers, :custom_values,
           :versions, :time_entries

  test "POST /issues/bulk_update.json should update multiple issues" do
    post(
      '/issues/bulk_update.json',
      :params => {:ids => [1, 2], :issue => {:priority_id => 6}},
      :headers => credentials('jsmith')
    )

    assert_response :no_content
    assert_equal 6, Issue.find(1).priority_id
    assert_equal 6, Issue.find(2).priority_id
  end

  test "POST /issues/bulk_update.xml should update multiple issues" do
    post(
      '/issues/bulk_update.xml',
      :params => {:ids => [1, 2], :issue => {:assigned_to_id => 3}},
      :headers => credentials('jsmith')
    )

    assert_response :no_content
    assert_equal 3, Issue.find(1).assigned_to_id
    assert_equal 3, Issue.find(2).assigned_to_id
  end

  test "POST /issues/bulk_update.json with notes should add journal" do
    assert_difference 'Journal.count', 2 do
      post(
        '/issues/bulk_update.json',
        :params => {:ids => [1, 2], :issue => {:priority_id => 6}, :notes => 'Bulk update via API'},
        :headers => credentials('jsmith')
      )
    end

    assert_response :no_content
    journal = Issue.find(1).journals.last
    assert_equal 'Bulk update via API', journal.notes
  end

  test "POST /issues/bulk_update.json should change status" do
    post(
      '/issues/bulk_update.json',
      :params => {:ids => [1, 2], :issue => {:status_id => 3}},
      :headers => credentials('jsmith')
    )

    assert_response :no_content
    assert_equal 3, Issue.find(1).status_id
    assert_equal 3, Issue.find(2).status_id
  end

  test "DELETE /issues.json should delete multiple issues" do
    assert_difference 'Issue.count', -2 do
      delete(
        '/issues.json',
        :params => {:ids => [1, 2]},
        :headers => credentials('admin')
      )
    end

    assert_response :no_content
    assert_nil Issue.find_by(:id => 1)
    assert_nil Issue.find_by(:id => 2)
  end

  test "DELETE /issues.xml should delete multiple issues" do
    assert_difference 'Issue.count', -2 do
      delete(
        '/issues.xml',
        :params => {:ids => [3, 7]},
        :headers => credentials('admin')
      )
    end

    assert_response :no_content
    assert_nil Issue.find_by(:id => 3)
    assert_nil Issue.find_by(:id => 7)
  end

  test "DELETE /issues.json with time entries and todo=destroy should delete issues" do
    # Issue 1 has time entries from fixtures
    assert TimeEntry.where(:issue_id => 1).exists?

    assert_difference 'Issue.count', -1 do
      delete(
        '/issues.json',
        :params => {:ids => [1], :todo => 'destroy'},
        :headers => credentials('admin')
      )
    end

    assert_response :no_content
    assert_nil Issue.find_by(:id => 1)
    # Time entries should also be deleted
    assert_not TimeEntry.where(:issue_id => 1).exists?
  end

  test "DELETE /issues.json with time entries and todo=nullify should nullify issue_id" do
    # Issue 1 has time entries from fixtures
    time_entry = TimeEntry.where(:issue_id => 1).first
    assert time_entry

    assert_difference 'Issue.count', -1 do
      assert_no_difference 'TimeEntry.count' do
        delete(
          '/issues.json',
          :params => {:ids => [1], :todo => 'nullify'},
          :headers => credentials('admin')
        )
      end
    end

    assert_response :no_content
    time_entry.reload
    assert_nil time_entry.issue_id
  end

  test "POST /issues/bulk_update.json without permission should return 403" do
    # Create a user without edit permission
    post(
      '/issues/bulk_update.json',
      :params => {:ids => [1, 2], :issue => {:priority_id => 6}},
      :headers => credentials('someone')
    )

    # User 'someone' doesn't exist, so it should be 401
    assert_response :unauthorized
  end
end
