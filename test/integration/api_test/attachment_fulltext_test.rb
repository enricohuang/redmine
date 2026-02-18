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

class Redmine::ApiTest::AttachmentFulltextTest < Redmine::ApiTest::Base
  fixtures :attachments, :issues, :projects, :users

  INDEXER_API_KEY = 'test_indexer_key_12345'

  def setup
    super
    set_fixtures_attachments_directory
    # Enable the indexer API and set the key
    Setting.attachment_indexer_api_enabled = '1'
    Setting.attachment_indexer_api_key = INDEXER_API_KEY
  end

  def teardown
    super
    set_tmp_attachments_directory
    Setting.attachment_indexer_api_enabled = '0'
    Setting.attachment_indexer_api_key = ''
  end

  def indexer_headers
    { 'X-Redmine-Indexer-Key' => INDEXER_API_KEY }
  end

  # Authentication tests

  test "GET /attachments/fulltext.json should return 503 when API is disabled" do
    Setting.attachment_indexer_api_enabled = '0'
    get '/attachments/fulltext.json', headers: indexer_headers
    assert_response :service_unavailable
    json = JSON.parse(response.body)
    assert_includes json['error'], 'disabled'
  end

  test "GET /attachments/fulltext.json should return 503 when API key is not configured" do
    Setting.attachment_indexer_api_key = ''
    get '/attachments/fulltext.json', headers: indexer_headers
    assert_response :service_unavailable
    json = JSON.parse(response.body)
    assert_includes json['error'], 'not configured'
  end

  test "GET /attachments/fulltext.json should return 401 with invalid API key" do
    get '/attachments/fulltext.json', headers: { 'X-Redmine-Indexer-Key' => 'wrong_key' }
    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_includes json['error'], 'Invalid'
  end

  test "GET /attachments/fulltext.json should accept API key via parameter" do
    get '/attachments/fulltext.json', params: { indexer_key: INDEXER_API_KEY }
    assert_response :success
  end

  # Index tests

  test "GET /attachments/fulltext.json should return pending attachments by default" do
    get '/attachments/fulltext.json', headers: indexer_headers
    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?('total_count')
    assert json.key?('attachments')
    assert json['attachments'].is_a?(Array)
  end

  test "GET /attachments/fulltext.json should return attachments with fulltext status" do
    attachment = Attachment.first
    AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'indexed',
      content: 'Test content',
      extractor_version: '1.0.0',
      indexed_at: Time.current
    )

    get '/attachments/fulltext.json', params: { status: 'indexed' }, headers: indexer_headers
    assert_response :success
    json = JSON.parse(response.body)

    indexed_attachment = json['attachments'].find { |a| a['id'] == attachment.id }
    assert_not_nil indexed_attachment
    assert_equal 'indexed', indexed_attachment['fulltext']['status']
    assert_equal '1.0.0', indexed_attachment['fulltext']['extractor_version']
  end

  test "GET /attachments/fulltext.json should filter by status" do
    attachment1 = Attachment.find(1)
    attachment2 = Attachment.find(2)

    AttachmentFulltextContent.create!(attachment: attachment1, status: 'indexed', content: 'test')
    AttachmentFulltextContent.create!(attachment: attachment2, status: 'failed', error_message: 'error')

    get '/attachments/fulltext.json', params: { status: 'failed' }, headers: indexer_headers
    assert_response :success
    json = JSON.parse(response.body)

    assert json['attachments'].all? { |a| a['fulltext']['status'] == 'failed' }
  end

  test "GET /attachments/fulltext.json should support pagination" do
    get '/attachments/fulltext.json', params: { limit: 2, offset: 1 }, headers: indexer_headers
    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 2, json['limit']
    assert_equal 1, json['offset']
    assert json['attachments'].length <= 2
  end

  test "GET /attachments/fulltext.json should filter by content_type" do
    get '/attachments/fulltext.json', params: { content_type: 'application/pdf' }, headers: indexer_headers
    assert_response :success
    json = JSON.parse(response.body)

    json['attachments'].each do |att|
      assert_equal 'application/pdf', att['content_type']
    end
  end

  test "GET /attachments/fulltext.json should filter by since parameter" do
    since_time = 1.hour.ago.iso8601
    get '/attachments/fulltext.json', params: { since: since_time }, headers: indexer_headers
    assert_response :success
  end

  test "GET /attachments/fulltext.json should return 400 for invalid status" do
    get '/attachments/fulltext.json', params: { status: 'invalid' }, headers: indexer_headers
    assert_response :bad_request
  end

  # Show tests

  test "GET /attachments/:id/fulltext.json should return attachment fulltext status" do
    attachment = Attachment.first
    AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'indexed',
      content: 'This is the extracted text',
      extractor_version: '1.0.0'
    )

    get "/attachments/#{attachment.id}/fulltext.json", headers: indexer_headers
    assert_response :success
    json = JSON.parse(response.body)

    assert_equal attachment.id, json['attachment']['id']
    assert_equal attachment.filename, json['attachment']['filename']
    assert_equal 'indexed', json['attachment']['fulltext']['status']
    assert_equal 'This is the extracted text', json['attachment']['fulltext']['content']
  end

  test "GET /attachments/:id/fulltext.json should return pending status for unindexed attachment" do
    attachment = Attachment.first
    attachment.fulltext_content&.destroy

    get "/attachments/#{attachment.id}/fulltext.json", headers: indexer_headers
    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 'pending', json['attachment']['fulltext']['status']
  end

  test "GET /attachments/:id/fulltext.json should return 404 for non-existent attachment" do
    get '/attachments/999999/fulltext.json', headers: indexer_headers
    assert_response :not_found
  end

  # Update tests

  test "PATCH /attachments/:id/fulltext.json should update fulltext as indexed" do
    attachment = Attachment.first
    attachment.fulltext_content&.destroy

    patch(
      "/attachments/#{attachment.id}/fulltext.json",
      params: {
        fulltext: {
          content: 'Extracted text from document',
          status: 'indexed',
          extractor_version: '2.0.0'
        }
      },
      headers: indexer_headers
    )
    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 'indexed', json['attachment']['fulltext']['status']
    assert_equal 'Extracted text from document', json['attachment']['fulltext']['content']
    assert_equal '2.0.0', json['attachment']['fulltext']['extractor_version']

    attachment.reload
    assert attachment.fulltext_content.indexed?
    assert_equal 'Extracted text from document', attachment.fulltext_content.content
  end

  test "PATCH /attachments/:id/fulltext.json should update fulltext as failed" do
    attachment = Attachment.first

    patch(
      "/attachments/#{attachment.id}/fulltext.json",
      params: {
        fulltext: {
          status: 'failed',
          error_message: 'Password protected PDF',
          extractor_version: '2.0.0'
        }
      },
      headers: indexer_headers
    )
    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 'failed', json['attachment']['fulltext']['status']
    assert_equal 'Password protected PDF', json['attachment']['fulltext']['error_message']

    attachment.reload
    assert attachment.fulltext_content.failed?
    assert_equal 'Password protected PDF', attachment.fulltext_content.error_message
  end

  test "PATCH /attachments/:id/fulltext.json should update fulltext as skipped" do
    attachment = Attachment.first

    patch(
      "/attachments/#{attachment.id}/fulltext.json",
      params: {
        fulltext: {
          status: 'skipped',
          error_message: 'Unsupported file type'
        }
      },
      headers: indexer_headers
    )
    assert_response :success

    attachment.reload
    assert attachment.fulltext_content.skipped?
  end

  test "PATCH /attachments/:id/fulltext.json should reset to pending" do
    attachment = Attachment.first
    AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'indexed',
      content: 'old content'
    )

    patch(
      "/attachments/#{attachment.id}/fulltext.json",
      params: { fulltext: { status: 'pending' } },
      headers: indexer_headers
    )
    assert_response :success

    attachment.reload
    assert attachment.fulltext_content.pending?
  end

  test "PATCH /attachments/:id/fulltext.json should return 400 for invalid status" do
    attachment = Attachment.first

    patch(
      "/attachments/#{attachment.id}/fulltext.json",
      params: { fulltext: { status: 'invalid_status' } },
      headers: indexer_headers
    )
    assert_response :bad_request
  end

  # Batch update tests

  test "POST /attachments/fulltext/batch.json should update multiple attachments" do
    attachment1 = Attachment.find(1)
    attachment2 = Attachment.find(2)

    post(
      '/attachments/fulltext/batch.json',
      params: {
        attachments: [
          { id: attachment1.id, content: 'Text from first document', status: 'indexed', extractor_version: '1.0' },
          { id: attachment2.id, status: 'failed', error_message: 'Corrupted file' }
        ]
      },
      headers: indexer_headers
    )
    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 2, json['success'].length
    assert_equal 0, json['errors'].length

    attachment1.reload
    assert attachment1.fulltext_content.indexed?
    assert_equal 'Text from first document', attachment1.fulltext_content.content

    attachment2.reload
    assert attachment2.fulltext_content.failed?
    assert_equal 'Corrupted file', attachment2.fulltext_content.error_message
  end

  test "POST /attachments/fulltext/batch.json should report errors for non-existent attachments" do
    attachment1 = Attachment.first

    post(
      '/attachments/fulltext/batch.json',
      params: {
        attachments: [
          { id: attachment1.id, content: 'Text', status: 'indexed' },
          { id: 999999, content: 'Text', status: 'indexed' }
        ]
      },
      headers: indexer_headers
    )
    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 1, json['success'].length
    assert_equal 1, json['errors'].length
    assert_equal 999999, json['errors'].first['id'].to_i
    assert_includes json['errors'].first['error'], 'not found'
  end

  test "POST /attachments/fulltext/batch.json should return 400 without attachments array" do
    post '/attachments/fulltext/batch.json', params: {}, headers: indexer_headers
    assert_response :bad_request
  end
end
