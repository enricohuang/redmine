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

require_relative '../test_helper'

class AttachmentFulltextControllerTest < Redmine::ControllerTest
  fixtures :projects, :users, :issues, :trackers, :issue_statuses, :attachments

  INDEXER_KEY = 'test-indexer-key-12345'

  def setup
    # Enable the API and set the key
    Setting.attachment_indexer_api_enabled = '1'
    Setting.attachment_indexer_api_key = INDEXER_KEY
    # Set the indexer key header for all requests
    @request.env['HTTP_X_REDMINE_INDEXER_KEY'] = INDEXER_KEY
  end

  def teardown
    Setting.attachment_indexer_api_enabled = '0'
    Setting.attachment_indexer_api_key = ''
  end

  # Authentication tests
  def test_index_requires_api_enabled
    Setting.attachment_indexer_api_enabled = '0'
    get :index, params: { format: 'json' }
    assert_response :service_unavailable
    json = JSON.parse(response.body)
    assert_match /disabled/, json['error']
  end

  def test_index_requires_api_key_configured
    Setting.attachment_indexer_api_key = ''
    get :index, params: { format: 'json' }
    assert_response :service_unavailable
    json = JSON.parse(response.body)
    assert_match /not configured/, json['error']
  end

  def test_index_requires_valid_api_key
    @request.env['HTTP_X_REDMINE_INDEXER_KEY'] = 'wrong-key'
    get :index, params: { format: 'json' }
    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_match /Invalid/, json['error']
  end

  def test_index_accepts_key_in_header
    get :index, params: { format: 'json' }
    assert_response :success
  end

  def test_index_accepts_key_in_params
    @request.env.delete('HTTP_X_REDMINE_INDEXER_KEY')
    get :index, params: { format: 'json', indexer_key: INDEXER_KEY }
    assert_response :success
  end

  # Index tests
  def test_index_returns_attachments
    get :index, params: { format: 'json' }
    assert_response :success
    json = JSON.parse(response.body)

    assert json['attachments'].is_a?(Array)
    assert json['total_count'].is_a?(Integer)
    assert json['offset'].is_a?(Integer)
    assert json['limit'].is_a?(Integer)
  end

  def test_index_filters_by_status_pending
    get :index, params: { format: 'json', status: 'pending' }
    assert_response :success
  end

  def test_index_filters_by_status_indexed
    get :index, params: { format: 'json', status: 'indexed' }
    assert_response :success
  end

  def test_index_filters_by_status_failed
    get :index, params: { format: 'json', status: 'failed' }
    assert_response :success
  end

  def test_index_filters_by_status_all
    get :index, params: { format: 'json', status: 'all' }
    assert_response :success
  end

  def test_index_invalid_status
    get :index, params: { format: 'json', status: 'invalid' }
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_match /Invalid status/, json['error']
  end

  def test_index_filters_by_content_type
    get :index, params: { format: 'json', status: 'all', content_type: 'application/pdf' }
    assert_response :success
  end

  def test_index_filters_by_since
    get :index, params: { format: 'json', status: 'all', since: 1.day.ago.iso8601 }
    assert_response :success
  end

  def test_index_invalid_since_format
    get :index, params: { format: 'json', since: 'not-a-date' }
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_match /Invalid.*datetime/, json['error']
  end

  def test_index_pagination
    get :index, params: { format: 'json', status: 'all', limit: 5, offset: 0 }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 5, json['limit']
    assert_equal 0, json['offset']
  end

  def test_index_limit_max_is_1000
    get :index, params: { format: 'json', status: 'all', limit: 2000 }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1000, json['limit']
  end

  def test_index_default_limit_is_100
    get :index, params: { format: 'json', status: 'all' }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 100, json['limit']
  end

  # Show tests
  def test_show_returns_attachment_details
    attachment = Attachment.first
    get :show, params: { id: attachment.id, format: 'json' }
    assert_response :success
    json = JSON.parse(response.body)

    assert json['attachment'].present?
    assert_equal attachment.id, json['attachment']['id']
    assert_equal attachment.filename, json['attachment']['filename']
  end

  def test_show_not_found
    get :show, params: { id: 99999, format: 'json' }
    assert_response :not_found
    json = JSON.parse(response.body)
    assert_match /not found/, json['error']
  end

  # Update tests
  def test_update_marks_as_indexed
    attachment = Attachment.first
    patch :update, params: {
      id: attachment.id,
      format: 'json',
      fulltext: {
        content: 'Extracted text content from the document.',
        status: 'indexed',
        extractor_version: '1.0.0'
      }
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 'indexed', json['attachment']['fulltext']['status']

    attachment.reload
    assert attachment.fulltext_content.present?
    assert attachment.fulltext_content.indexed?
    assert_equal 'Extracted text content from the document.', attachment.fulltext_content.content
  end

  def test_update_marks_as_failed
    attachment = Attachment.first
    patch :update, params: {
      id: attachment.id,
      format: 'json',
      fulltext: {
        status: 'failed',
        error_message: 'Password protected PDF',
        extractor_version: '1.0.0'
      }
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 'failed', json['attachment']['fulltext']['status']
  end

  def test_update_marks_as_skipped
    attachment = Attachment.first
    patch :update, params: {
      id: attachment.id,
      format: 'json',
      fulltext: {
        status: 'skipped',
        error_message: 'File type not supported'
      }
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 'skipped', json['attachment']['fulltext']['status']
  end

  def test_update_invalid_status
    attachment = Attachment.first
    patch :update, params: {
      id: attachment.id,
      format: 'json',
      fulltext: { status: 'invalid_status' }
    }

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_match /Invalid status/, json['error']
  end

  def test_update_not_found
    patch :update, params: {
      id: 99999,
      format: 'json',
      fulltext: { status: 'indexed', content: 'test' }
    }

    assert_response :not_found
  end

  # Batch update tests
  def test_batch_update_multiple_attachments
    attachments = Attachment.limit(2)
    skip "Need at least 2 attachments" if attachments.count < 2

    post :batch_update, params: {
      format: 'json',
      attachments: [
        { id: attachments[0].id, content: 'Content 1', status: 'indexed', extractor_version: '1.0' },
        { id: attachments[1].id, status: 'skipped', error_message: 'Not supported' }
      ]
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert json['success'].is_a?(Array)
    assert_equal 2, json['success'].length
  end

  def test_batch_update_with_some_errors
    attachment = Attachment.first

    post :batch_update, params: {
      format: 'json',
      attachments: [
        { id: attachment.id, content: 'Content', status: 'indexed' },
        { id: 99999, status: 'indexed', content: 'Test' }
      ]
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert json['success'].length == 1
    assert json['errors'].length == 1
    assert_equal 99999, json['errors'].first['id'].to_i
    assert_match /not found/i, json['errors'].first['error']
  end

  def test_batch_update_missing_attachments_array
    post :batch_update, params: { format: 'json' }

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_match /Missing.*attachments/, json['error']
  end

  def test_batch_update_invalid_status
    attachment = Attachment.first

    post :batch_update, params: {
      format: 'json',
      attachments: [
        { id: attachment.id, status: 'bad_status' }
      ]
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert json['errors'].length == 1
    assert_match /Invalid status/, json['errors'].first['error']
  end
end
