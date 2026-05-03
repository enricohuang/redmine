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

class Redmine::ApiTest::ImportsTest < Redmine::ApiTest::Base
  def teardown
    Import.destroy_all
    super
  end

  test "POST /imports.json should create import and return workflow state" do
    assert_difference 'Import.count' do
      post(
        '/imports.json',
        :params => {
          :type => 'IssueImport',
          :file => uploaded_test_file('import_issues.csv', 'text/csv')
        },
        :headers => credentials('jsmith')
      )
    end

    assert_response :created
    import = json_response['import']
    assert_equal 'IssueImport', import['type']
    assert_equal 'uploaded', import['state']
    assert_match %r{/imports/\d+\z}, response.location
    assert_match /\A[0-9a-f]+\z/, import['identifier']
    assert_equal 2, import['user']['id']
    assert import['file_available']
  end

  test "GET /imports/:id.json should find import by numeric id" do
    import = generate_import

    get "/imports/#{import.id}.json", :headers => credentials('jsmith')

    assert_response :success
    assert_equal import.id, json_response['import']['id']
    assert_equal import.filename, json_response['import']['identifier']
  end

  test "PUT /imports/:id/settings.json should update settings and parse item count" do
    import = generate_import('import_iso8859-1.csv')

    put(
      "/imports/#{import.id}/settings.json",
      :params => {
        :import_settings => {
          :separator => ';',
          :wrapper => '"',
          :encoding => 'ISO-8859-1'
        }
      },
      :headers => credentials('jsmith')
    )

    assert_response :success
    import_json = json_response['import']
    assert_equal 'settings_validated', import_json['state']
    assert_equal 2, import_json['total_items']
    assert_equal 'ISO-8859-1', setting_value(import_json, 'encoding')
    assert_equal ['column A', 'column B', 'column C'], import_json['headers']
  end

  test "PUT /imports/:id/settings.json should return validation error on invalid encoding" do
    import = generate_import('import_iso8859-1.csv')

    put(
      "/imports/#{import.id}/settings.json",
      :params => {
        :import_settings => {
          :separator => ';',
          :wrapper => '"',
          :encoding => 'UTF-8'
        }
      },
      :headers => credentials('jsmith')
    )

    assert_response :unprocessable_content
    errors = json_response['errors']
    assert errors.any? {|message| message.include?('not a valid UTF-8 encoded file')}
  end

  test "GET /imports/:id/mapping.json should auto map fields and persist them" do
    import = generate_import('import_issues_auto_mapping.csv')
    import.settings = {'separator' => ';', 'wrapper' => '"', 'encoding' => 'ISO-8859-1'}
    import.save!

    get "/imports/#{import.id}/mapping.json", :headers => credentials('jsmith')

    assert_response :success
    entries = setting_entries(json_response['import'], 'mapping')
    assert_equal 1, entries['subject']
    assert_equal 10, entries['estimated_hours']
    assert_equal 15, entries['unique_id']

    import.reload
    assert_equal 1, import.mapping['subject']
  end

  test "PUT /imports/:id/mapping.json should update mapping" do
    import = generate_import('import_iso8859-1.csv')
    import.settings = {'separator' => ';', 'wrapper' => '"', 'encoding' => 'ISO-8859-1'}
    import.save!

    put(
      "/imports/#{import.id}/mapping.json",
      :params => {
        :import_settings => {
          :mapping => {
            :project_id => '1',
            :tracker_id => '2',
            :subject => '0'
          }
        }
      },
      :headers => credentials('jsmith')
    )

    assert_response :success
    entries = setting_entries(json_response['import'], 'mapping')
    assert_equal '1', entries['project_id']
    assert_equal '2', entries['tracker_id']
    assert_equal '0', entries['subject']
  end

  test "POST /imports/:id/run.json should import the file and return row results" do
    import = generate_import_with_mapping

    assert_difference 'Issue.count', 3 do
      post "/imports/#{import.id}/run.json", :headers => credentials('jsmith')
    end

    assert_response :success
    import_json = json_response['import']
    assert_equal 'finished', import_json['state']
    assert_equal true, import_json['finished']
    assert_equal 3, import_json['processed_items']
    assert_equal 3, import_json['saved_items']
    assert_equal 0, import_json['unsaved_items']
    assert_equal 3, import_json['items'].size
    assert import_json['items'].all? {|item| item['object_id'].present?}
  end

  private

  def json_response
    ActiveSupport::JSON.decode(response.body)
  end

  def setting_value(import_json, name)
    setting = import_json['settings'].detect {|entry| entry['name'] == name}
    setting && setting['value']
  end

  def setting_entries(import_json, name)
    setting = import_json['settings'].detect {|entry| entry['name'] == name}
    Array(setting && setting['entries']).each_with_object({}) do |entry, entries|
      entries[entry['name']] = entry['value']
    end
  end
end
