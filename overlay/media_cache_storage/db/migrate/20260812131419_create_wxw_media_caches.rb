# frozen_string_literal: true

class CreateWxwMediaCaches < ActiveRecord::Migration[8.1]
  def change
    create_table :wxw_media_caches do |t|
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :attachment_name, null: false
      t.bigint :generation, null: false, default: 0
      t.timestamps
      t.index [:record_type, :record_id, :attachment_name], unique: true, name: 'index_wxw_media_caches_on_attachment'
    end

    reversible do |direction|
      direction.down do
        raise ActiveRecord::IrreversibleMigration, 'Migrate cached media back to main first' if select_value('SELECT EXISTS (SELECT 1 FROM wxw_media_caches)')
      end
    end
  end
end
