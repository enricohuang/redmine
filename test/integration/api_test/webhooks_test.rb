# frozen_string_literal: true

require_relative '../../test_helper'

class Redmine::ApiTest::WebhooksTest < Redmine::ApiTest::Base
  setup do
    @project = Project.find('ecookbook')
    @user = User.find_by_login('jsmith')
    @role = Role.find_by_name('Manager')
    @role.permissions << :use_webhooks unless @role.permissions.include?(:use_webhooks)
    @role.save!
    Setting.webhooks_enabled = '1'
  end

  teardown do
    Setting.webhooks_enabled = '0'
  end

  # Authentication tests

  test "GET /webhooks.json should require authentication" do
    get '/webhooks.json'
    assert_response :unauthorized
  end

  test "GET /webhooks.xml should require authentication" do
    get '/webhooks.xml'
    assert_response :unauthorized
  end

  # Authorization tests

  test "GET /webhooks.json should return 403 without permission" do
    @role.permissions.delete(:use_webhooks)
    @role.save!
    get '/webhooks.json', :headers => credentials('jsmith')
    assert_response :forbidden
  end

  test "GET /webhooks.json should return 403 when webhooks disabled" do
    with_settings :webhooks_enabled => '0' do
      get '/webhooks.json', :headers => credentials('jsmith')
      assert_response :forbidden
    end
  end

  # Index tests

  test "GET /webhooks.json should return user's webhooks" do
    webhook = create_webhook(user: @user)

    get '/webhooks.json', :headers => credentials('jsmith')
    assert_response :success
    assert_equal 'application/json', response.media_type

    json = ActiveSupport::JSON.decode(response.body)
    assert json.key?('webhooks')
    assert_equal 1, json['webhooks'].size
    assert_equal webhook.id, json['webhooks'][0]['id']
    assert_equal webhook.url, json['webhooks'][0]['url']
    assert_equal webhook.active, json['webhooks'][0]['active']
    assert_equal webhook.events, json['webhooks'][0]['events']
    assert_not_nil json['webhooks'][0]['created_at']
    assert_not_nil json['webhooks'][0]['updated_at']
  end

  test "GET /webhooks.xml should return user's webhooks" do
    webhook = create_webhook(user: @user)

    get '/webhooks.xml', :headers => credentials('jsmith')
    assert_response :success
    assert_equal 'application/xml', response.media_type

    assert_select 'webhooks webhook' do
      assert_select 'id', :text => webhook.id.to_s
      assert_select 'url', :text => webhook.url
      assert_select 'active', :text => 'true'
    end
  end

  test "GET /webhooks.json should not return other user's webhooks" do
    admin = User.find_by_login('admin')
    admin_role = Role.find(1)
    admin_role.permissions << :use_webhooks unless admin_role.permissions.include?(:use_webhooks)
    admin_role.save!

    webhook = create_webhook(user: @user)
    other_webhook = create_webhook(user: admin, url: 'https://other.example.com/hook')

    get '/webhooks.json', :headers => credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['webhooks'].size
    assert_equal webhook.id, json['webhooks'][0]['id']
  end

  test "GET /webhooks.json with pagination should work" do
    3.times { |i| create_webhook(user: @user, url: "https://example.com/hook#{i}") }

    get '/webhooks.json', :headers => credentials('jsmith'), :params => { :limit => 2, :offset => 1 }
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 2, json['webhooks'].size
    assert_equal 3, json['total_count']
    assert_equal 1, json['offset']
    assert_equal 2, json['limit']
  end

  test "GET /webhooks.json with include=projects should include projects" do
    webhook = create_webhook(user: @user, projects: [@project])

    get '/webhooks.json?include=projects', :headers => credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['webhooks'][0]['projects'].size
    assert_equal @project.id, json['webhooks'][0]['projects'][0]['id']
    assert_equal @project.name, json['webhooks'][0]['projects'][0]['name']
    assert_equal @project.identifier, json['webhooks'][0]['projects'][0]['identifier']
  end

  # Show tests

  test "GET /webhooks/:id.json should return webhook details" do
    webhook = create_webhook(user: @user, projects: [@project])

    get "/webhooks/#{webhook.id}.json", :headers => credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Hash, json['webhook']
    assert_equal webhook.id, json['webhook']['id']
    assert_equal webhook.url, json['webhook']['url']
    assert_equal webhook.active, json['webhook']['active']
    assert_equal webhook.events, json['webhook']['events']
  end

  test "GET /webhooks/:id.xml should return webhook details" do
    webhook = create_webhook(user: @user)

    get "/webhooks/#{webhook.id}.xml", :headers => credentials('jsmith')
    assert_response :success

    assert_select 'webhook' do
      assert_select 'id', :text => webhook.id.to_s
      assert_select 'url', :text => webhook.url
    end
  end

  test "GET /webhooks/:id.json should return 404 for other user's webhook" do
    admin = User.find_by_login('admin')
    other_webhook = create_webhook(user: admin, url: 'https://other.example.com/hook')

    get "/webhooks/#{other_webhook.id}.json", :headers => credentials('jsmith')
    assert_response :not_found
  end

  test "GET /webhooks/:id.json should return 404 for non-existent webhook" do
    get "/webhooks/99999.json", :headers => credentials('jsmith')
    assert_response :not_found
  end

  test "GET /webhooks/:id.json with include=projects should include projects" do
    webhook = create_webhook(user: @user, projects: [@project])

    get "/webhooks/#{webhook.id}.json?include=projects", :headers => credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 1, json['webhook']['projects'].size
    assert_equal @project.id, json['webhook']['projects'][0]['id']
  end

  test "GET /webhooks/:id.json with include=setable_events should include setable_events" do
    webhook = create_webhook(user: @user)

    get "/webhooks/#{webhook.id}.json?include=setable_events", :headers => credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert json['webhook'].key?('setable_events')
    assert_includes json['webhook']['setable_events'], 'issue.created'
    assert_includes json['webhook']['setable_events'], 'issue.updated'
    assert_includes json['webhook']['setable_events'], 'issue.deleted'
  end

  test "GET /webhooks/:id.json with include=setable_projects should include setable_projects" do
    webhook = create_webhook(user: @user)

    get "/webhooks/#{webhook.id}.json?include=setable_projects", :headers => credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert json['webhook'].key?('setable_projects')
    assert json['webhook']['setable_projects'].any?
  end

  # Create tests

  test "POST /webhooks.json should create webhook" do
    assert_difference 'Webhook.count' do
      post(
        '/webhooks.json',
        :params => {
          :webhook => {
            :url => 'https://new.example.com/webhook',
            :events => ['issue.created', 'issue.updated'],
            :project_ids => [@project.id],
            :active => true
          }
        },
        :headers => credentials('jsmith')
      )
    end

    assert_response :created
    assert_equal 'application/json', response.media_type

    json = ActiveSupport::JSON.decode(response.body)
    assert_kind_of Hash, json['webhook']
    assert_equal 'https://new.example.com/webhook', json['webhook']['url']
    assert_equal ['issue.created', 'issue.updated'], json['webhook']['events']
    assert_equal true, json['webhook']['active']

    webhook = Webhook.find(json['webhook']['id'])
    assert_equal @user.id, webhook.user_id
    assert_includes webhook.project_ids, @project.id
  end

  test "POST /webhooks.xml should create webhook" do
    assert_difference 'Webhook.count' do
      post(
        '/webhooks.xml',
        :params => {
          :webhook => {
            :url => 'https://new.example.com/webhook',
            :events => ['issue.created'],
            :project_ids => [@project.id]
          }
        },
        :headers => credentials('jsmith')
      )
    end

    assert_response :created
    assert_equal 'application/xml', response.media_type
    assert_select 'webhook url', :text => 'https://new.example.com/webhook'
  end

  test "POST /webhooks.json with invalid parameters should return errors" do
    assert_no_difference 'Webhook.count' do
      post(
        '/webhooks.json',
        :params => {
          :webhook => {
            :url => '',
            :events => ['issue.created'],
            :project_ids => [@project.id]
          }
        },
        :headers => credentials('jsmith')
      )
    end

    assert_response :unprocessable_content
    json = ActiveSupport::JSON.decode(response.body)
    assert json.key?('errors')
    assert_kind_of Array, json['errors']
  end

  test "POST /webhooks.xml with invalid parameters should return errors" do
    assert_no_difference 'Webhook.count' do
      post(
        '/webhooks.xml',
        :params => {
          :webhook => {
            :url => '',
            :events => ['issue.created'],
            :project_ids => [@project.id]
          }
        },
        :headers => credentials('jsmith')
      )
    end

    assert_response :unprocessable_content
    assert_equal 'application/xml', response.media_type
    assert_select 'errors error'
  end

  test "POST /webhooks.json with secret should create webhook with secret" do
    assert_difference 'Webhook.count' do
      post(
        '/webhooks.json',
        :params => {
          :webhook => {
            :url => 'https://new.example.com/webhook',
            :secret => 'mysecret123',
            :events => ['issue.created'],
            :project_ids => [@project.id]
          }
        },
        :headers => credentials('jsmith')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    webhook = Webhook.find(json['webhook']['id'])
    assert_equal 'mysecret123', webhook.secret
    # secret should NOT be in API response
    assert_nil json['webhook']['secret']
  end

  # Update tests

  test "PUT /webhooks/:id.json should update webhook" do
    webhook = create_webhook(user: @user)

    put(
      "/webhooks/#{webhook.id}.json",
      :params => {
        :webhook => {
          :url => 'https://updated.example.com/webhook',
          :active => false
        }
      },
      :headers => credentials('jsmith')
    )

    assert_response :no_content

    webhook.reload
    assert_equal 'https://updated.example.com/webhook', webhook.url
    assert_equal false, webhook.active
  end

  test "PUT /webhooks/:id.xml should update webhook" do
    webhook = create_webhook(user: @user)

    put(
      "/webhooks/#{webhook.id}.xml",
      :params => {
        :webhook => {
          :url => 'https://updated.example.com/webhook'
        }
      },
      :headers => credentials('jsmith')
    )

    assert_response :no_content

    webhook.reload
    assert_equal 'https://updated.example.com/webhook', webhook.url
  end

  test "PUT /webhooks/:id.json with invalid parameters should return errors" do
    webhook = create_webhook(user: @user)

    put(
      "/webhooks/#{webhook.id}.json",
      :params => {
        :webhook => {
          :url => ''
        }
      },
      :headers => credentials('jsmith')
    )

    assert_response :unprocessable_content
    json = ActiveSupport::JSON.decode(response.body)
    assert json.key?('errors')
  end

  test "PUT /webhooks/:id.json should return 404 for other user's webhook" do
    admin = User.find_by_login('admin')
    other_webhook = create_webhook(user: admin, url: 'https://other.example.com/hook')

    put(
      "/webhooks/#{other_webhook.id}.json",
      :params => { :webhook => { :url => 'https://hacked.com' } },
      :headers => credentials('jsmith')
    )

    assert_response :not_found
    assert_equal 'https://other.example.com/hook', other_webhook.reload.url
  end

  # Delete tests

  test "DELETE /webhooks/:id.json should delete webhook" do
    webhook = create_webhook(user: @user)

    assert_difference 'Webhook.count', -1 do
      delete "/webhooks/#{webhook.id}.json", :headers => credentials('jsmith')
    end

    assert_response :no_content
  end

  test "DELETE /webhooks/:id.xml should delete webhook" do
    webhook = create_webhook(user: @user)

    assert_difference 'Webhook.count', -1 do
      delete "/webhooks/#{webhook.id}.xml", :headers => credentials('jsmith')
    end

    assert_response :no_content
  end

  test "DELETE /webhooks/:id.json should return 404 for other user's webhook" do
    admin = User.find_by_login('admin')
    other_webhook = create_webhook(user: admin, url: 'https://other.example.com/hook')

    assert_no_difference 'Webhook.count' do
      delete "/webhooks/#{other_webhook.id}.json", :headers => credentials('jsmith')
    end

    assert_response :not_found
  end

  private

  def create_webhook(url: 'https://example.com/webhook',
                     user: User.find_by_login('jsmith'),
                     events: ['issue.created', 'issue.updated'],
                     projects: [Project.find('ecookbook')],
                     active: true,
                     secret: nil)
    Webhook.create!(
      url: url,
      user: user,
      events: events,
      projects: projects,
      active: active,
      secret: secret
    )
  end
end
