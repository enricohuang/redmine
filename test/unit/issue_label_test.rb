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

class IssueLabelTest < ActiveSupport::TestCase
  fixtures :projects, :labels, :issues, :issue_labels, :trackers, :issue_statuses

  def setup
    @project = Project.find(1)
    @issue = Issue.find(1)
    @label = labels(:label_one)
  end

  # Association tests
  def test_belongs_to_issue
    issue_label = IssueLabel.new(issue: @issue, label: @label)
    assert_equal @issue, issue_label.issue
  end

  def test_belongs_to_label
    issue_label = IssueLabel.new(issue: @issue, label: @label)
    assert_equal @label, issue_label.label
  end

  # Uniqueness validation tests
  def test_label_can_only_be_applied_once_per_issue
    # Create first association
    IssueLabel.create!(issue: @issue, label: labels(:label_urgent))

    # Try to create duplicate
    duplicate = IssueLabel.new(issue: @issue, label: labels(:label_urgent))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:label_id], 'has already been taken'
  end

  def test_same_label_can_be_applied_to_different_issues
    issue2 = Issue.find(2)
    label = labels(:label_three)

    issue_label1 = IssueLabel.new(issue: @issue, label: label)
    issue_label2 = IssueLabel.new(issue: issue2, label: label)

    assert issue_label1.valid?
    assert issue_label2.valid?
  end

  # Project validation tests
  def test_label_must_belong_to_issue_project
    # Use a label not already assigned to issue 3
    label_project1 = labels(:label_urgent)
    # Use issue 3 which has no labels from fixtures
    issue = Issue.find(3)

    # Verify both are in project 1
    assert_equal 1, label_project1.project_id, "Label should be in project 1"
    assert_equal 1, issue.project_id, "Issue should be in project 1"

    issue_label = IssueLabel.new(issue: issue, label: label_project1)
    assert issue_label.valid?, "Label from same project should be valid. Errors: #{issue_label.errors.full_messages.join(', ')}"
  end

  def test_label_from_different_project_is_invalid
    # Create a label in project 2
    label_project2 = labels(:label_project_two)
    # Issue from project 1
    issue = Issue.find(1)

    issue_label = IssueLabel.new(issue: issue, label: label_project2)
    assert_not issue_label.valid?
    assert_includes issue_label.errors[:label], 'is invalid'
  end

  # Issue integration tests
  def test_issue_can_have_multiple_labels
    issue = Issue.find(3) # An issue without labels
    label1 = labels(:label_one)
    label2 = labels(:label_two)

    IssueLabel.create!(issue: issue, label: label1)
    IssueLabel.create!(issue: issue, label: label2)

    issue.reload
    assert_equal 2, issue.labels.count
    assert_includes issue.labels, label1
    assert_includes issue.labels, label2
  end

  def test_removing_issue_label
    issue_label = issue_labels(:issue_one_label_one)
    issue = issue_label.issue
    label = issue_label.label

    assert_includes issue.labels, label

    issue_label.destroy

    issue.reload
    assert_not_includes issue.labels, label
  end

  def test_deleting_issue_removes_issue_labels
    issue = Issue.find(1)
    issue_label_count = issue.issue_labels.count
    assert issue_label_count > 0, "Issue should have labels"

    assert_difference 'IssueLabel.count', -issue_label_count do
      issue.destroy
    end
  end
end
