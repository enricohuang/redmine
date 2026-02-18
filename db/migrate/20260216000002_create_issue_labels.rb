# frozen_string_literal: true

class CreateIssueLabels < ActiveRecord::Migration[7.2]
  def up
    create_table :issue_labels do |t|
      t.references :issue, null: false, type: :integer
      t.references :label, null: false
    end

    add_index :issue_labels, [:issue_id, :label_id], unique: true
    add_foreign_key :issue_labels, :issues, on_delete: :cascade
    add_foreign_key :issue_labels, :labels, on_delete: :cascade
  end

  def down
    drop_table :issue_labels
  end
end
