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

class Redmine::ApiTest::WikiPagesTest < Redmine::ApiTest::Base
  test "GET /projects/:project_id/wiki/index.xml should return wiki pages" do
    get '/projects/ecookbook/wiki/index.xml'
    assert_response :ok
    assert_equal 'application/xml', response.media_type
    assert_select 'wiki_pages[type=array]' do
      assert_select 'wiki_page', :count => Wiki.find(1).pages.count
      assert_select 'wiki_page' do
        assert_select 'title', :text => 'CookBook_documentation'
        assert_select 'version', :text => '3'
        assert_select 'created_on'
        assert_select 'updated_on'
      end
      assert_select 'wiki_page' do
        assert_select 'title', :text => 'Page_with_an_inline_image'
        assert_select 'parent[title=?]', 'CookBook_documentation'
      end
    end
  end

  test "GET /projects/:project_id/wiki/:title.xml should return wiki page" do
    get '/projects/ecookbook/wiki/CookBook_documentation.xml'
    assert_response :ok
    assert_equal 'application/xml', response.media_type
    assert_select 'wiki_page' do
      assert_select 'title', :text => 'CookBook_documentation'
      assert_select 'version', :text => '3'
      assert_select 'text'
      assert_select 'author'
      assert_select 'comments'
      assert_select 'project[id=1][name="eCookbook"]'
      assert_select 'created_on'
      assert_select 'updated_on'
    end
  end

  test "GET /projects/:project_id/wiki/:title.xml?include=attachments should include attachments" do
    get '/projects/ecookbook/wiki/Page_with_an_inline_image.xml?include=attachments'
    assert_response :ok
    assert_equal 'application/xml', response.media_type
    assert_select 'wiki_page' do
      assert_select 'title', :text => 'Page_with_an_inline_image'
      assert_select 'attachments[type=array]' do
        assert_select 'attachment' do
          assert_select 'id', :text => '3'
          assert_select 'filename', :text => 'logo.gif'
        end
      end
    end
  end

  test "GET /projects/:project_id/wiki/:title.xml with unknown title and edit permission should respond with 404" do
    get '/projects/ecookbook/wiki/Invalid_Page.xml', :headers => credentials('jsmith')
    assert_response :not_found
    assert_equal 'application/xml', response.media_type
  end

  test "GET /projects/:project_id/wiki/:title/:version.xml should return wiki page version" do
    get '/projects/ecookbook/wiki/CookBook_documentation/2.xml'
    assert_response :ok
    assert_equal 'application/xml', response.media_type
    assert_select 'wiki_page' do
      assert_select 'title', :text => 'CookBook_documentation'
      assert_select 'version', :text => '2'
      assert_select 'text'
      assert_select 'author'
      assert_select 'comments', :text => 'Small update'
      assert_select 'created_on'
      assert_select 'updated_on'
    end
  end

  test "GET /projects/:project_id/wiki/:title/:version.xml without permission should be denied" do
    Role.anonymous.remove_permission! :view_wiki_edits

    get '/projects/ecookbook/wiki/CookBook_documentation/2.xml'
    assert_response :unauthorized
    assert_equal 'application/xml', response.media_type
  end

  test "PUT /projects/:project_id/wiki/:title.xml should update wiki page" do
    assert_no_difference 'WikiPage.count' do
      assert_difference 'WikiContentVersion.count' do
        put(
          '/projects/ecookbook/wiki/CookBook_documentation.xml',
          :params => {
            :wiki_page => {
              :text => 'New content from API',
              :comments => 'API update'
            }
          },
          :headers => credentials('jsmith')
        )
        assert_response :no_content
      end
    end

    page = WikiPage.find(1)
    assert_equal 'New content from API', page.content.text
    assert_equal 4, page.content.version
    assert_equal 'API update', page.content.comments
    assert_equal 'jsmith', page.content.author.login
  end

  test "GET /projects/:project_id/wiki/:title/:version.xml should not includ author if not exists" do
    WikiContentVersion.find_by_id(2).update(author_id: nil)

    get '/projects/ecookbook/wiki/CookBook_documentation/2.xml'
    assert_response :ok
    assert_equal 'application/xml', response.media_type
    assert_select 'wiki_page' do
      assert_select 'author', 0
    end
  end

  test "PUT /projects/:project_id/wiki/:title.xml with current versino should update wiki page" do
    assert_no_difference 'WikiPage.count' do
      assert_difference 'WikiContentVersion.count' do
        put(
          '/projects/ecookbook/wiki/CookBook_documentation.xml',
          :params => {
            :wiki_page => {
              :text => 'New content from API',
              :comments => 'API update',
              :version => '3'
            }
          },
          :headers => credentials('jsmith')
        )
        assert_response :no_content
      end
    end

    page = WikiPage.find(1)
    assert_equal 'New content from API', page.content.text
    assert_equal 4, page.content.version
    assert_equal 'API update', page.content.comments
    assert_equal 'jsmith', page.content.author.login
  end

  test "PUT /projects/:project_id/wiki/:title.xml with stale version should respond with 409" do
    assert_no_difference 'WikiPage.count' do
      assert_no_difference 'WikiContentVersion.count' do
        put(
          '/projects/ecookbook/wiki/CookBook_documentation.xml',
          :params => {
            :wiki_page => {
              :text => 'New content from API',
              :comments => 'API update',
              :version => '2'
            }
          },
          :headers => credentials('jsmith')
        )
        assert_response :conflict
      end
    end
  end

  test "PUT /projects/:project_id/wiki/:title.xml should create the page if it does not exist" do
    assert_difference 'WikiPage.count' do
      assert_difference 'WikiContentVersion.count' do
        put(
          '/projects/ecookbook/wiki/New_page_from_API.xml',
          :params => {
            :wiki_page => {
              :text => 'New content from API',
              :comments => 'API create'
            }
          },
          :headers => credentials('jsmith')
        )
        assert_response :created
      end
    end

    page = WikiPage.order(id: :desc).first
    assert_equal 'New_page_from_API', page.title
    assert_equal 'New content from API', page.content.text
    assert_equal 1, page.content.version
    assert_equal 'API create', page.content.comments
    assert_equal 'jsmith', page.content.author.login
    assert_nil page.parent
  end

  test "PUT /projects/:project_id/wiki/:title.xml with attachment" do
    set_tmp_attachments_directory
    attachment = Attachment.create!(:file => uploaded_test_file("testfile.txt", "text/plain"), :author_id => 2)
    assert_difference 'WikiPage.count' do
      assert_difference 'WikiContentVersion.count' do
        put(
          '/projects/ecookbook/wiki/New_page_from_API.xml',
          :params => {
            :wiki_page => {
              :text => 'New content from API with Attachments',
              :comments => 'API create with Attachments',
              :uploads => [
                :token => attachment.token,
                :filename => 'testfile.txt',
                :content_type => "text/plain"
              ]
            }
          },
          :headers => credentials('jsmith')
        )
        assert_response :created
      end
    end

    page = WikiPage.order(id: :desc).first
    assert_equal 'New_page_from_API', page.title
    assert_include attachment, page.attachments
    assert_equal attachment.filename, page.attachments.first.filename
  end

  test "PUT /projects/:project_id/wiki/:title.xml with parent" do
    assert_difference 'WikiPage.count' do
      assert_difference 'WikiContentVersion.count' do
        put(
          '/projects/ecookbook/wiki/New_subpage_from_API.xml',
          :params => {
            :wiki_page => {
              :parent_title => 'CookBook_documentation',
              :text => 'New content from API',
              :comments => 'API create'
            }
          },
          :headers => credentials('jsmith')
        )
        assert_response :created
      end
    end

    page = WikiPage.order(id: :desc).first
    assert_equal 'New_subpage_from_API', page.title
    assert_equal WikiPage.find(1), page.parent
  end

  test "DELETE /projects/:project_id/wiki/:title.xml should destroy the page" do
    assert_difference 'WikiPage.count', -1 do
      delete '/projects/ecookbook/wiki/CookBook_documentation.xml', :headers => credentials('jsmith')
      assert_response :no_content
    end

    assert_nil WikiPage.find_by_id(1)
  end

  # ==========================================
  # Index with pagination tests
  # ==========================================

  test "GET /projects/:project_id/wiki/index.json should return wiki pages with pagination metadata" do
    get '/projects/ecookbook/wiki/index.json'
    assert_response :ok
    assert_equal 'application/json', response.media_type
    json = ActiveSupport::JSON.decode(response.body)
    assert json['wiki_pages'].is_a?(Array)
    assert_not_nil json['total_count']
    assert_not_nil json['offset']
    assert_not_nil json['limit']
  end

  test "GET /projects/:project_id/wiki/index.json with limit and offset" do
    get '/projects/ecookbook/wiki/index.json?limit=2&offset=1'
    assert_response :ok
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 2, json['limit']
    assert_equal 1, json['offset']
    assert json['wiki_pages'].size <= 2
  end

  test "GET /projects/:project_id/wiki/index.json should include protected attribute" do
    get '/projects/ecookbook/wiki/index.json'
    assert_response :ok
    json = ActiveSupport::JSON.decode(response.body)
    assert json['wiki_pages'].all? { |p| p.key?('protected') }
  end

  # ==========================================
  # Show with protected attribute tests
  # ==========================================

  test "GET /projects/:project_id/wiki/:title.json should include protected attribute" do
    # Reset protected status for this test
    WikiPage.find(1).update_attribute(:protected, false)

    get '/projects/ecookbook/wiki/CookBook_documentation.json'
    assert_response :ok
    json = ActiveSupport::JSON.decode(response.body)
    assert json['wiki_page'].key?('protected')
    assert_equal false, json['wiki_page']['protected']
  end

  # ==========================================
  # History endpoint tests
  # ==========================================

  test "GET /projects/:project_id/wiki/:title/history.json should return version history" do
    get '/projects/ecookbook/wiki/CookBook_documentation/history.json', :headers => credentials('jsmith')
    assert_response :ok
    assert_equal 'application/json', response.media_type
    json = ActiveSupport::JSON.decode(response.body)
    assert_not_nil json['wiki_page']
    assert_equal 'CookBook_documentation', json['wiki_page']['title']
    assert json['wiki_page']['versions'].is_a?(Array)
    assert_not_nil json['wiki_page']['total_count']
    assert_not_nil json['wiki_page']['offset']
    assert_not_nil json['wiki_page']['limit']
  end

  test "GET /projects/:project_id/wiki/:title/history.json should include version details" do
    get '/projects/ecookbook/wiki/CookBook_documentation/history.json', :headers => credentials('jsmith')
    assert_response :ok
    json = ActiveSupport::JSON.decode(response.body)
    versions = json['wiki_page']['versions']
    assert versions.size > 0
    version = versions.first
    assert_not_nil version['version_number']
    assert_not_nil version['updated_on']
  end

  test "GET /projects/:project_id/wiki/:title/history.json with pagination" do
    get '/projects/ecookbook/wiki/CookBook_documentation/history.json?limit=1&offset=0', :headers => credentials('jsmith')
    assert_response :ok
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['wiki_page']['limit']
    assert_equal 0, json['wiki_page']['offset']
    assert json['wiki_page']['versions'].size <= 1
  end

  test "GET /projects/:project_id/wiki/:title/history.xml should return version history" do
    get '/projects/ecookbook/wiki/CookBook_documentation/history.xml', :headers => credentials('jsmith')
    assert_response :ok
    assert_equal 'application/xml', response.media_type
    assert_select 'wiki_page' do
      assert_select 'title', :text => 'CookBook_documentation'
      assert_select 'versions[type=array]' do
        assert_select 'version'
      end
    end
  end

  test "GET /projects/:project_id/wiki/:title/history.json without permission should be denied" do
    Role.anonymous.remove_permission! :view_wiki_edits

    get '/projects/ecookbook/wiki/CookBook_documentation/history.json'
    assert_response :unauthorized
  end

  # ==========================================
  # Rename endpoint tests
  # ==========================================

  test "POST /projects/:project_id/wiki/:title/rename.json should rename page" do
    post(
      '/projects/ecookbook/wiki/CookBook_documentation/rename.json',
      :params => {
        :wiki_page => {
          :title => 'Renamed_CookBook_documentation',
          :redirect_existing_links => '1'
        }
      },
      :headers => credentials('jsmith')
    )
    assert_response :ok
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'Renamed_CookBook_documentation', json['wiki_page']['title']

    # Verify page was renamed
    assert_nil WikiPage.find_by(wiki_id: 1, title: 'CookBook_documentation')
    assert_not_nil WikiPage.find_by(wiki_id: 1, title: 'Renamed_CookBook_documentation')
  end

  test "POST /projects/:project_id/wiki/:title/rename.json with invalid title should return errors" do
    post(
      '/projects/ecookbook/wiki/CookBook_documentation/rename.json',
      :params => {
        :wiki_page => {
          :title => ''
        }
      },
      :headers => credentials('jsmith')
    )
    assert_response :unprocessable_entity
    json = ActiveSupport::JSON.decode(response.body)
    assert json['errors'].present?
  end

  test "POST /projects/:project_id/wiki/:title/rename.json without permission should not change title" do
    Role.find(1).remove_permission! :rename_wiki_pages

    post(
      '/projects/ecookbook/wiki/CookBook_documentation/rename.json',
      :params => {
        :wiki_page => {
          :title => 'New_Title'
        }
      },
      :headers => credentials('jsmith')
    )
    # Without rename permission, title change is ignored via safe_attributes
    # The request succeeds but the title remains unchanged
    assert_response :ok
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'CookBook_documentation', json['wiki_page']['title']

    # Verify page was not renamed
    assert_not_nil WikiPage.find_by(wiki_id: 1, title: 'CookBook_documentation')
    assert_nil WikiPage.find_by(wiki_id: 1, title: 'New_Title')
  end

  # ==========================================
  # Protect endpoint tests
  # ==========================================

  test "POST /projects/:project_id/wiki/:title/protect.json should protect page" do
    page = WikiPage.find(1)
    # Reset protected status for this test
    page.update_attribute(:protected, false)
    assert_equal false, page.protected?

    post(
      '/projects/ecookbook/wiki/CookBook_documentation/protect.json',
      :params => { :protected => '1' },
      :headers => credentials('admin')
    )
    assert_response :ok
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal true, json['wiki_page']['protected']

    page.reload
    assert_equal true, page.protected?
  end

  test "POST /projects/:project_id/wiki/:title/protect.json should unprotect page" do
    page = WikiPage.find(1)
    page.update_attribute(:protected, true)
    assert_equal true, page.protected?

    post(
      '/projects/ecookbook/wiki/CookBook_documentation/protect.json',
      :params => { :protected => '0' },
      :headers => credentials('admin')
    )
    assert_response :ok
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal false, json['wiki_page']['protected']

    page.reload
    assert_equal false, page.protected?
  end

  test "POST /projects/:project_id/wiki/:title/protect.json without permission should be denied" do
    Role.find(1).remove_permission! :protect_wiki_pages

    post(
      '/projects/ecookbook/wiki/CookBook_documentation/protect.json',
      :params => { :protected => '1' },
      :headers => credentials('jsmith')
    )
    assert_response :forbidden
  end
end
