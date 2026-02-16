# frozen_string_literal: true

require_relative '../../test_helper'

class Redmine::ApiTest::JournalsTest < Redmine::ApiTest::Base
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :projects_trackers, :enabled_modules,
           :journals, :journal_details

  # Index tests

  test "GET /issues/:issue_id/journals.json should require authentication" do
    get '/issues/1/journals.json'
    assert_response :unauthorized
  end

  test "GET /issues/:issue_id/journals.json should return journals" do
    get '/issues/1/journals.json', :headers => credentials('jsmith')
    assert_response :success
    assert_equal 'application/json', response.media_type

    json = ActiveSupport::JSON.decode(response.body)
    assert json.key?('journals')
    assert_kind_of Array, json['journals']
    assert json['journals'].size > 0

    first_journal = json['journals'].first
    assert first_journal.key?('id')
    assert first_journal.key?('notes')
    assert first_journal.key?('created_on')
    assert first_journal.key?('private_notes')
  end

  test "GET /issues/:issue_id/journals.xml should return journals" do
    get '/issues/1/journals.xml', :headers => credentials('jsmith')
    assert_response :success
    assert_equal 'application/xml', response.media_type

    assert_select 'journals[type=array]' do
      assert_select 'journal'
    end
  end

  test "GET /issues/:issue_id/journals.json with pagination" do
    issue = Issue.find(1)
    3.times do |i|
      issue.init_journal(User.find(2), "Note #{i}")
      issue.save!
    end

    get '/issues/1/journals.json?limit=2&offset=1', :headers => credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 2, json['limit']
    assert_equal 1, json['offset']
    assert json['total_count'] >= 3
  end

  test "GET /issues/:issue_id/journals.json should not return private notes without permission" do
    issue = Issue.find(1)
    # Create private journal by another user (admin)
    journal = issue.init_journal(User.find(1), "Private comment by admin")
    journal.private_notes = true
    journal.save!

    # jsmith has role 1 on project 1, so remove permission from role 1
    Role.find(1).update!(:permissions => Role.find(1).permissions - [:view_private_notes])

    get '/issues/1/journals.json', :headers => credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    journal_ids = json['journals'].map { |j| j['id'] }
    assert_not_includes journal_ids, journal.id
  end

  test "GET /issues/:issue_id/journals.json should return 404 for non-existent issue" do
    get '/issues/99999/journals.json', :headers => credentials('jsmith')
    assert_response :not_found
  end

  # Show tests

  test "GET /journals/:id.json should require authentication" do
    get '/journals/1.json'
    assert_response :unauthorized
  end

  test "GET /journals/:id.json should return journal details" do
    journal = Journal.find(1)

    get "/journals/#{journal.id}.json", :headers => credentials('jsmith')
    assert_response :success
    assert_equal 'application/json', response.media_type

    json = ActiveSupport::JSON.decode(response.body)
    assert json.key?('journal')
    assert_equal journal.id, json['journal']['id']
    assert json['journal'].key?('issue')
    assert_equal journal.journalized_id, json['journal']['issue']['id']
  end

  test "GET /journals/:id.xml should return journal details" do
    journal = Journal.find(1)

    get "/journals/#{journal.id}.xml", :headers => credentials('jsmith')
    assert_response :success
    assert_equal 'application/xml', response.media_type

    assert_select 'journal' do
      assert_select 'id', :text => journal.id.to_s
      assert_select 'issue[id]'
    end
  end

  test "GET /journals/:id.json should include details" do
    journal = Journal.find(1)

    get "/journals/#{journal.id}.json", :headers => credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert json['journal'].key?('details')
    assert_kind_of Array, json['journal']['details']
  end

  test "GET /journals/:id.json should return 404 for non-existent journal" do
    get '/journals/99999.json', :headers => credentials('jsmith')
    assert_response :not_found
  end

  # Create tests

  test "POST /issues/:issue_id/journals.json should require authentication" do
    post '/issues/1/journals.json', :params => {:journal => {:notes => 'Test'}}
    assert_response :unauthorized
  end

  test "POST /issues/:issue_id/journals.json should create journal" do
    issue = Issue.find(1)

    assert_difference 'Journal.count' do
      post(
        '/issues/1/journals.json',
        :params => {:journal => {:notes => 'New comment via API'}},
        :headers => credentials('jsmith')
      )
    end

    assert_response :created
    assert_equal 'application/json', response.media_type

    json = ActiveSupport::JSON.decode(response.body)
    assert json.key?('journal')
    assert_equal 'New comment via API', json['journal']['notes']
    assert_equal issue.id, json['journal']['issue']['id']

    journal = Journal.find(json['journal']['id'])
    assert_equal 'New comment via API', journal.notes
    assert_equal User.find_by_login('jsmith').id, journal.user_id
  end

  test "POST /issues/:issue_id/journals.xml should create journal" do
    assert_difference 'Journal.count' do
      post(
        '/issues/1/journals.xml',
        :params => {:journal => {:notes => 'XML comment'}},
        :headers => credentials('jsmith')
      )
    end

    assert_response :created
    assert_equal 'application/xml', response.media_type
    assert_select 'journal notes', :text => 'XML comment'
  end

  test "POST /issues/:issue_id/journals.json with private_notes" do
    # jsmith has role 1 on project 1
    Role.find(1).add_permission!(:set_notes_private)

    assert_difference 'Journal.count' do
      post(
        '/issues/1/journals.json',
        :params => {:journal => {:notes => 'Private comment', :private_notes => true}},
        :headers => credentials('jsmith')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal true, json['journal']['private_notes']

    journal = Journal.find(json['journal']['id'])
    assert journal.private_notes
  end

  test "POST /issues/:issue_id/journals.json should return error for empty notes" do
    assert_no_difference 'Journal.count' do
      post(
        '/issues/1/journals.json',
        :params => {:journal => {:notes => ''}},
        :headers => credentials('jsmith')
      )
    end

    assert_response :unprocessable_content
    json = ActiveSupport::JSON.decode(response.body)
    assert json.key?('errors')
  end

  test "POST /issues/:issue_id/journals.json should return 404 for non-existent issue" do
    post '/issues/99999/journals.json',
         :params => {:journal => {:notes => 'Test'}},
         :headers => credentials('jsmith')
    assert_response :not_found
  end

  test "POST /issues/:issue_id/journals.json should return 403 without permission" do
    # jsmith has role 1 on project 1, so remove permission from role 1
    Role.find(1).remove_permission!(:add_issue_notes)

    post '/issues/1/journals.json',
         :params => {:journal => {:notes => 'Test'}},
         :headers => credentials('jsmith')
    assert_response :forbidden
  end

  # Update tests

  test "PUT /journals/:id.json should update journal notes and return updated data" do
    journal = Journal.find(1)

    put(
      "/journals/#{journal.id}.json",
      :params => {:journal => {:notes => 'Updated notes'}},
      :headers => credentials('admin')
    )

    assert_response :success
    assert_equal 'application/json', response.media_type

    json = ActiveSupport::JSON.decode(response.body)
    assert json.key?('journal')
    assert_equal 'Updated notes', json['journal']['notes']
    assert_equal journal.id, json['journal']['id']

    journal.reload
    assert_equal 'Updated notes', journal.notes
  end

  test "PUT /journals/:id.xml should update journal notes and return updated data" do
    journal = Journal.find(1)

    put(
      "/journals/#{journal.id}.xml",
      :params => {:journal => {:notes => 'Updated via XML'}},
      :headers => credentials('admin')
    )

    assert_response :success
    assert_equal 'application/xml', response.media_type

    journal.reload
    assert_equal 'Updated via XML', journal.notes

    assert_select 'journal' do
      assert_select 'notes', :text => 'Updated via XML'
    end
  end

  test "PUT /journals/:id.json should return updated_on and updated_by" do
    journal = Journal.find(1)

    put(
      "/journals/#{journal.id}.json",
      :params => {:journal => {:notes => 'New content'}},
      :headers => credentials('admin')
    )

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)

    assert_not_nil json['journal']['updated_on']
    assert json['journal'].key?('updated_by')
  end

  test "PUT /journals/:id.json should return 403 without permission" do
    journal = Journal.find(1)

    # jsmith has role 1 on project 1
    Role.find(1).remove_permission!(:edit_issue_notes)
    Role.find(1).remove_permission!(:edit_own_issue_notes)

    put "/journals/#{journal.id}.json",
        :params => {:journal => {:notes => 'Hacked'}},
        :headers => credentials('jsmith')

    assert_response :forbidden
  end

  test "PUT /journals/:id.json should return 404 for non-existent journal" do
    put '/journals/99999.json',
        :params => {:journal => {:notes => 'Test'}},
        :headers => credentials('admin')
    assert_response :not_found
  end

  test "PUT /journals/:id.json without details should destroy journal" do
    journal = Journal.find(5)
    assert_equal [], journal.details

    assert_difference('Journal.count', -1) do
      put(
        "/journals/#{journal.id}.json",
        :params => {:journal => {:notes => ''}},
        :headers => credentials('admin')
      )
    end

    # Should return success even when destroyed
    assert_response :success
    assert_nil Journal.find_by(id: 5)
  end

  test "PUT /journals/:id.xml without details should destroy journal" do
    journal = Journal.find(5)
    assert_equal [], journal.details

    assert_difference('Journal.count', -1) do
      put(
        "/journals/#{journal.id}.xml",
        :params => {:journal => {:notes => ''}},
        :headers => credentials('admin')
      )
    end

    assert_response :success
    assert_nil Journal.find_by(id: 5)
  end
end
