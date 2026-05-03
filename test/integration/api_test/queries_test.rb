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

class Redmine::ApiTest::QueriesTest < Redmine::ApiTest::Base
  test "GET /queries.xml should return queries" do
    get '/queries.xml'

    assert_response :success
    assert_equal 'application/xml', @response.media_type
    assert_select 'queries[type=array] query id', :text => '4' do
      assert_select '~ name', :text => 'Public query for all projects'
    end
  end

  test "GET /queries/:id.json should return visible query" do
    get '/queries/4.json'

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 4, json['query']['id']
    assert_equal 'Public query for all projects', json['query']['name']
  end

  test "POST /queries.json should create query" do
    assert_difference 'IssueQuery.count' do
      post(
        '/queries.json',
        :params => {:type => 'IssueQuery', :query => {:name => 'API query', :visibility => Query::VISIBILITY_PRIVATE}},
        :headers => credentials('admin')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'API query', json['query']['name']
  end

  test "PUT /queries/:id.json should update editable query" do
    query = IssueQuery.create!(:name => 'Editable API query', :user_id => 1, :visibility => Query::VISIBILITY_PRIVATE)

    put(
      "/queries/#{query.id}.json",
      :params => {:query => {:name => 'Updated API query'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal 'Updated API query', query.reload.name
  end

  test "DELETE /queries/:id.json should destroy editable query" do
    query = IssueQuery.create!(:name => 'Delete API query', :user_id => 1, :visibility => Query::VISIBILITY_PRIVATE)

    assert_difference 'IssueQuery.count', -1 do
      delete "/queries/#{query.id}.json", :headers => credentials('admin')
    end

    assert_response :no_content
  end

  test "GET /queries/filter.json should return filter values with API authentication" do
    get(
      '/queries/filter.json',
      :params => {:type => 'IssueQuery', :name => 'status_id'},
      :headers => credentials('admin')
    )

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json
    assert json.any? {|value| value.first == 'New'}
  end
end
