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

class Redmine::ApiTest::RepositoriesTest < Redmine::ApiTest::Base
  def teardown
    FileUtils.rm_rf(@filesystem_repository_path) if @filesystem_repository_path
    super
  end

  test 'GET /projects/:id/repository/:repository_id/entries.json should list repository entries with a limit' do
    with_filesystem_repository do |repository|
      get(
        "/projects/1/repository/#{repository.identifier_param}/entries.json",
        :params => {:limit => 1},
        :headers => credentials('admin')
      )
    end

    assert_response :success
    repository_json = json_response['repository']
    assert_equal 2, repository_json['entries_total_count']
    assert_equal 1, repository_json['entries_limit']
    assert_equal 1, repository_json['entries'].size
    assert_includes %w[dir test.txt], repository_json['entries'].first['name']
  end

  test 'GET /projects/:id/repository/:repository_id/entries.json should support path query parameter' do
    with_filesystem_repository do |repository|
      get(
        "/projects/1/repository/#{repository.identifier_param}/entries.json",
        :params => {:path => 'dir'},
        :headers => credentials('admin')
      )
    end

    assert_response :success
    repository_json = json_response['repository']
    assert_equal 'dir', repository_json['path']
    assert_equal 1, repository_json['entries_total_count']
    assert_equal ['child.txt'], repository_json['entries'].map {|entry| entry['name']}
  end

  test 'GET /projects/:id/repository/:repository_id/revisions.json should return changesets' do
    get '/projects/1/repository/10/revisions.json', :headers => credentials('jsmith')

    assert_response :success
    json = json_response
    assert_operator json['total_count'], :>, 0
    revisions = json['changesets'].map {|changeset| changeset['revision']}
    assert_includes revisions, '4'
  end

  test 'GET /projects/:id/repository/:repository_id/revisions/:rev.json should return changeset filechanges' do
    get '/projects/1/repository/10/revisions/1.json', :headers => credentials('jsmith')

    assert_response :success
    changeset = json_response['changeset']
    assert_equal '1', changeset['revision']
    assert_equal 2, changeset['filechanges_total_count']
    assert_equal %w[A A], changeset['filechanges'].map {|change| change['action']}
    assert_includes changeset['filechanges'].map {|change| change['path']}, '/test/some/path/in/the/repo'
  end

  test 'GET /projects/:id/repository/:repository_id/revisions/:rev.json should hide filechanges without browse permission' do
    Role.find(1).remove_permission! :browse_repository
    Role.find(1).add_permission! :view_changesets

    get '/projects/1/repository/10/revisions/1.json', :headers => credentials('jsmith')

    assert_response :success
    changeset = json_response['changeset']
    assert_equal 0, changeset['filechanges_total_count']
    assert_equal [], changeset['filechanges']
  end

  test 'POST /projects/:id/repository/:repository_id/revisions/:rev/issues.xml should add related issue' do
    changeset = Changeset.find(103)
    assert_equal [], changeset.issue_ids
    assert_difference 'Changeset.find(103).issues.size' do
      post '/projects/1/repository/10/revisions/4/issues.xml', :headers => credentials('jsmith'), :params => {:issue_id => '2'}
    end
    assert_response :no_content
    assert_equal [2], changeset.reload.issue_ids
  end

  test 'POST /projects/:id/repository/:repository_id/revisions/:rev/issues.json should add related issue' do
    changeset = Changeset.find(103)
    assert_equal [], changeset.issue_ids
    assert_difference 'Changeset.find(103).issues.size' do
      post '/projects/1/repository/10/revisions/4/issues.json', :headers => credentials('jsmith'), :params => {:issue_id => '2'}
    end
    assert_response :no_content
    assert_equal [2], changeset.reload.issue_ids
  end

  test 'POST /projects/:id/repository/:repository_id/revisions/:rev/issues.xml should accept issue_id with sharp' do
    changeset = Changeset.find(103)
    assert_equal [], changeset.issue_ids
    assert_difference 'Changeset.find(103).issues.size' do
      post '/projects/1/repository/10/revisions/4/issues.xml', :headers => credentials('jsmith'), :params => {:issue_id => '#2'}
    end
    assert_response :no_content
    assert_equal [2], changeset.reload.issue_ids
  end

  test 'POST /projects/:id/repository/:repository_id/revisions/:rev/issues.json should accept issue_id with sharp' do
    changeset = Changeset.find(103)
    assert_equal [], changeset.issue_ids
    assert_difference 'Changeset.find(103).issues.size' do
      post '/projects/1/repository/10/revisions/4/issues.json', :headers => credentials('jsmith'), :params => {:issue_id => '#2'}
    end
    assert_response :no_content
    assert_equal [2], changeset.reload.issue_ids
  end

  test 'POST /projects/:id/repository/:repository_id/revisions/:rev/issues.xml with invalid issue_id' do
    assert_no_difference 'Changeset.find(103).issues.size' do
      post '/projects/1/repository/10/revisions/4/issues.xml', :headers => credentials('jsmith'), :params => {:issue_id => '9999'}
    end
    assert_response :unprocessable_content
    assert_select 'errors error', :text => 'Issue is invalid'
  end

  test 'POST /projects/:id/repository/:repository_id/revisions/:rev/issues.json with invalid issue_id' do
    assert_no_difference 'Changeset.find(103).issues.size' do
      post '/projects/1/repository/10/revisions/4/issues.json', :headers => credentials('jsmith'), :params => {:issue_id => '9999'}
    end
    assert_response :unprocessable_content
    json = ActiveSupport::JSON.decode(response.body)
    assert json['errors'].include?('Issue is invalid')
  end

  test 'DELETE /projects/:id/repository/:repository_id/revisions/:rev/issues/:issue_id.xml should remove related issue' do
    changeset = Changeset.find(103)
    changeset.issues << Issue.find(1)
    changeset.issues << Issue.find(2)
    assert_difference 'Changeset.find(103).issues.size', -1 do
      delete '/projects/1/repository/10/revisions/4/issues/2.xml', :headers => credentials('jsmith')
    end
    assert_response :no_content
    assert_equal [1], changeset.reload.issue_ids
  end

  test 'DELETE /projects/:id/repository/:repository_id/revisions/:rev/issues/:issue_id.json should remove related issue' do
    changeset = Changeset.find(103)
    changeset.issues << Issue.find(1)
    changeset.issues << Issue.find(2)
    assert_difference 'Changeset.find(103).issues.size', -1 do
      delete '/projects/1/repository/10/revisions/4/issues/2.json', :headers => credentials('jsmith')
    end
    assert_response :no_content
    assert_equal [1], changeset.reload.issue_ids
  end

  private

  def json_response
    ActiveSupport::JSON.decode(response.body)
  end

  def with_filesystem_repository
    @filesystem_repository_path = Rails.root.join('tmp/test/api_filesystem_repository').to_s
    FileUtils.rm_rf(@filesystem_repository_path)
    FileUtils.mkdir_p(File.join(@filesystem_repository_path, 'dir'))
    File.write(File.join(@filesystem_repository_path, 'test.txt'), "hello\n")
    File.write(File.join(@filesystem_repository_path, 'dir', 'child.txt'), "child\n")

    with_settings :enabled_scm => (Setting.enabled_scm + ['Filesystem']).uniq do
      repository =
        Repository::Filesystem.create!(
          :project => Project.find(1),
          :identifier => 'api-fs',
          :url => @filesystem_repository_path,
          :path_encoding => ''
        )
      yield repository
    end
  end
end
