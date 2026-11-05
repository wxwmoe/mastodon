add_check_constraint "wxw_status_settings", "NOT (settings ? 'text_type') OR settings->'text_type' IN ('\"markdown\"'::jsonb, '\"html\"'::jsonb)", name: "wxw_status_settings_text_type"
