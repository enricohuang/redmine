# frozen_string_literal: true

class CreateAttachmentFulltextContents < ActiveRecord::Migration[7.2]
  def change
    create_table :attachment_fulltext_contents do |t|
      t.references :attachment, null: false, foreign_key: true, index: { unique: true }
      t.text :content
      t.string :status, null: false, default: 'pending'
      t.string :error_message
      t.string :extractor_version
      t.datetime :indexed_at

      t.timestamps null: false
    end

    add_index :attachment_fulltext_contents, :status
    add_index :attachment_fulltext_contents, :indexed_at
  end
end
