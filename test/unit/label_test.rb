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

class LabelTest < ActiveSupport::TestCase
  fixtures :projects, :labels, :issues, :issue_labels

  def setup
    @project = Project.find(1)
  end

  # Validation tests
  def test_create_with_valid_attributes
    label = Label.new(name: 'New Label', color: '#FF5733', project: @project)
    assert label.save
    assert_equal 'New Label', label.name
    assert_equal '#FF5733', label.color
  end

  def test_name_is_required
    label = Label.new(color: '#FF5733', project: @project)
    assert_not label.valid?
    assert label.errors[:name].any? { |e| e.include?('blank') }
  end

  def test_project_is_required
    label = Label.new(name: 'Test', color: '#FF5733')
    assert_not label.valid?
    assert label.errors[:project].any? { |e| e.include?('blank') }
  end

  def test_name_must_be_unique_within_project
    Label.create!(name: 'Unique', color: '#FF5733', project: @project)
    duplicate = Label.new(name: 'Unique', color: '#00FF00', project: @project)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], 'has already been taken'
  end

  def test_same_name_allowed_in_different_projects
    project2 = Project.find(2)
    Label.create!(name: 'Shared Name', color: '#FF5733', project: @project)
    label2 = Label.new(name: 'Shared Name', color: '#00FF00', project: project2)
    assert label2.valid?
    assert label2.save
  end

  def test_name_uniqueness_is_case_sensitive
    Label.create!(name: 'CaseSensitive', color: '#FF5733', project: @project)
    # Different case should be allowed (case_sensitive: true in validation)
    label2 = Label.new(name: 'casesensitive', color: '#00FF00', project: @project)
    assert label2.valid?
  end

  def test_name_maximum_length
    label = Label.new(name: 'a' * 65, color: '#FF5733', project: @project)
    assert_not label.valid?
    assert_includes label.errors[:name], 'is too long (maximum is 64 characters)'
  end

  def test_name_at_maximum_length
    label = Label.new(name: 'a' * 64, color: '#FF5733', project: @project)
    assert label.valid?
  end

  def test_color_format_validation
    label = Label.new(name: 'Test', project: @project)

    # Valid colors
    label.color = '#FF5733'
    assert label.valid?, "Should accept uppercase hex"

    label.color = '#ff5733'
    assert label.valid?, "Should accept lowercase hex"

    label.color = '#aAbBcC'
    assert label.valid?, "Should accept mixed case hex"

    # Invalid colors
    label.color = 'FF5733'
    assert_not label.valid?, "Should reject without #"

    label.color = '#FF573'
    assert_not label.valid?, "Should reject 5-digit hex"

    label.color = '#FF57331'
    assert_not label.valid?, "Should reject 7-digit hex"

    label.color = '#GGGGGG'
    assert_not label.valid?, "Should reject invalid hex characters"

    label.color = 'red'
    assert_not label.valid?, "Should reject color names"
  end

  # Text color contrast tests
  def test_text_color_for_dark_background
    label = Label.new(name: 'Dark', color: '#000000', project: @project)
    assert_equal '#FFFFFF', label.text_color
  end

  def test_text_color_for_light_background
    label = Label.new(name: 'Light', color: '#FFFFFF', project: @project)
    assert_equal '#000000', label.text_color
  end

  def test_text_color_for_red_background
    label = Label.new(name: 'Red', color: '#d73a4a', project: @project)
    # Dark red should get white text
    assert_equal '#FFFFFF', label.text_color
  end

  def test_text_color_for_yellow_background
    label = Label.new(name: 'Yellow', color: '#FFFF00', project: @project)
    # Bright yellow should get black text
    assert_equal '#000000', label.text_color
  end

  def test_text_color_for_cyan_background
    label = Label.new(name: 'Cyan', color: '#a2eeef', project: @project)
    # Light cyan should get black text
    assert_equal '#000000', label.text_color
  end

  # Association tests
  def test_belongs_to_project
    label = labels(:label_one)
    assert_equal projects(:projects_001), label.project
  end

  def test_has_many_issue_labels
    label = labels(:label_one)
    assert_respond_to label, :issue_labels
    assert label.issue_labels.count >= 0
  end

  def test_has_many_issues_through_issue_labels
    label = labels(:label_one)
    assert_respond_to label, :issues
  end

  def test_destroying_label_destroys_issue_labels
    label = labels(:label_one)
    issue_label_count = label.issue_labels.count
    assert issue_label_count > 0, "Fixture should have issue_labels"

    assert_difference 'IssueLabel.count', -issue_label_count do
      label.destroy
    end
  end

  # to_s test
  def test_to_s_returns_name
    label = Label.new(name: 'My Label', color: '#FF5733', project: @project)
    assert_equal 'My Label', label.to_s
  end

  # Safe attributes test
  def test_safe_attributes
    label = Label.new(project: @project)
    label.safe_attributes = { 'name' => 'Safe Name', 'color' => '#123456' }
    assert_equal 'Safe Name', label.name
    assert_equal '#123456', label.color
  end

  def test_safe_attributes_ignores_project
    label = Label.new(project: @project)
    project2 = Project.find(2)
    label.safe_attributes = { 'name' => 'Test', 'color' => '#123456', 'project_id' => project2.id }
    # project_id should not be changed via safe_attributes
    assert_equal @project.id, label.project_id
  end

  # Query tests
  def test_labels_ordered_by_name
    labels = @project.labels.order(:name)
    names = labels.map(&:name)
    assert_equal names, names.sort
  end
end
