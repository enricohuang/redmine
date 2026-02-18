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

class AttachmentFulltextController < ApplicationController
  # Skip CSRF verification for API calls
  skip_before_action :verify_authenticity_token

  # Authenticate via indexer API key before all actions
  before_action :authenticate_indexer
  before_action :find_attachment, only: [:show, :update]

  # List attachments for fulltext indexing
  # GET /attachments/fulltext.json
  #
  # Parameters:
  #   status - Filter by fulltext status: pending, indexed, failed, skipped (default: pending)
  #   content_type - Filter by content type (e.g., application/pdf)
  #   since - Only return attachments created after this ISO8601 datetime
  #   limit - Maximum number of results (default: 100, max: 1000)
  #   offset - Pagination offset (default: 0)
  def index
    scope = Attachment.where.not(container_id: nil).includes(:fulltext_content)

    # Filter by status
    case params[:status]
    when 'pending', nil
      scope = scope.fulltext_pending
    when 'indexed'
      scope = scope.fulltext_indexed
    when 'failed'
      scope = scope.fulltext_failed
    when 'all'
      scope = scope.fulltext_indexable
    else
      render json: { error: "Invalid status: #{params[:status]}" }, status: :bad_request
      return
    end

    # Filter by content type
    if params[:content_type].present?
      scope = scope.where(content_type: params[:content_type])
    end

    # Filter by created date
    if params[:since].present?
      begin
        since_time = Time.iso8601(params[:since])
        scope = scope.where('attachments.created_on > ?', since_time)
      rescue ArgumentError
        render json: { error: "Invalid 'since' datetime format. Use ISO8601." }, status: :bad_request
        return
      end
    end

    # Filter by extractor version (for re-indexing with new extractors)
    if params[:extractor_version].present?
      scope = scope.joins(:fulltext_content)
                   .where.not(attachment_fulltext_contents: { extractor_version: params[:extractor_version] })
    end

    # Pagination
    limit = [[params[:limit].to_i, 1].max, 1000].min
    limit = 100 if params[:limit].blank?
    offset = [params[:offset].to_i, 0].max

    @total_count = scope.count
    @attachments = scope.order(:id).limit(limit).offset(offset)
    @limit = limit
    @offset = offset

    respond_to do |format|
      format.api
      format.json { render_index_json }
    end
  end

  # Get fulltext status for a single attachment
  # GET /attachments/:id/fulltext.json
  def show
    respond_to do |format|
      format.api
      format.json { render_show_json }
    end
  end

  # Update fulltext content for an attachment
  # PATCH/PUT /attachments/:id/fulltext.json
  #
  # Body:
  # {
  #   "fulltext": {
  #     "content": "Extracted text...",
  #     "status": "indexed",  # indexed, failed, skipped
  #     "error_message": "Optional error message",
  #     "extractor_version": "1.0.0"
  #   }
  # }
  def update
    fulltext_params = params.require(:fulltext).permit(:content, :status, :error_message, :extractor_version)

    fulltext_content = @attachment.fulltext_content || @attachment.build_fulltext_content

    case fulltext_params[:status]
    when 'indexed'
      fulltext_content.mark_indexed!(
        fulltext_params[:content],
        extractor_version: fulltext_params[:extractor_version]
      )
    when 'failed'
      fulltext_content.mark_failed!(
        fulltext_params[:error_message],
        extractor_version: fulltext_params[:extractor_version]
      )
    when 'skipped'
      fulltext_content.mark_skipped!(fulltext_params[:error_message])
    when 'pending'
      fulltext_content.reset_to_pending!
    else
      render json: { error: "Invalid status: #{fulltext_params[:status]}" }, status: :bad_request
      return
    end

    respond_to do |format|
      format.api { render action: 'show' }
      format.json { render_show_json }
    end
  end

  # Batch update fulltext content for multiple attachments
  # POST /attachments/fulltext/batch.json
  #
  # Body:
  # {
  #   "attachments": [
  #     {"id": 123, "content": "Text...", "status": "indexed", "extractor_version": "1.0.0"},
  #     {"id": 124, "status": "failed", "error_message": "Password protected"}
  #   ]
  # }
  def batch_update
    unless params[:attachments].is_a?(Array)
      render json: { error: "Missing or invalid 'attachments' array" }, status: :bad_request
      return
    end

    results = { success: [], errors: [] }

    params[:attachments].each do |item|
      attachment_id = item[:id]
      begin
        attachment = Attachment.find(attachment_id)
        fulltext_content = attachment.fulltext_content || attachment.build_fulltext_content

        case item[:status]
        when 'indexed'
          fulltext_content.mark_indexed!(item[:content], extractor_version: item[:extractor_version])
        when 'failed'
          fulltext_content.mark_failed!(item[:error_message], extractor_version: item[:extractor_version])
        when 'skipped'
          fulltext_content.mark_skipped!(item[:error_message])
        when 'pending'
          fulltext_content.reset_to_pending!
        else
          results[:errors] << { id: attachment_id, error: "Invalid status: #{item[:status]}" }
          next
        end

        results[:success] << { id: attachment_id, status: fulltext_content.status }
      rescue ActiveRecord::RecordNotFound
        results[:errors] << { id: attachment_id, error: 'Attachment not found' }
      rescue StandardError => e
        results[:errors] << { id: attachment_id, error: e.message }
      end
    end

    render json: results
  end

  private

  def authenticate_indexer
    # Check if API is enabled
    unless Setting.attachment_indexer_api_enabled?
      render json: { error: 'Attachment fulltext indexer API is disabled. Enable it in Administration > Settings > API.' },
             status: :service_unavailable
      return
    end

    indexer_key = Setting.attachment_indexer_api_key

    # Get the key from header or parameter
    provided_key = request.headers['X-Redmine-Indexer-Key'] || params[:indexer_key]

    if indexer_key.blank?
      render json: { error: 'Fulltext indexer API key is not configured. Set attachment_indexer_api_key in settings.' },
             status: :service_unavailable
      return
    end

    unless ActiveSupport::SecurityUtils.secure_compare(indexer_key.to_s, provided_key.to_s)
      render json: { error: 'Invalid indexer API key' }, status: :unauthorized
    end
  end

  def find_attachment
    @attachment = Attachment.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Attachment not found' }, status: :not_found
  end

  def render_index_json
    render json: {
      total_count: @total_count,
      offset: @offset,
      limit: @limit,
      attachments: @attachments.map { |a| attachment_json(a) }
    }
  end

  def render_show_json
    render json: { attachment: attachment_json(@attachment, include_content: true) }
  end

  def attachment_json(attachment, include_content: false)
    fc = attachment.fulltext_content

    json = {
      id: attachment.id,
      filename: attachment.filename,
      content_type: attachment.content_type,
      filesize: attachment.filesize,
      created_on: attachment.created_on.iso8601,
      content_url: download_named_attachment_url(attachment, attachment.filename),
      fulltext: {
        status: fc&.status || 'pending',
        indexed_at: fc&.indexed_at&.iso8601,
        extractor_version: fc&.extractor_version,
        error_message: fc&.error_message
      }
    }

    if include_content && fc&.indexed?
      json[:fulltext][:content] = fc.content
    end

    json
  end
end
