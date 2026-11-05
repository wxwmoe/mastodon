create_table "wxw_status_settings", force: :cascade do |t|
  t.bigint "status_id"
  t.bigint "status_edit_id"
  t.jsonb "settings", default: {}, null: false
  t.index ["status_id"], name: "index_wxw_status_settings_on_status_id", unique: true, where: "status_id IS NOT NULL"
  t.index ["status_edit_id"], name: "index_wxw_status_settings_on_status_edit_id", unique: true, where: "status_edit_id IS NOT NULL"
  t.check_constraint "num_nonnulls(status_id, status_edit_id) = 1", name: "wxw_status_settings_owner"
  t.check_constraint "jsonb_typeof(settings) = 'object' AND settings <> '{}'::jsonb", name: "wxw_status_settings_object"
end

add_foreign_key "wxw_status_settings", "status_edits", on_delete: :cascade
add_foreign_key "wxw_status_settings", "statuses", on_delete: :cascade
