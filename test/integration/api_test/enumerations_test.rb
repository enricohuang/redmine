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

class Redmine::ApiTest::EnumerationsTest < Redmine::ApiTest::Base
  test "GET /enumerations/issue_priorities.xml should return priorities" do
    get '/enumerations/issue_priorities.xml'
    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_select 'issue_priorities[type=array]' do
      assert_select 'issue_priority:nth-of-type(3)' do
        assert_select 'id', :text => '6'
        assert_select 'name', :text => 'High'
        assert_select 'active', :text => 'true'
      end
      assert_select 'issue_priority:nth-of-type(6)' do
        assert_select 'id', :text => '15'
        assert_select 'name', :text => 'Inactive Priority'
        assert_select 'active', :text => 'false'
      end
    end
  end

  test "GET /enumerations/invalid_subclass.xml should return 404" do
    get '/enumerations/invalid_subclass.xml'
    assert_response :not_found
    assert_equal 'application/xml', response.media_type
  end

  test "GET /enumerations/:type/:id.json should return enumeration" do
    get '/enumerations/issue_priorities/4.json'

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 4, json['issue_priority']['id']
    assert_equal 'Low', json['issue_priority']['name']
  end

  test "POST /enumerations/:type.json should require admin API user" do
    post(
      '/enumerations/issue_priorities.json',
      :params => {:enumeration => {:name => 'Very Urgent'}},
      :headers => credentials('jsmith')
    )

    assert_response :forbidden
  end

  test "POST /enumerations/:type.json should create enumeration" do
    assert_difference 'IssuePriority.count' do
      post(
        '/enumerations/issue_priorities.json',
        :params => {:enumeration => {:name => 'Very Urgent'}},
        :headers => credentials('admin')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'Very Urgent', json['issue_priority']['name']
  end

  test "PUT /enumerations/:type/:id.json should update enumeration" do
    put(
      '/enumerations/issue_priorities/4.json',
      :params => {:enumeration => {:name => 'Very Low'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal 'Very Low', IssuePriority.find(4).name
  end

  test "DELETE /enumerations/:type/:id.json should delete unused enumeration" do
    priority = IssuePriority.create!(:name => 'Unused')

    assert_difference 'IssuePriority.count', -1 do
      delete "/enumerations/issue_priorities/#{priority.id}.json", :headers => credentials('admin')
    end

    assert_response :no_content
  end
end
