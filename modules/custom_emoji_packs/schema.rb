create_table "wxw_emoji_packs", force: :cascade do |t|
  t.datetime "created_at", null: false
  t.bigint "custom_emoji_category_id"
  t.boolean "default_enabled", default: false, null: false
  t.bigint "featured_emoji_id"
  t.string "name", default: "", null: false
  t.integer "position", default: 0, null: false
  t.bigint "section_id"
  t.datetime "updated_at", null: false
  t.bigint "user_id"
  t.index ["custom_emoji_category_id"], name: "index_wxw_emoji_packs_on_custom_emoji_category_id", unique: true
  t.index ["featured_emoji_id"], name: "index_wxw_emoji_packs_on_featured_emoji_id"
  t.index ["section_id"], name: "index_wxw_emoji_packs_on_section_id"
  t.index ["user_id"], name: "index_wxw_emoji_packs_on_user_id"
  t.check_constraint "(user_id IS NULL AND custom_emoji_category_id IS NOT NULL) OR (user_id IS NOT NULL AND custom_emoji_category_id IS NULL AND section_id IS NULL)", name: "wxw_emoji_packs_owner_and_category"
end

create_table "wxw_emoji_favorites", force: :cascade do |t|
  t.datetime "created_at", null: false
  t.bigint "custom_emoji_id", null: false
  t.bigint "pack_id", null: false
  t.datetime "updated_at", null: false
  t.bigint "user_id", null: false
  t.index ["custom_emoji_id"], name: "index_wxw_emoji_favorites_on_custom_emoji_id"
  t.index ["pack_id"], name: "index_wxw_emoji_favorites_on_pack_id"
  t.index ["user_id", "custom_emoji_id"], name: "index_wxw_emoji_favorites_on_user_id_and_custom_emoji_id", unique: true
end

create_table "wxw_emoji_sections", force: :cascade do |t|
  t.datetime "created_at", null: false
  t.string "name", default: "", null: false
  t.integer "position", default: 0, null: false
  t.datetime "updated_at", null: false
end

create_table "wxw_emoji_translations", force: :cascade do |t|
  t.datetime "created_at", null: false
  t.string "language", null: false
  t.string "name", default: "", null: false
  t.bigint "translatable_id", null: false
  t.string "translatable_type", null: false
  t.datetime "updated_at", null: false
  t.index ["translatable_type", "translatable_id", "language"], name: "index_wxw_emoji_translations_on_owner_and_language", unique: true
end
add_foreign_key "wxw_emoji_packs", "users", on_delete: :cascade
add_foreign_key "wxw_emoji_packs", "custom_emojis", column: "featured_emoji_id", on_delete: :nullify
add_foreign_key "wxw_emoji_favorites", "wxw_emoji_packs", column: "pack_id", on_delete: :cascade
add_foreign_key "wxw_emoji_favorites", "custom_emojis", on_delete: :cascade
add_foreign_key "wxw_emoji_favorites", "users", on_delete: :cascade
