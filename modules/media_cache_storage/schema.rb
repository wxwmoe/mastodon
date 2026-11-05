create_table "wxw_media_caches", force: :cascade do |t|
  t.string "record_type", null: false
  t.bigint "record_id", null: false
  t.string "attachment_name", null: false
  t.bigint "generation", default: 0, null: false
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
  t.index ["record_type", "record_id", "attachment_name"], name: "index_wxw_media_caches_on_attachment", unique: true
end
