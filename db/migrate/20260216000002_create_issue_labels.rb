# frozen_string_literal: true

class CreateIssueLabels < ActiveRecord::Migration[7.2]
  def change
    create_table :issue_labels do |t|
      t.references :issue, null: false, foreign_key: true, type: :integer
      t.references :label, null: false, foreign_key: true
    end

    add_index :issue_labels, [:issue_id, :label_id], unique: true
  end
end
