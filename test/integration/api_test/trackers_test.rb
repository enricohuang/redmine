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

class Redmine::ApiTest::TrackersTest < Redmine::ApiTest::Base
  test "GET /trackers.xml should return trackers" do
    Tracker.find(2).update_attribute :core_fields, %w[assigned_to_id due_date]
    get '/trackers.xml'

    assert_response :success
    assert_equal 'application/xml', @response.media_type

    assert_select 'trackers[type=array] tracker id', :text => '2' do
      assert_select '~ name', :text => 'Feature request'
      assert_select '~ description', :text => 'Description for Feature request tracker'
      assert_select '~ enabled_standard_fields[type=array]' do
        assert_select 'enabled_standard_fields>field', :count => 2
        assert_select 'enabled_standard_fields>field', :text => 'assigned_to_id'
        assert_select 'enabled_standard_fields>field', :text => 'due_date'
      end
    end
  end

  test "GET /trackers/:id.json should return tracker" do
    get '/trackers/1.json'

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['tracker']['id']
    assert_equal 'Bug', json['tracker']['name']
    assert_kind_of Array, json['tracker']['enabled_standard_fields']
  end

  test "POST /trackers.json should require admin API user" do
    post(
      '/trackers.json',
      :params => {:tracker => {:name => 'Support', :default_status_id => 1}},
      :headers => credentials('jsmith')
    )

    assert_response :forbidden
  end

  test "POST /trackers.json should create tracker" do
    assert_difference 'Tracker.count' do
      post(
        '/trackers.json',
        :params => {:tracker => {:name => 'Support', :default_status_id => 1}},
        :headers => credentials('admin')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'Support', json['tracker']['name']
  end

  test "PUT /trackers/:id.json should update tracker" do
    put(
      '/trackers/2.json',
      :params => {:tracker => {:description => 'Updated through API'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal 'Updated through API', Tracker.find(2).description
  end

  test "DELETE /trackers/:id.json should delete unused tracker" do
    tracker = Tracker.create!(:name => 'Unused', :default_status_id => 1)

    assert_difference 'Tracker.count', -1 do
      delete "/trackers/#{tracker.id}.json", :headers => credentials('admin')
    end

    assert_response :no_content
  end

  test "DELETE /trackers/:id.json should reject tracker with issues" do
    assert_no_difference 'Tracker.count' do
      delete '/trackers/1.json', :headers => credentials('admin')
    end

    assert_response :unprocessable_content
  end

  test "GET /trackers/fields.json should return tracker fields" do
    get '/trackers/fields.json', :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json['trackers']
    assert json['trackers'].any? {|tracker| tracker['id'] == 1}
  end

  test "PUT /trackers/fields.json should update tracker fields" do
    put(
      '/trackers/fields.json',
      :params => {:trackers => {'1' => {:core_fields => %w[assigned_to_id due_date]}}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal %w[assigned_to_id due_date], Tracker.find(1).core_fields
  end
end
