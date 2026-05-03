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

class Redmine::ApiTest::RolesTest < Redmine::ApiTest::Base
  test "GET /roles.xml should return the roles" do
    get '/roles.xml'

    assert_response :success
    assert_equal 'application/xml', @response.media_type

    assert_select 'roles role', 3
    assert_select 'roles[type=array] role id', :text => '2' do
      assert_select '~ name', :text => 'Developer'
    end
  end

  test "GET /roles.json should return the roles" do
    get '/roles.json'

    assert_response :success
    assert_equal 'application/json', @response.media_type

    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Hash, json
    assert_kind_of Array, json['roles']
    assert_equal 3, json['roles'].size
    assert_include({'id' => 2, 'name' => 'Developer'}, json['roles'])
  end

  test "GET /roles/:id.xml should return the role" do
    get '/roles/1.xml'

    assert_response :success
    assert_equal 'application/xml', @response.media_type

    assert_select 'role' do
      assert_select 'name', :text => 'Manager'
      assert_select 'assignable', :text => 'true'
      assert_select 'issues_visibility', :text => 'all'
      assert_select 'time_entries_visibility', :text => 'all'
      assert_select 'users_visibility', :text => 'all'

      assert_select 'role permissions[type=array]' do
        assert_select 'permission', Role.find(1).permissions.size
        assert_select 'permission', :text => 'view_issues'
      end
    end
  end

  test "GET /roles.json with include_builtin should return built-in roles for admin" do
    get '/roles.json', :params => {:include_builtin => '1'}, :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 5, json['roles'].size
    assert json['roles'].any? {|role| role['id'] == 4 && role['name'] == 'Non member'}
    assert json['roles'].any? {|role| role['id'] == 5 && role['name'] == 'Anonymous'}
  end

  test "POST /roles.json should require admin API user" do
    post(
      '/roles.json',
      :params => {:role => {:name => 'Support'}},
      :headers => credentials('jsmith')
    )

    assert_response :forbidden
  end

  test "POST /roles.json should create role" do
    assert_difference 'Role.count' do
      post(
        '/roles.json',
        :params => {:role => {:name => 'Support', :permissions => %w[view_issues add_issues]}},
        :headers => credentials('admin')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'Support', json['role']['name']
    assert_includes json['role']['permissions'], 'view_issues'
  end

  test "PUT /roles/:id.json should update role" do
    put(
      '/roles/2.json',
      :params => {:role => {:name => 'Developer API'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal 'Developer API', Role.find(2).name
  end

  test "DELETE /roles/:id.json should delete unused role" do
    role = Role.create!(:name => 'Unused')

    assert_difference 'Role.count', -1 do
      delete "/roles/#{role.id}.json", :headers => credentials('admin')
    end

    assert_response :no_content
  end

  test "DELETE /roles/:id.json should reject role in use" do
    assert_no_difference 'Role.count' do
      delete '/roles/1.json', :headers => credentials('admin')
    end

    assert_response :unprocessable_content
  end

  test "GET /roles/permissions.json should export permissions" do
    get '/roles/permissions.json', :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json['roles']
    assert_kind_of Array, json['available_permissions']
  end

  test "PUT /roles/permissions.json should update permissions" do
    put(
      '/roles/permissions.json',
      :params => {:permissions => {'3' => %w[view_issues add_issues]}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal [:view_issues, :add_issues], Role.find(3).permissions
  end
end
