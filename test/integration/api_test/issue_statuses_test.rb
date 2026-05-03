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

class Redmine::ApiTest::IssueStatusesTest < Redmine::ApiTest::Base
  test "GET /issue_statuses.xml should return issue statuses" do
    get '/issue_statuses.xml'

    assert_response :success
    assert_equal 'application/xml', @response.media_type
    assert_select 'issue_statuses[type=array] issue_status id', :text => '2' do
      assert_select '~ name', :text => 'Assigned'
      assert_select '~ is_closed', :text => 'false'
      assert_select '~ description', :text => 'Description for Assigned issue status'
    end
  end

  test "GET /issue_statuses/:id.json should return issue status" do
    get '/issue_statuses/2.json'

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 2, json['issue_status']['id']
    assert_equal 'Assigned', json['issue_status']['name']
  end

  test "POST /issue_statuses.json should require admin API user" do
    post(
      '/issue_statuses.json',
      :params => {:issue_status => {:name => 'QA Review'}},
      :headers => credentials('jsmith')
    )

    assert_response :forbidden
  end

  test "POST /issue_statuses.json should create issue status" do
    assert_difference 'IssueStatus.count' do
      post(
        '/issue_statuses.json',
        :params => {:issue_status => {:name => 'QA Review', :default_done_ratio => 50}},
        :headers => credentials('admin')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'QA Review', json['issue_status']['name']
  end

  test "PUT /issue_statuses/:id.json should update issue status" do
    put(
      '/issue_statuses/2.json',
      :params => {:issue_status => {:description => 'Updated through API'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal 'Updated through API', IssueStatus.find(2).description
  end

  test "DELETE /issue_statuses/:id.json should delete unused issue status" do
    status = IssueStatus.create!(:name => 'Unused')

    assert_difference 'IssueStatus.count', -1 do
      delete "/issue_statuses/#{status.id}.json", :headers => credentials('admin')
    end

    assert_response :no_content
  end

  test "POST /issue_statuses/update_issue_done_ratio.json should synchronize ratios" do
    with_settings :issue_done_ratio => 'issue_status' do
      post '/issue_statuses/update_issue_done_ratio.json', :headers => credentials('admin')
    end

    assert_response :no_content
  end
end
