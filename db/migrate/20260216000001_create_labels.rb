# frozen_string_literal: true

class CreateLabels < ActiveRecord::Migration[7.2]
  def up
    create_table :labels do |t|
      t.string :name, limit: 64, null: false
      t.string :color, limit: 7, null: false, default: '#0052CC'
      t.references :project, null: false, type: :integer

      t.timestamps null: false
    end

    add_index :labels, [:project_id, :name], unique: true
    add_foreign_key :labels, :projects, on_delete: :cascade
  end

  def down
    drop_table :labels
  end
end
