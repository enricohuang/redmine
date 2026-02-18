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

class AttachmentFulltextContentTest < ActiveSupport::TestCase
  fixtures :attachments, :issues, :projects, :users

  def setup
    User.current = nil
    set_tmp_attachments_directory
    # Clean up any existing fulltext content to avoid uniqueness violations
    AttachmentFulltextContent.delete_all
  end

  def test_create_with_valid_status
    attachment = Attachment.find(1)
    fulltext = AttachmentFulltextContent.new(
      attachment: attachment,
      status: 'pending'
    )
    assert fulltext.save
  end

  def test_create_with_invalid_status
    attachment = Attachment.find(1)
    fulltext = AttachmentFulltextContent.new(
      attachment: attachment,
      status: 'invalid_status'
    )
    assert_not fulltext.valid?
    assert_includes fulltext.errors[:status], 'is not included in the list'
  end

  def test_attachment_association
    attachment = Attachment.find(1)
    fulltext = AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'pending'
    )
    assert_equal attachment, fulltext.attachment
  end

  def test_uniqueness_of_attachment
    attachment = Attachment.find(1)
    AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'pending'
    )
    duplicate = AttachmentFulltextContent.new(
      attachment: attachment,
      status: 'pending'
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:attachment_id], 'has already been taken'
  end

  def test_mark_indexed
    attachment = Attachment.find(1)
    fulltext = AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'pending'
    )

    fulltext.mark_indexed!('This is the extracted text content', extractor_version: '1.0.0')

    assert fulltext.indexed?
    assert_equal 'indexed', fulltext.status
    assert_equal 'This is the extracted text content', fulltext.content
    assert_equal '1.0.0', fulltext.extractor_version
    assert_not_nil fulltext.indexed_at
    assert_nil fulltext.error_message
  end

  def test_mark_failed
    attachment = Attachment.find(1)
    fulltext = AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'pending'
    )

    fulltext.mark_failed!('Password protected file', extractor_version: '1.0.0')

    assert fulltext.failed?
    assert_equal 'failed', fulltext.status
    assert_nil fulltext.content
    assert_equal 'Password protected file', fulltext.error_message
    assert_equal '1.0.0', fulltext.extractor_version
    assert_not_nil fulltext.indexed_at
  end

  def test_mark_skipped
    attachment = Attachment.find(1)
    fulltext = AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'pending'
    )

    fulltext.mark_skipped!('Unsupported file type')

    assert fulltext.skipped?
    assert_equal 'skipped', fulltext.status
    assert_equal 'Unsupported file type', fulltext.error_message
    assert_not_nil fulltext.indexed_at
  end

  def test_reset_to_pending
    attachment = Attachment.find(1)
    fulltext = AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'indexed',
      content: 'Some content',
      extractor_version: '1.0.0',
      indexed_at: Time.current
    )

    fulltext.reset_to_pending!

    assert fulltext.pending?
    assert_equal 'pending', fulltext.status
    assert_nil fulltext.error_message
  end

  def test_status_predicates
    fulltext = AttachmentFulltextContent.new

    fulltext.status = 'pending'
    assert fulltext.pending?
    assert_not fulltext.indexed?
    assert_not fulltext.failed?
    assert_not fulltext.skipped?
    assert_not fulltext.processed?

    fulltext.status = 'indexed'
    assert_not fulltext.pending?
    assert fulltext.indexed?
    assert_not fulltext.failed?
    assert_not fulltext.skipped?
    assert fulltext.processed?

    fulltext.status = 'failed'
    assert_not fulltext.pending?
    assert_not fulltext.indexed?
    assert fulltext.failed?
    assert_not fulltext.skipped?
    assert fulltext.processed?

    fulltext.status = 'skipped'
    assert_not fulltext.pending?
    assert_not fulltext.indexed?
    assert_not fulltext.failed?
    assert fulltext.skipped?
    assert fulltext.processed?
  end

  def test_scope_pending
    attachment1 = Attachment.find(1)
    attachment2 = Attachment.find(2)

    AttachmentFulltextContent.create!(attachment: attachment1, status: 'pending')
    AttachmentFulltextContent.create!(attachment: attachment2, status: 'indexed', content: 'test')

    pending_records = AttachmentFulltextContent.pending
    assert_equal 1, pending_records.count
    assert_equal attachment1.id, pending_records.first.attachment_id
  end

  def test_scope_indexed
    attachment1 = Attachment.find(1)
    attachment2 = Attachment.find(2)

    AttachmentFulltextContent.create!(attachment: attachment1, status: 'pending')
    AttachmentFulltextContent.create!(attachment: attachment2, status: 'indexed', content: 'test')

    indexed_records = AttachmentFulltextContent.indexed
    assert_equal 1, indexed_records.count
    assert_equal attachment2.id, indexed_records.first.attachment_id
  end

  def test_scope_failed
    attachment1 = Attachment.find(1)
    attachment2 = Attachment.find(2)

    AttachmentFulltextContent.create!(attachment: attachment1, status: 'failed', error_message: 'error')
    AttachmentFulltextContent.create!(attachment: attachment2, status: 'indexed', content: 'test')

    failed_records = AttachmentFulltextContent.failed
    assert_equal 1, failed_records.count
    assert_equal attachment1.id, failed_records.first.attachment_id
  end

  def test_scope_needs_reindex
    attachment1 = Attachment.find(1)
    attachment2 = Attachment.find(2)
    attachment3 = Attachment.find(4)

    AttachmentFulltextContent.create!(attachment: attachment1, status: 'pending')
    AttachmentFulltextContent.create!(attachment: attachment2, status: 'failed', error_message: 'error')
    AttachmentFulltextContent.create!(attachment: attachment3, status: 'indexed', content: 'test')

    needs_reindex = AttachmentFulltextContent.needs_reindex
    assert_equal 2, needs_reindex.count
    assert_includes needs_reindex.pluck(:attachment_id), attachment1.id
    assert_includes needs_reindex.pluck(:attachment_id), attachment2.id
  end

  def test_scope_indexed_before
    attachment1 = Attachment.find(1)
    attachment2 = Attachment.find(2)

    AttachmentFulltextContent.create!(
      attachment: attachment1,
      status: 'indexed',
      content: 'test',
      indexed_at: 2.days.ago
    )
    AttachmentFulltextContent.create!(
      attachment: attachment2,
      status: 'indexed',
      content: 'test',
      indexed_at: Time.current
    )

    old_records = AttachmentFulltextContent.indexed_before(1.day.ago)
    assert_equal 1, old_records.count
    assert_equal attachment1.id, old_records.first.attachment_id
  end

  def test_scope_with_extractor_version
    attachment1 = Attachment.find(1)
    attachment2 = Attachment.find(2)

    AttachmentFulltextContent.create!(
      attachment: attachment1,
      status: 'indexed',
      content: 'test',
      extractor_version: '1.0.0'
    )
    AttachmentFulltextContent.create!(
      attachment: attachment2,
      status: 'indexed',
      content: 'test',
      extractor_version: '2.0.0'
    )

    v1_records = AttachmentFulltextContent.with_extractor_version('1.0.0')
    assert_equal 1, v1_records.count
    assert_equal attachment1.id, v1_records.first.attachment_id
  end

  def test_error_message_truncation
    attachment = Attachment.find(1)
    fulltext = AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'pending'
    )

    long_error = 'a' * 300
    fulltext.mark_failed!(long_error)

    assert_equal 255, fulltext.error_message.length
    assert fulltext.error_message.end_with?('...')
  end

  def test_destroyed_with_attachment
    attachment = Attachment.find(1)
    fulltext = AttachmentFulltextContent.create!(
      attachment: attachment,
      status: 'indexed',
      content: 'test content'
    )
    fulltext_id = fulltext.id

    attachment.destroy

    assert_nil AttachmentFulltextContent.find_by(id: fulltext_id)
  end
end
