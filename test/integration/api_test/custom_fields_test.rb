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

class Redmine::ApiTest::CustomFieldsTest < Redmine::ApiTest::Base
  test "GET /custom_fields.xml should return custom fields" do
    get '/custom_fields.xml', :headers => credentials('admin')
    assert_response :success
    assert_equal 'application/xml', response.media_type

    assert_select 'custom_fields' do
      assert_select 'custom_field' do
        assert_select 'name', :text => 'Database'
        assert_select 'description', :text => 'Select one of the databases'
        assert_select 'id', :text => '2'
        assert_select 'customized_type', :text => 'issue'
        assert_select 'possible_values[type=array]' do
          assert_select 'possible_value>value', :text => 'PostgreSQL'
          assert_select 'possible_value>label', :text => 'PostgreSQL'
        end
        assert_select 'trackers[type=array]'
        assert_select 'roles[type=array]'
        assert_select 'visible', :text => 'true'
        assert_select 'editable', :text => 'true'
      end
    end
  end

  test "GET /custom_fields.xml should include value and label for enumeration custom fields" do
    field = IssueCustomField.generate!(:field_format => 'enumeration')
    foo = field.enumerations.create!(:name => 'Foo')
    bar = field.enumerations.create!(:name => 'Bar')

    get '/custom_fields.xml', :headers => credentials('admin')
    assert_response :success

    assert_select 'possible_value' do
      assert_select "value:contains(?) + label:contains(?)", foo.id.to_s, 'Foo'
      assert_select "value:contains(?) + label:contains(?)", bar.id.to_s, 'Bar'
    end
  end

  test "GET /custom_fields/:id.json should return custom field" do
    get '/custom_fields/1.json', :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['custom_field']['id']
    assert_equal 'Database', json['custom_field']['name']
  end

  test "POST /custom_fields.json should require admin API user" do
    post(
      '/custom_fields.json',
      :params => {:type => 'IssueCustomField', :custom_field => {:name => 'Severity', :field_format => 'string'}},
      :headers => credentials('jsmith')
    )

    assert_response :forbidden
  end

  test "POST /custom_fields.json should create custom field" do
    assert_difference 'IssueCustomField.count' do
      post(
        '/custom_fields.json',
        :params => {:type => 'IssueCustomField', :custom_field => {:name => 'Severity', :field_format => 'string'}},
        :headers => credentials('admin')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'Severity', json['custom_field']['name']
  end

  test "PUT /custom_fields/:id.json should update custom field" do
    put(
      '/custom_fields/2.json',
      :params => {:custom_field => {:description => 'Updated through API'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal 'Updated through API', CustomField.find(2).description
  end

  test "DELETE /custom_fields/:id.json should delete unused custom field" do
    field = IssueCustomField.generate!(:name => 'Delete me', :field_format => 'string')

    assert_difference 'IssueCustomField.count', -1 do
      delete "/custom_fields/#{field.id}.json", :headers => credentials('admin')
    end

    assert_response :no_content
  end

  test "custom field enumeration JSON API should manage values" do
    field = IssueCustomField.generate!(:field_format => 'enumeration')

    assert_difference 'CustomFieldEnumeration.count' do
      post(
        "/custom_fields/#{field.id}/enumerations.json",
        :params => {:custom_field_enumeration => {:name => 'Critical'}},
        :headers => credentials('admin')
      )
    end
    assert_response :created
    value = field.enumerations.find_by!(:name => 'Critical')

    get "/custom_fields/#{field.id}/enumerations.json", :headers => credentials('admin')
    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert json['custom_field_enumerations'].any? {|enumeration| enumeration['name'] == 'Critical'}

    put(
      "/custom_fields/#{field.id}/enumerations/#{value.id}.json",
      :params => {:custom_field_enumeration => {:name => 'Blocker'}},
      :headers => credentials('admin')
    )
    assert_response :no_content
    assert_equal 'Blocker', value.reload.name

    put(
      "/custom_fields/#{field.id}/enumerations.json",
      :params => {:custom_field_enumerations => {value.id.to_s => {:name => 'Major', :active => '1'}}},
      :headers => credentials('admin')
    )
    assert_response :no_content
    assert_equal 'Major', value.reload.name

    assert_difference 'CustomFieldEnumeration.count', -1 do
      delete "/custom_fields/#{field.id}/enumerations/#{value.id}.json", :headers => credentials('admin')
    end
    assert_response :no_content
  end
end
