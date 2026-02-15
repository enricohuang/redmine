# frozen_string_literal: true

require_relative '../test_helper'

class WebhooksApiE2eTest < Redmine::ApiTest::Base
  # End-to-end test for the full webhook lifecycle via API

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

  test "complete webhook lifecycle via API" do
    # Step 1: Create a webhook
    webhook_url = 'https://e2e-test.example.com/webhook'
    webhook_secret = 'e2e_test_secret_123'
    webhook_events = ['issue.created', 'issue.updated']

    assert_difference 'Webhook.count' do
      post(
        '/webhooks.json',
        params: {
          webhook: {
            url: webhook_url,
            secret: webhook_secret,
            events: webhook_events,
            project_ids: [@project.id],
            active: true
          }
        },
        headers: credentials('jsmith')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    webhook_id = json['webhook']['id']
    assert_not_nil webhook_id
    assert_equal webhook_url, json['webhook']['url']
    assert_equal webhook_events, json['webhook']['events']
    assert_equal true, json['webhook']['active']

    # Step 2: Verify webhook exists by fetching it
    get "/webhooks/#{webhook_id}.json?include=projects", headers: credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal webhook_id, json['webhook']['id']
    assert_equal 1, json['webhook']['projects'].size
    assert_equal @project.id, json['webhook']['projects'][0]['id']

    # Step 3: Verify webhook appears in index
    get '/webhooks.json', headers: credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert json['webhooks'].any? { |w| w['id'] == webhook_id }

    # Step 4: Update the webhook
    updated_url = 'https://e2e-test.example.com/updated-webhook'
    put(
      "/webhooks/#{webhook_id}.json",
      params: {
        webhook: {
          url: updated_url,
          active: false
        }
      },
      headers: credentials('jsmith')
    )

    assert_response :no_content

    # Step 5: Verify the update
    get "/webhooks/#{webhook_id}.json", headers: credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)
    assert_equal updated_url, json['webhook']['url']
    assert_equal false, json['webhook']['active']

    # Step 6: Delete the webhook
    assert_difference 'Webhook.count', -1 do
      delete "/webhooks/#{webhook_id}.json", headers: credentials('jsmith')
    end

    assert_response :no_content

    # Step 7: Verify deletion (should return 404)
    get "/webhooks/#{webhook_id}.json", headers: credentials('jsmith')
    assert_response :not_found
  end

  test "webhook signature verification" do
    # Test that the signature computation matches expected format
    webhook = Webhook.create!(
      url: 'https://test.example.com/webhook',
      user: @user,
      events: ['issue.created'],
      projects: [@project],
      secret: 'test_secret_key'
    )

    payload = '{"type":"issue.created","data":{"issue":{"id":1}}}'
    executor = Webhook::Executor.new(webhook.url, payload, webhook.secret)

    signature = executor.compute_signature
    assert signature.start_with?('sha256=')

    # Verify signature format (sha256= followed by hex string)
    hex_part = signature.sub('sha256=', '')
    assert_equal 64, hex_part.length
    assert_match(/\A[a-f0-9]+\z/, hex_part)

    # Verify the signature can be recomputed
    expected = 'sha256=' + OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new('sha256'),
      webhook.secret,
      payload
    )
    assert_equal expected, signature
  end

  test "webhook only allows projects user has access to" do
    # Create webhook with a valid project ID the user has access to
    assert_difference 'Webhook.count' do
      post(
        '/webhooks.json',
        params: {
          webhook: {
            url: 'https://test.example.com/webhook',
            events: ['issue.created'],
            project_ids: [@project.id],
            active: true
          }
        },
        headers: credentials('jsmith')
      )
    end

    assert_response :created
    json = ActiveSupport::JSON.decode(response.body)
    webhook = Webhook.find(json['webhook']['id'])
    assert_includes webhook.project_ids, @project.id
  end

  test "webhook with invalid events is rejected" do
    assert_no_difference 'Webhook.count' do
      post(
        '/webhooks.json',
        params: {
          webhook: {
            url: 'https://test.example.com/webhook',
            events: ['invalid.event'],
            project_ids: [@project.id],
            active: true
          }
        },
        headers: credentials('jsmith')
      )
    end

    assert_response :unprocessable_content
    json = ActiveSupport::JSON.decode(response.body)
    assert json.key?('errors')
  end

  test "API returns setable events and projects metadata" do
    webhook = Webhook.create!(
      url: 'https://test.example.com/webhook',
      user: @user,
      events: ['issue.created'],
      projects: [@project]
    )

    get "/webhooks/#{webhook.id}.json?include=setable_events,setable_projects",
        headers: credentials('jsmith')
    assert_response :success

    json = ActiveSupport::JSON.decode(response.body)

    # Verify setable_events contains all expected event types
    setable_events = json['webhook']['setable_events']
    assert_includes setable_events, 'issue.created'
    assert_includes setable_events, 'issue.updated'
    assert_includes setable_events, 'issue.deleted'
    assert_includes setable_events, 'wiki_page.created'
    assert_includes setable_events, 'time_entry.created'
    assert_includes setable_events, 'news.created'
    assert_includes setable_events, 'version.created'

    # Verify setable_projects contains accessible projects
    setable_projects = json['webhook']['setable_projects']
    assert setable_projects.any?
    project_ids = setable_projects.map { |p| p['id'] }
    assert_includes project_ids, @project.id
  end
end
