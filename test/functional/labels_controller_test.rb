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

class LabelsControllerTest < Redmine::ControllerTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :labels, :issues, :issue_labels, :trackers, :issue_statuses,
           :enabled_modules

  def setup
    @project = Project.find(1)
    @label = labels(:label_one)
    User.current = nil
    # Ensure role has manage_labels permission
    Role.find(1).add_permission!(:manage_labels)
    Role.find(2).add_permission!(:manage_labels)
    # Enable REST API
    Setting.rest_api_enabled = '1'
  end

  # Index tests
  def test_index_html_redirects_to_project_settings
    @request.session[:user_id] = 2 # Manager
    get :index, params: { project_id: @project.identifier }
    assert_redirected_to settings_project_path(@project, tab: 'labels')
  end

  # API response tests are covered in integration tests (test/integration/api_test/labels_test.rb)

  def test_index_requires_login
    get :index, params: { project_id: @project.identifier }
    assert_response :found # Redirect to login
  end

  def test_index_requires_project_access
    @request.session[:user_id] = 7 # User without project access
    get :index, params: { project_id: @project.identifier }
    assert_response :forbidden
  end

  # Show tests - API format tests are in integration tests

  # New tests
  def test_new
    @request.session[:user_id] = 2
    get :new, params: { project_id: @project.identifier }
    assert_response :success
    assert_select 'input[name=?]', 'label[name]'
    assert_select 'input[name=?]', 'label[color]'
  end

  def test_new_requires_permission
    @request.session[:user_id] = 7
    get :new, params: { project_id: @project.identifier }
    assert_response :forbidden
  end

  # Create tests
  def test_create_html
    @request.session[:user_id] = 2
    assert_difference 'Label.count', 1 do
      post :create, params: {
        project_id: @project.identifier,
        label: { name: 'New Label', color: '#FF5733' }
      }
    end
    assert_redirected_to settings_project_path(@project, tab: 'labels')
    label = Label.order(:id).last
    assert_equal 'New Label', label.name
    assert_equal '#FF5733', label.color
    assert_equal @project.id, label.project_id
  end

  def test_create_with_invalid_data
    @request.session[:user_id] = 2
    assert_no_difference 'Label.count' do
      post :create, params: {
        project_id: @project.identifier,
        label: { name: '', color: '#FF5733' }
      }
    end
    assert_response :success
    assert_select '#errorExplanation'
  end

  def test_create_requires_permission
    @request.session[:user_id] = 7
    assert_no_difference 'Label.count' do
      post :create, params: {
        project_id: @project.identifier,
        label: { name: 'Test', color: '#FF5733' }
      }
    end
    assert_response :forbidden
  end

  # Create inline tests
  def test_create_inline_with_edit_issues_permission
    @request.session[:user_id] = 2 # Has edit_issues permission
    assert_difference 'Label.count', 1 do
      post :create_inline, params: {
        project_id: @project.identifier,
        name: 'Inline Label'
      }
    end
    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 'Inline Label', json['name']
    assert_match /^#[0-9A-Fa-f]{6}$/, json['color']
    assert json['text_color'].present?
  end

  def test_create_inline_assigns_random_color
    @request.session[:user_id] = 2
    colors = []
    5.times do |i|
      post :create_inline, params: {
        project_id: @project.identifier,
        name: "Random #{i}"
      }
      json = JSON.parse(response.body)
      colors << json['color']
    end
    # Colors come from predefined palette
    colors.each do |color|
      assert_includes LabelsController::INLINE_COLORS, color
    end
  end

  def test_create_inline_strips_whitespace
    @request.session[:user_id] = 2
    post :create_inline, params: {
      project_id: @project.identifier,
      name: '  Trimmed Name  '
    }
    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 'Trimmed Name', json['name']
  end

  def test_create_inline_with_duplicate_name
    @request.session[:user_id] = 2
    post :create_inline, params: {
      project_id: @project.identifier,
      name: 'Bug' # Already exists
    }
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json['errors'].present?
  end

  def test_create_inline_requires_permission
    # Remove manage_labels and edit_issues from user's roles
    Role.find(1).remove_permission!(:manage_labels)
    Role.find(1).remove_permission!(:edit_issues)
    Role.find(2).remove_permission!(:manage_labels)
    Role.find(2).remove_permission!(:edit_issues)

    # User 2 should now be forbidden
    @request.session[:user_id] = 2
    post :create_inline, params: {
      project_id: @project.identifier,
      name: 'Test'
    }
    assert_response :forbidden
  end

  # Edit tests
  def test_edit
    @request.session[:user_id] = 2
    get :edit, params: { id: @label.id }
    assert_response :success
    assert_select 'input[name=?][value=?]', 'label[name]', @label.name
    assert_select 'input[name=?][value=?]', 'label[color]', @label.color
  end

  # Update tests
  def test_update_html
    @request.session[:user_id] = 2
    patch :update, params: {
      id: @label.id,
      label: { name: 'Updated Name', color: '#123456' }
    }
    assert_redirected_to settings_project_path(@project, tab: 'labels')
    @label.reload
    assert_equal 'Updated Name', @label.name
    assert_equal '#123456', @label.color
  end

  def test_update_with_invalid_data
    @request.session[:user_id] = 2
    original_name = @label.name
    patch :update, params: {
      id: @label.id,
      label: { name: '', color: '#FF5733' }
    }
    assert_response :success
    @label.reload
    assert_equal original_name, @label.name
  end

  # Destroy tests
  def test_destroy_html
    @request.session[:user_id] = 2
    assert_difference 'Label.count', -1 do
      delete :destroy, params: { id: @label.id }
    end
    assert_redirected_to settings_project_path(@project, tab: 'labels')
  end

  def test_destroy_removes_associated_issue_labels
    @request.session[:user_id] = 2
    issue_label_count = @label.issue_labels.count
    assert issue_label_count > 0

    assert_difference 'IssueLabel.count', -issue_label_count do
      delete :destroy, params: { id: @label.id }
    end
  end

  def test_destroy_requires_permission
    @request.session[:user_id] = 7
    assert_no_difference 'Label.count' do
      delete :destroy, params: { id: @label.id }
    end
    assert_response :forbidden
  end

  # API key authentication is tested in integration tests
end
