# frozen_string_literal: true

class AddTextTypeToWxwStatusSettings < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    unless check_constraint_exists?(:wxw_status_settings, name: 'wxw_status_settings_text_type')
      add_check_constraint :wxw_status_settings,
                           "NOT (settings ? 'text_type') OR settings->'text_type' IN ('\"markdown\"'::jsonb, '\"html\"'::jsonb)",
                           name: 'wxw_status_settings_text_type',
                           validate: false
    end

    validate_check_constraint :wxw_status_settings, name: 'wxw_status_settings_text_type'
  end

  def down
    remove_check_constraint :wxw_status_settings, name: 'wxw_status_settings_text_type', if_exists: true
  end
end
