add_check_constraint "wxw_status_settings", "NOT (settings ? 'remote_visibility') OR settings->'remote_visibility' IN ('0'::jsonb, '1'::jsonb, '2'::jsonb, '3'::jsonb)", name: "wxw_status_settings_remote_visibility"
add_check_constraint "wxw_status_settings", "status_edit_id IS NULL OR NOT (settings ? 'remote_visibility')", name: "wxw_status_settings_edit_keys"
