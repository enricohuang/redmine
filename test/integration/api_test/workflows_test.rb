# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.

require_relative '../../test_helper'

class Redmine::ApiTest::WorkflowsTest < Redmine::ApiTest::Base
  test "GET /workflows/transitions.json should require admin API user" do
    get '/workflows/transitions.json', :headers => credentials('jsmith')

    assert_response :forbidden
  end

  test "GET /workflows/transitions.json should export transition rows" do
    WorkflowTransition.delete_all
    WorkflowTransition.create!(:tracker_id => 1, :role_id => 2, :old_status_id => 1, :new_status_id => 2)

    get(
      '/workflows/transitions.json',
      :params => {:tracker_id => 1, :role_id => 2},
      :headers => credentials('admin')
    )

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal(
      [{
        'tracker_id' => 1,
        'role_id' => 2,
        'old_status_id' => 1,
        'new_status_id' => 2,
        'author' => false,
        'assignee' => false
      }],
      json['transitions']
    )
  end

  test "PUT /workflows/transitions.json should replace selected transition scope" do
    WorkflowTransition.delete_all
    WorkflowTransition.create!(:tracker_id => 1, :role_id => 2, :old_status_id => 1, :new_status_id => 2)

    put(
      '/workflows/transitions.json',
      :params => {
        :tracker_id => 1,
        :role_id => 2,
        :transitions => [
          {
            :tracker_id => 1,
            :role_id => 2,
            :old_status_id => 2,
            :new_status_id => 3,
            :author => true,
            :assignee => false
          }
        ]
      },
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_not WorkflowTransition.exists?(:tracker_id => 1, :role_id => 2, :old_status_id => 1, :new_status_id => 2)
    transition = WorkflowTransition.find_by!(:tracker_id => 1, :role_id => 2, :old_status_id => 2, :new_status_id => 3)
    assert_equal true, transition.author?
    assert_equal false, transition.assignee?
  end

  test "GET /workflows/permissions.json should export field permission rows" do
    WorkflowPermission.delete_all
    WorkflowPermission.create!(
      :tracker_id => 1,
      :role_id => 2,
      :old_status_id => 1,
      :field_name => 'due_date',
      :rule => 'readonly'
    )

    get(
      '/workflows/permissions.json',
      :params => {:tracker_id => 1, :role_id => 2},
      :headers => credentials('admin')
    )

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal(
      [{
        'tracker_id' => 1,
        'role_id' => 2,
        'old_status_id' => 1,
        'field_name' => 'due_date',
        'rule' => 'readonly'
      }],
      json['permissions']
    )
  end

  test "PUT /workflows/permissions.json should replace selected permission scope" do
    WorkflowPermission.delete_all
    WorkflowPermission.create!(
      :tracker_id => 1,
      :role_id => 2,
      :old_status_id => 1,
      :field_name => 'due_date',
      :rule => 'readonly'
    )

    put(
      '/workflows/permissions.json',
      :params => {
        :tracker_id => 1,
        :role_id => 2,
        :permissions => [
          {
            :tracker_id => 1,
            :role_id => 2,
            :old_status_id => 2,
            :field_name => 'assigned_to_id',
            :rule => 'required'
          }
        ]
      },
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_not WorkflowPermission.exists?(:tracker_id => 1, :role_id => 2, :old_status_id => 1, :field_name => 'due_date')
    assert WorkflowPermission.exists?(:tracker_id => 1, :role_id => 2, :old_status_id => 2, :field_name => 'assigned_to_id', :rule => 'required')
  end

  test "POST /workflows/copy.json should copy workflow rules" do
    WorkflowRule.delete_all
    WorkflowTransition.create!(:tracker_id => 1, :role_id => 2, :old_status_id => 1, :new_status_id => 2)

    post(
      '/workflows/copy.json',
      :params => {
        :source_tracker_id => 1,
        :source_role_id => 2,
        :target_tracker_ids => [3],
        :target_role_ids => [3]
      },
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert WorkflowTransition.exists?(:tracker_id => 3, :role_id => 3, :old_status_id => 1, :new_status_id => 2)
  end
end
