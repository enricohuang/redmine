# frozen_string_literal: true

class AddFulltextIndexableToAttachments < ActiveRecord::Migration[7.2]
  def change
    add_column :attachments, :fulltext_indexable, :boolean, default: true, null: false
  end
end
