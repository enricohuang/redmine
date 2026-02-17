# frozen_string_literal: true

require_relative '../../test_helper'

class Redmine::ApiTest::DocumentsTest < Redmine::ApiTest::Base
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles,
           :documents, :enumerations, :enabled_modules

  test "GET /projects/:project_id/documents.xml should return documents" do
    get '/projects/ecookbook/documents.xml', :headers => credentials('jsmith')

    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_select 'documents[type=array]' do
      assert_select 'document', 3
      assert_select 'document id', :text => '1'
      assert_select 'document title', :text => 'Test document'
    end
  end

  test "GET /projects/:project_id/documents.json should return documents" do
    get '/projects/ecookbook/documents.json', :headers => credentials('jsmith')

    assert_response :success
    assert_equal 'application/json', response.media_type
    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Hash, json
    assert_kind_of Array, json['documents']
    assert_equal 3, json['documents'].size
    document = json['documents'].find { |d| d['id'] == 1 }
    assert_equal 'Test document', document['title']
    assert_equal 'Document description', document['description']
  end

  test "GET /projects/:project_id/documents.json should support pagination" do
    get '/projects/ecookbook/documents.json', :params => {:limit => 1}, :headers => credentials('jsmith')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['documents'].size
    assert_equal 3, json['total_count']
  end

  test "GET /documents/:id.xml should return document" do
    get '/documents/1.xml', :headers => credentials('jsmith')

    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_select 'document' do
      assert_select 'id', :text => '1'
      assert_select 'title', :text => 'Test document'
      assert_select 'description', :text => 'Document description'
      assert_select 'project[id="1"][name="eCookbook"]'
    end
  end

  test "GET /documents/:id.json should return document" do
    get '/documents/1.json', :headers => credentials('jsmith')

    assert_response :success
    assert_equal 'application/json', response.media_type
    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Hash, json
    document = json['document']
    assert_equal 1, document['id']
    assert_equal 'Test document', document['title']
    assert_equal 1, document['project']['id']
  end

  test "POST /projects/:project_id/documents.xml should create document" do
    assert_difference 'Document.count' do
      post(
        '/projects/ecookbook/documents.xml',
        :params => {:document => {:title => 'API Document', :description => 'Created via API', :category_id => 1}},
        :headers => credentials('admin')
      )
    end

    assert_response :no_content
    document = Document.find_by(:title => 'API Document')
    assert_not_nil document
    assert_equal 'Created via API', document.description
    assert_equal 1, document.project_id
  end

  test "POST /projects/:project_id/documents.json should create document" do
    assert_difference 'Document.count' do
      post(
        '/projects/ecookbook/documents.json',
        :params => {:document => {:title => 'JSON Document', :description => 'Created via JSON API', :category_id => 1}},
        :headers => credentials('admin')
      )
    end

    assert_response :no_content
    document = Document.find_by(:title => 'JSON Document')
    assert_not_nil document
    assert_equal 'Created via JSON API', document.description
  end

  test "POST /projects/:project_id/documents.xml with invalid data should return errors" do
    assert_no_difference 'Document.count' do
      post(
        '/projects/ecookbook/documents.xml',
        :params => {:document => {:title => ''}},
        :headers => credentials('admin')
      )
    end

    assert_response :unprocessable_content
    assert_select 'errors error', :text => "Title cannot be blank"
  end

  test "PUT /documents/:id.xml should update document" do
    put(
      '/documents/1.xml',
      :params => {:document => {:title => 'Updated Document', :description => 'Updated description'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    document = Document.find(1)
    assert_equal 'Updated Document', document.title
    assert_equal 'Updated description', document.description
  end

  test "PUT /documents/:id.json should update document" do
    put(
      '/documents/1.json',
      :params => {:document => {:title => 'JSON Updated'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    document = Document.find(1)
    assert_equal 'JSON Updated', document.title
  end

  test "PUT /documents/:id.xml with invalid data should return errors" do
    put(
      '/documents/1.xml',
      :params => {:document => {:title => ''}},
      :headers => credentials('admin')
    )

    assert_response :unprocessable_content
    assert_select 'errors error', :text => "Title cannot be blank"
  end

  test "DELETE /documents/:id.xml should delete document" do
    assert_difference 'Document.count', -1 do
      delete '/documents/1.xml', :headers => credentials('admin')
    end

    assert_response :no_content
    assert_nil Document.find_by(:id => 1)
  end

  test "DELETE /documents/:id.json should delete document" do
    assert_difference 'Document.count', -1 do
      delete '/documents/2.json', :headers => credentials('admin')
    end

    assert_response :no_content
    assert_nil Document.find_by(:id => 2)
  end
end
