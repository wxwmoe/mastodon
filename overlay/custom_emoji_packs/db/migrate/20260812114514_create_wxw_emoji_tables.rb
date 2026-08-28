# frozen_string_literal: true

# Must predate the upstream schema version.
class CreateWxwEmojiTables < ActiveRecord::Migration[8.1]
  def change
    create_table :wxw_emoji_sections do |t|
      t.string :name, null: false, default: ''
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :wxw_emoji_packs do |t|
      t.bigint :custom_emoji_category_id, null: false
      t.bigint :section_id
      t.string :name, null: false, default: ''
      t.integer :position, null: false, default: 0
      t.boolean :default_enabled, null: false, default: false
      t.timestamps
      t.index :custom_emoji_category_id, unique: true
      t.index :section_id
    end

    create_table :wxw_emoji_translations do |t|
      t.string :translatable_type, null: false
      t.bigint :translatable_id, null: false
      t.string :language, null: false
      t.string :name, null: false, default: ''
      t.timestamps
      t.index %i(translatable_type translatable_id language), unique: true, name: 'index_wxw_emoji_translations_on_owner_and_language'
    end
  end
end
