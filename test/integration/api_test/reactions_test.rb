# frozen_string_literal: true

require_relative '../../test_helper'

class Redmine::ApiTest::ReactionsTest < Redmine::ApiTest::Base
  fixtures :projects, :trackers, :issue_statuses, :issues,
           :enumerations, :users, :issue_categories,
           :projects_trackers, :roles, :member_roles, :members,
           :enabled_modules, :journals, :journal_details,
           :news, :messages, :boards, :reactions

  def setup
    super
    Setting.reactions_enabled = '1'
  end

  def teardown
    Setting.reactions_enabled = '0'
    super
  end

  # Index tests

  test "GET /reactions.json should list reactions for an issue" do
    # Issue 1 already has reactions from fixtures (users 1, 2, 3)
    issue = Issue.find(1)

    get '/reactions.json',
        :params => {:object_type => 'Issue', :object_id => issue.id},
        :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)

    assert json['reactions'].is_a?(Array)
    assert_equal 3, json['total_count']  # From fixtures
    assert_equal 'Issue', json['object_type']
    assert_equal issue.id, json['object_id']
  end

  test "GET /reactions.json should return reaction details" do
    issue = Issue.find(1)

    get '/reactions.json',
        :params => {:object_type => 'Issue', :object_id => issue.id},
        :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)

    assert json['reactions'].any?
    reaction = json['reactions'].first
    assert_not_nil reaction['id']
    assert_not_nil reaction['user']['id']
    assert_not_nil reaction['created_on']
  end

  test "GET /reactions.json for journal" do
    # Journal 1 already has a reaction from fixtures (user 2)
    journal = Journal.find(1)

    get '/reactions.json',
        :params => {:object_type => 'Journal', :object_id => journal.id},
        :headers => credentials('admin')

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['total_count']
  end

  test "GET /reactions.json with invalid object_type should fail" do
    get '/reactions.json',
        :params => {:object_type => 'InvalidType', :object_id => 1},
        :headers => credentials('admin')

    assert_response :unprocessable_entity
  end

  test "GET /reactions.json should be accessible to anonymous when object is visible" do
    issue = Issue.find(1)

    get '/reactions.json',
        :params => {:object_type => 'Issue', :object_id => issue.id}

    assert_response :success
  end

  # Create tests

  test "POST /reactions.json should create a reaction" do
    # Use Issue 2 which has no reactions from fixtures
    issue = Issue.find(2)
    assert_difference 'Reaction.count', 1 do
      post '/reactions.json',
           :params => {:object_type => 'Issue', :object_id => issue.id},
           :headers => credentials('jsmith')
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)

    assert_not_nil json['reaction']
    assert_not_nil json['reaction']['id']
    assert_equal 2, json['reaction']['user']['id']
    assert_equal 'Issue', json['reaction']['object_type']
    assert_equal issue.id, json['reaction']['object_id']
  end

  test "POST /reactions.json should return existing reaction if already exists" do
    # User 2 (jsmith) already has reaction on issue 1 from fixtures
    issue = Issue.find(1)

    assert_no_difference 'Reaction.count' do
      post '/reactions.json',
           :params => {:object_type => 'Issue', :object_id => issue.id},
           :headers => credentials('jsmith')
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    assert_not_nil json['reaction']['id']
  end

  test "POST /reactions.json should require authentication" do
    issue = Issue.find(2)

    post '/reactions.json',
         :params => {:object_type => 'Issue', :object_id => issue.id}

    assert_response :unauthorized
  end

  test "POST /reactions.json for journal" do
    # Use journal 2 which has no reaction from user 2
    journal = Journal.find(2)

    assert_difference 'Reaction.count', 1 do
      post '/reactions.json',
           :params => {:object_type => 'Journal', :object_id => journal.id},
           :headers => credentials('jsmith')
    end

    assert_response :created
  end

  # Destroy tests

  test "DELETE /reactions/:id.json should delete a reaction" do
    # User 2 (jsmith) has reaction id 2 on issue 1 from fixtures
    issue = Issue.find(1)
    reaction = Reaction.find(2)  # jsmith's reaction

    assert_difference 'Reaction.count', -1 do
      delete "/reactions/#{reaction.id}.json",
             :params => {:object_type => 'Issue', :object_id => issue.id},
             :headers => credentials('jsmith')
    end

    assert_response :success
  end

  test "DELETE /reactions/:id.json should only delete own reaction" do
    issue = Issue.find(1)
    reaction = Reaction.find(3) # dlopper's reaction (user 3)

    assert_no_difference 'Reaction.count' do
      delete "/reactions/#{reaction.id}.json",
             :params => {:object_type => 'Issue', :object_id => issue.id},
             :headers => credentials('jsmith') # jsmith (user 2) trying to delete
    end

    assert_response :unprocessable_entity
  end

  test "DELETE /reactions/:id.json should require authentication" do
    issue = Issue.find(1)
    reaction = Reaction.find(1)

    delete "/reactions/#{reaction.id}.json",
           :params => {:object_type => 'Issue', :object_id => issue.id}

    assert_response :unauthorized
  end

  # Settings tests

  test "GET /reactions.json should return 403 when reactions disabled" do
    Setting.reactions_enabled = '0'

    get '/reactions.json',
        :params => {:object_type => 'Issue', :object_id => 1},
        :headers => credentials('admin')

    assert_response :forbidden
  end

  # XML format tests

  test "GET /reactions.xml should return XML format" do
    issue = Issue.find(1)

    get '/reactions.xml',
        :params => {:object_type => 'Issue', :object_id => issue.id},
        :headers => credentials('admin')

    assert_response :success
    assert_select 'reactions' do
      assert_select 'reaction', 3  # From fixtures
    end
  end
end
