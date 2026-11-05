# frozen_string_literal: true

class CreateWxwStatusSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :wxw_status_settings do |t|
      t.bigint :status_id
      t.bigint :status_edit_id
      t.jsonb :settings, null: false, default: {}
      t.index :status_id, unique: true, where: 'status_id IS NOT NULL'
      t.index :status_edit_id, unique: true, where: 'status_edit_id IS NOT NULL'
      t.foreign_key :statuses, on_delete: :cascade
      t.foreign_key :status_edits, on_delete: :cascade
      t.check_constraint 'num_nonnulls(status_id, status_edit_id) = 1', name: 'wxw_status_settings_owner'
      t.check_constraint "jsonb_typeof(settings) = 'object' AND settings <> '{}'::jsonb", name: 'wxw_status_settings_object'
    end
  end
end
