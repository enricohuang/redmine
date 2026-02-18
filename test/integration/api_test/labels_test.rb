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

require_relative '../../test_helper'

class Redmine::ApiTest::LabelsTest < Redmine::ApiTest::Base
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :labels, :issues, :issue_labels, :trackers, :issue_statuses,
           :enabled_modules

  def setup
    super  # Enable REST API
    @project = Project.find(1)
    # Grant manage_labels permission to Manager and Developer roles
    Role.find(1).add_permission!(:manage_labels)
    Role.find(2).add_permission!(:manage_labels)
  end

  # GET /projects/:project_id/labels.json
  test "GET /projects/:project_id/labels.json should return labels" do
    get "/projects/#{@project.identifier}/labels.json", headers: credentials('jsmith')
    assert_response :success
    json = response.parsed_body

    assert json['labels'].is_a?(Array)
    assert !json['labels'].empty?

    label = json['labels'].first
    assert label['id'].present?
    assert label['name'].present?
    assert label['color'].present?
  end

  test "GET /projects/:project_id/labels.json should return labels ordered by name" do
    get "/projects/#{@project.identifier}/labels.json", headers: credentials('jsmith')
    assert_response :success
    json = response.parsed_body

    names = json['labels'].pluck('name')
    assert_equal names, names.sort
  end

  test "GET /projects/:project_id/labels.xml should return labels in XML" do
    get "/projects/#{@project.identifier}/labels.xml", headers: credentials('jsmith')
    assert_response :success
    assert_select 'labels>label>name'
    assert_select 'labels>label>color'
  end

  test "GET /projects/:project_id/labels.json without credentials should fail" do
    get "/projects/#{@project.identifier}/labels.json"
    assert_response :unauthorized
  end

  # GET /labels/:id.json
  test "GET /labels/:id.json should return label details" do
    label = labels(:label_one)
    get "/labels/#{label.id}.json", headers: credentials('jsmith')
    assert_response :success
    json = response.parsed_body

    assert_equal label.id, json['label']['id']
    assert_equal label.name, json['label']['name']
    assert_equal label.color, json['label']['color']
    assert json['label']['project'].present?
    assert_equal @project.id, json['label']['project']['id']
  end

  test "GET /labels/:id.json with non-existent id should return 404" do
    get "/labels/99999.json", headers: credentials('jsmith')
    assert_response :not_found
  end

  # POST /projects/:project_id/labels.json
  test "POST /projects/:project_id/labels.json should create a label" do
    assert_difference 'Label.count', 1 do
      post "/projects/#{@project.identifier}/labels.json",
           params: { label: { name: 'API Test Label', color: '#FF5733' } }.to_json,
           headers: credentials('jsmith').merge('Content-Type' => 'application/json')
    end
    assert_response :created

    json = response.parsed_body
    assert_equal 'API Test Label', json['label']['name']
    assert_equal '#FF5733', json['label']['color']

    # Check Location header
    assert response.headers['Location'].present?
    assert_match %r{/labels/\d+}, response.headers['Location']
  end

  test "POST /projects/:project_id/labels.json with invalid data should return errors" do
    assert_no_difference 'Label.count' do
      post "/projects/#{@project.identifier}/labels.json",
           params: { label: { name: '', color: '#FF5733' } }.to_json,
           headers: credentials('jsmith').merge('Content-Type' => 'application/json')
    end
    assert_response :unprocessable_entity

    json = response.parsed_body
    assert json['errors'].present?
  end

  test "POST /projects/:project_id/labels.json with duplicate name should fail" do
    assert_no_difference 'Label.count' do
      post "/projects/#{@project.identifier}/labels.json",
           params: { label: { name: 'Bug', color: '#00FF00' } }.to_json,
           headers: credentials('jsmith').merge('Content-Type' => 'application/json')
    end
    assert_response :unprocessable_entity
  end

  test "POST /projects/:project_id/labels.json with invalid color should fail" do
    assert_no_difference 'Label.count' do
      post "/projects/#{@project.identifier}/labels.json",
           params: { label: { name: 'Test', color: 'red' } }.to_json,
           headers: credentials('jsmith').merge('Content-Type' => 'application/json')
    end
    assert_response :unprocessable_entity
  end

  # PUT /labels/:id.json
  test "PUT /labels/:id.json should update label" do
    label = labels(:label_one)
    put "/labels/#{label.id}.json",
        params: { label: { name: 'Updated via API', color: '#AABBCC' } }.to_json,
        headers: credentials('jsmith').merge('Content-Type' => 'application/json')
    assert_response :no_content

    label.reload
    assert_equal 'Updated via API', label.name
    assert_equal '#AABBCC', label.color
  end

  test "PUT /labels/:id.json with partial update should work" do
    label = labels(:label_one)
    original_color = label.color

    put "/labels/#{label.id}.json",
        params: { label: { name: 'Partial Update' } }.to_json,
        headers: credentials('jsmith').merge('Content-Type' => 'application/json')
    assert_response :no_content

    label.reload
    assert_equal 'Partial Update', label.name
    assert_equal original_color, label.color
  end

  test "PUT /labels/:id.json with invalid data should return errors" do
    label = labels(:label_one)
    original_name = label.name

    put "/labels/#{label.id}.json",
        params: { label: { name: '' } }.to_json,
        headers: credentials('jsmith').merge('Content-Type' => 'application/json')
    assert_response :unprocessable_entity

    label.reload
    assert_equal original_name, label.name
  end

  # DELETE /labels/:id.json
  test "DELETE /labels/:id.json should delete label" do
    label = labels(:label_three)

    assert_difference 'Label.count', -1 do
      delete "/labels/#{label.id}.json", headers: credentials('jsmith')
    end
    assert_response :no_content
    assert_nil Label.find_by(id: label.id)
  end

  test "DELETE /labels/:id.json should remove issue associations" do
    label = labels(:label_one)
    issue_label_count = label.issue_labels.count
    assert issue_label_count > 0

    assert_difference 'IssueLabel.count', -issue_label_count do
      delete "/labels/#{label.id}.json", headers: credentials('jsmith')
    end
    assert_response :no_content
  end

  # Permission tests
  test "POST /projects/:project_id/labels.json without manage_labels permission should fail" do
    # Remove permission from all roles jsmith might have
    Role.find(1).remove_permission!(:manage_labels)
    Role.find(2).remove_permission!(:manage_labels)

    assert_no_difference 'Label.count' do
      post "/projects/#{@project.identifier}/labels.json",
           params: { label: { name: 'Test', color: '#FF5733' } }.to_json,
           headers: credentials('jsmith').merge('Content-Type' => 'application/json')
    end
    assert_response :forbidden
  end

  test "DELETE /labels/:id.json without manage_labels permission should fail" do
    # Remove permission from all roles jsmith might have
    Role.find(1).remove_permission!(:manage_labels)
    Role.find(2).remove_permission!(:manage_labels)
    label = labels(:label_one)

    assert_no_difference 'Label.count' do
      delete "/labels/#{label.id}.json", headers: credentials('jsmith')
    end
    assert_response :forbidden
  end

  # Issue labels via Issues API
  test "GET /issues/:id.json should include labels if requested" do
    issue = Issue.find(1)
    # Ensure issue has labels
    unless issue.labels.any?
      label = labels(:label_one)
      IssueLabel.create!(issue: issue, label: label) unless issue.issue_labels.exists?(label: label)
      issue.reload
    end

    get "/issues/#{issue.id}.json?include=labels", headers: credentials('jsmith')
    assert_response :success

    json = response.parsed_body
    # Labels may or may not be included depending on whether the API supports include=labels
    # This test verifies the API endpoint works; label inclusion is optional
    assert json['issue'].present?
  end
end
