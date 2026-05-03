# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.

require_relative '../../test_helper'

class Redmine::ApiTest::AuthSourcesTest < Redmine::ApiTest::Base
  test "GET /auth_sources.json should require admin API user" do
    get '/auth_sources.json', :headers => credentials('jsmith')

    assert_response :forbidden
  end

  test "GET /auth_sources.json should return auth sources without passwords" do
    AuthSource.find(1).update!(:account_password => 'ldap-secret')

    get '/auth_sources.json', :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json['auth_sources']
    auth_source = json['auth_sources'].detect {|source| source['id'] == 1}
    assert_equal 'LDAP test server', auth_source['name']
    assert_equal true, auth_source['has_account_password']
    assert_not_includes response.body, 'ldap-secret'
    assert_not_includes auth_source.keys, 'account_password'
  end

  test "GET /auth_sources/:id.json should return auth source without password" do
    AuthSource.find(1).update!(:account => 'cn=admin,dc=example,dc=com', :account_password => 'ldap-secret')

    get '/auth_sources/1.json', :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    auth_source = json['auth_source']
    assert_equal 1, auth_source['id']
    assert_equal 'cn=admin,dc=example,dc=com', auth_source['account']
    assert_equal true, auth_source['has_account_password']
    assert_not_includes response.body, 'ldap-secret'
    assert_not_includes auth_source.keys, 'account_password'
  end

  test "POST /auth_sources.json should create LDAP auth source" do
    assert_difference 'AuthSourceLdap.count' do
      post(
        '/auth_sources.json',
        :params => {
          :type => 'AuthSourceLdap',
          :auth_source => {
            :name => 'API LDAP',
            :host => 'ldap.example.test',
            :port => 389,
            :base_dn => 'dc=example,dc=test',
            :attr_login => 'uid',
            :account_password => 'ldap-secret'
          }
        },
        :headers => credentials('admin')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 'API LDAP', json['auth_source']['name']
    assert_equal true, json['auth_source']['has_account_password']
    assert_not_includes response.body, 'ldap-secret'
  end

  test "PUT /auth_sources/:id.json should update auth source" do
    put(
      '/auth_sources/1.json',
      :params => {:auth_source => {:name => 'Updated LDAP'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal 'Updated LDAP', AuthSource.find(1).name
  end

  test "POST /auth_sources/:id/test_connection.json should test connection" do
    AuthSourceLdap.any_instance.expects(:test_connection).once

    post '/auth_sources/1/test_connection.json', :headers => credentials('admin')

    assert_response :no_content
  end

  test "DELETE /auth_sources/:id.json should delete unused auth source" do
    auth_source = AuthSourceLdap.create!(
      :name => 'Unused LDAP',
      :host => 'ldap.example.test',
      :port => 389,
      :base_dn => 'dc=example,dc=test',
      :attr_login => 'uid'
    )

    assert_difference 'AuthSource.count', -1 do
      delete "/auth_sources/#{auth_source.id}.json", :headers => credentials('admin')
    end

    assert_response :no_content
  end
end
