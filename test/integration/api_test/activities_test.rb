# frozen_string_literal: true

require_relative '../../test_helper'

class Redmine::ApiTest::ActivitiesTest < Redmine::ApiTest::Base
  fixtures :projects, :trackers, :issue_statuses, :issues,
           :enumerations, :users, :issue_categories,
           :projects_trackers, :roles, :member_roles, :members,
           :enabled_modules, :journals, :journal_details,
           :news, :comments, :documents

  test "GET /activity.json should return activities" do
    get '/activity.json', :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)

    assert json['activities'].is_a?(Array)
    assert_not_nil json['total_count']
    assert_not_nil json['offset']
    assert_not_nil json['limit']
  end

  test "GET /activity.json should return activity details" do
    get '/activity.json', :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)

    if json['activities'].any?
      activity = json['activities'].first
      assert_not_nil activity['type']
      assert_not_nil activity['title']
      assert_not_nil activity['datetime']
      assert_not_nil activity['url']
    end
  end

  test "GET /activity.json with show_issues filter" do
    get '/activity.json', :params => {:show_issues => 1}, :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert json['activities'].is_a?(Array)
  end

  test "GET /activity.json with user_id filter" do
    get '/activity.json', :params => {:user_id => 2}, :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert json['activities'].is_a?(Array)
    json['activities'].each do |activity|
      if activity['author']
        assert_equal 2, activity['author']['id']
      end
    end
  end

  test "GET /activity.json with from date filter" do
    get '/activity.json', :params => {:from => '2006-07-19'}, :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert json['activities'].is_a?(Array)
  end

  test "GET /activity.json with pagination" do
    get '/activity.json', :params => {:limit => 5, :offset => 0}, :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert json['activities'].is_a?(Array)
    assert json['activities'].size <= 5
    assert_equal 0, json['offset']
    assert_equal 5, json['limit']
  end

  test "GET /projects/:project_id/activity.json should return project activities" do
    get '/projects/ecookbook/activity.json', :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)

    assert json['activities'].is_a?(Array)
    json['activities'].each do |activity|
      if activity['project']
        # Activities should be from ecookbook or its subprojects
        assert [1, 3, 4, 5].include?(activity['project']['id'])
      end
    end
  end

  test "GET /projects/:project_id/activity.json with with_subprojects=0" do
    get '/projects/ecookbook/activity.json',
        :params => {:with_subprojects => '0'},
        :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert json['activities'].is_a?(Array)
  end

  test "GET /activity.xml should return XML format" do
    get '/activity.xml', :headers => credentials('admin')

    assert_response :success
    assert_select 'activities' do
      assert_select 'activity', :minimum => 0
    end
  end

  test "GET /activity.json should require authentication when REST API enabled" do
    with_settings :rest_api_enabled => '1' do
      get '/activity.json'
      # Global activity is allowed for anonymous users
      assert_response :success
    end
  end

  test "GET /activity.json with multiple show filters" do
    get '/activity.json',
        :params => {:show_issues => 1, :show_news => 1},
        :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert json['activities'].is_a?(Array)
  end
end
