# frozen_string_literal: true

class AddWxwEmojiFavorites < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class MigrationUser < ActiveRecord::Base
    self.table_name = 'users'
  end

  def up
    add_reference :wxw_emoji_packs, :user, index: { algorithm: :concurrently }, foreign_key: { on_delete: :cascade, validate: false }
    add_reference :wxw_emoji_packs, :featured_emoji, index: { algorithm: :concurrently }, foreign_key: { to_table: :custom_emojis, on_delete: :nullify, validate: false }
    validate_foreign_key :wxw_emoji_packs, :users
    validate_foreign_key :wxw_emoji_packs, :custom_emojis, column: :featured_emoji_id
    change_column_null :wxw_emoji_packs, :custom_emoji_category_id, true
    add_check_constraint :wxw_emoji_packs,
                         '(user_id IS NULL AND custom_emoji_category_id IS NOT NULL) OR (user_id IS NOT NULL AND custom_emoji_category_id IS NULL AND section_id IS NULL)',
                         name: 'wxw_emoji_packs_owner_and_category', validate: false
    validate_check_constraint :wxw_emoji_packs, name: 'wxw_emoji_packs_owner_and_category'

    create_table :wxw_emoji_favorites do |t|
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :pack, null: false, foreign_key: { to_table: :wxw_emoji_packs, on_delete: :cascade }
      t.references :custom_emoji, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
      t.index [:user_id, :custom_emoji_id], unique: true
    end
    prune_pack_settings
  end

  def down
    drop_table :wxw_emoji_favorites
    execute 'DELETE FROM wxw_emoji_packs WHERE user_id IS NOT NULL'
    prune_pack_settings
    remove_check_constraint :wxw_emoji_packs, name: 'wxw_emoji_packs_owner_and_category'
    change_column_null :wxw_emoji_packs, :custom_emoji_category_id, false
    remove_reference :wxw_emoji_packs, :featured_emoji, foreign_key: { to_table: :custom_emojis }
    remove_reference :wxw_emoji_packs, :user, foreign_key: true
  end

  private

  def prune_pack_settings
    public_ids = select_values('SELECT id FROM wxw_emoji_packs WHERE custom_emoji_category_id IS NOT NULL').map(&:to_i).index_with(true)
    MigrationUser.where('settings LIKE ?', '%"wxw_emoji.%').find_each do |user|
      user.with_lock do
        settings = JSON.parse(user.settings)
        next unless settings.is_a?(Hash)

        original = settings.dup
        %w(wxw_emoji.picks wxw_emoji.order).each do |key|
          next unless settings[key].is_a?(String)

          begin
            ids = JSON.parse(settings[key])
          rescue JSON::ParserError
            next
          end
          next unless ids.is_a?(Array)

          kept = ids.select { |id| public_ids.key?(Integer(id, exception: false)) }
          settings[key] = JSON.generate(kept) unless kept == ids
        end
        user.update_column(:settings, JSON.generate(settings)) unless settings == original
      end
    end
  end
end
