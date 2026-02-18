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

class AttachmentFulltextContent < ApplicationRecord
  belongs_to :attachment

  # Valid statuses for fulltext content
  STATUSES = %w[pending indexed failed skipped].freeze

  validates :attachment_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes for filtering by status
  scope :pending, -> { where(status: 'pending') }
  scope :indexed, -> { where(status: 'indexed') }
  scope :failed, -> { where(status: 'failed') }
  scope :skipped, -> { where(status: 'skipped') }
  scope :needs_reindex, -> { where(status: %w[pending failed]) }

  # Scope to find records indexed before a certain time (for re-indexing)
  scope :indexed_before, ->(time) { where('indexed_at < ?', time) }

  # Scope to find records by extractor version
  scope :with_extractor_version, ->(version) { where(extractor_version: version) }
  scope :without_extractor_version, ->(version) { where.not(extractor_version: version) }

  # Mark the content as successfully indexed
  def mark_indexed!(content_text, extractor_version: nil)
    update!(
      content: content_text,
      status: 'indexed',
      error_message: nil,
      extractor_version: extractor_version,
      indexed_at: Time.current
    )
  end

  # Mark the content as failed to index
  def mark_failed!(error_msg, extractor_version: nil)
    update!(
      content: nil,
      status: 'failed',
      error_message: error_msg.to_s.truncate(255),
      extractor_version: extractor_version,
      indexed_at: Time.current
    )
  end

  # Mark the content as skipped (e.g., unsupported file type, too large)
  def mark_skipped!(reason = nil)
    update!(
      content: nil,
      status: 'skipped',
      error_message: reason.to_s.truncate(255),
      indexed_at: Time.current
    )
  end

  # Reset to pending status for re-indexing
  def reset_to_pending!
    update!(
      status: 'pending',
      error_message: nil
    )
  end

  # Check status helpers
  def pending?
    status == 'pending'
  end

  def indexed?
    status == 'indexed'
  end

  def failed?
    status == 'failed'
  end

  def skipped?
    status == 'skipped'
  end

  # Returns true if content has been processed (indexed, failed, or skipped)
  def processed?
    indexed? || failed? || skipped?
  end
end
