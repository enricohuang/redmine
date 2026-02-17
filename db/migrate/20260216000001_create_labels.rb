# frozen_string_literal: true

class CreateLabels < ActiveRecord::Migration[7.2]
  def change
    create_table :labels do |t|
      t.string :name, limit: 64, null: false
      t.string :color, limit: 7, null: false, default: '#0052CC'
      t.references :project, null: false, foreign_key: true, type: :integer

      t.timestamps null: false
    end

    add_index :labels, [:project_id, :name], unique: true
  end
end
