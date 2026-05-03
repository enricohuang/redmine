# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

require_relative '../../test_helper'

class Redmine::ApiTest::AdminSettingsTest < Redmine::ApiTest::Base
  test "GET /admin/info.json should require admin API user" do
    get '/admin/info.json', :headers => credentials('jsmith')

    assert_response :forbidden
  end

  test "GET /admin/info.json should return checklist" do
    get '/admin/info.json', :headers => credentials('admin')

    assert_response :success
    assert_equal 'application/json', @response.media_type

    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Array, json['admin_info']['checklist']
    assert json['admin_info']['checklist'].any? {|check| check['key'] == 'text_default_administrator_account_changed'}
  end

  test "POST /admin/test_email.json should send test email to current user" do
    Mailer.expects(:deliver_test_email).with(User.find(1))

    post '/admin/test_email.json', :headers => credentials('admin')

    assert_response :no_content
  end

  test "POST /admin/default_configuration.json should load default data" do
    Redmine::DefaultData::Loader.expects(:load).with('en')

    post '/admin/default_configuration.json', :params => {:lang => 'en'}, :headers => credentials('admin')

    assert_response :no_content
  end

  test "GET /settings.json should require admin API user" do
    get '/settings.json', :headers => credentials('jsmith')

    assert_response :forbidden
  end

  test "GET /settings.json should return settings without secret values" do
    Setting.sys_api_key = 'secret-system-key'

    get '/settings.json', :headers => credentials('admin')

    assert_response :success
    assert_equal 'application/json', @response.media_type

    json = ActiveSupport::JSON.decode(response.body)
    settings = json['settings']
    assert_kind_of Array, settings

    app_title = settings.detect {|setting| setting['name'] == 'app_title'}
    assert_equal Setting.app_title, app_title['value']
    assert_equal false, app_title['sensitive']

    sys_api_key = settings.detect {|setting| setting['name'] == 'sys_api_key'}
    assert_equal true, sys_api_key['sensitive']
    assert_equal true, sys_api_key['has_value']
    assert_not_includes response.body, 'secret-system-key'
  end

  test "PUT /settings.json should update settings" do
    put(
      '/settings.json',
      :params => {:settings => {:app_title => 'API Managed Redmine'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal 'API Managed Redmine', Setting.app_title
  end

  test "PUT /settings.json should return validation errors" do
    put(
      '/settings.json',
      :params => {:settings => {:mail_from => 'not-an-email'}},
      :headers => credentials('admin')
    )

    assert_response :unprocessable_content
    assert_includes response.body, 'mail_from'
  end

  test "GET /settings/plugin/:id.json should mask plugin secrets" do
    Redmine::Plugin.register(:foo) do
      settings :partial => 'not blank',
               :default => {
                 'sample_setting' => 'Plugin setting value',
                 'api_key' => 'plugin-secret-key'
               }
      directory 'test/fixtures/plugins/foo_plugin'
    end
    Setting.plugin_foo = {'sample_setting' => 'Visible value', 'api_key' => 'plugin-secret-key'}

    get '/settings/plugin/foo.json', :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    settings = json['plugin_setting']['settings']
    sample_setting = settings.detect {|setting| setting['name'] == 'sample_setting'}
    api_key = settings.detect {|setting| setting['name'] == 'api_key'}

    assert_equal 'Visible value', sample_setting['value']
    assert_equal true, api_key['sensitive']
    assert_equal true, api_key['has_value']
    assert_not_includes response.body, 'plugin-secret-key'
  ensure
    Redmine::Plugin.unregister(:foo)
  end

  test "PUT /settings/plugin/:id.json should update plugin settings" do
    Redmine::Plugin.register(:foo) do
      settings :partial => 'not blank',
               :default => {'sample_setting' => 'Plugin setting value'}
      directory 'test/fixtures/plugins/foo_plugin'
    end

    put(
      '/settings/plugin/foo.json',
      :params => {:settings => {'sample_setting' => 'Updated value'}},
      :headers => credentials('admin')
    )

    assert_response :no_content
    assert_equal({'sample_setting' => 'Updated value'}, Setting.plugin_foo)
  ensure
    Redmine::Plugin.unregister(:foo)
  end
end
