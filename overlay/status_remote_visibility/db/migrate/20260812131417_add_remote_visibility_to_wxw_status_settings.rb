# frozen_string_literal: true

class AddRemoteVisibilityToWxwStatusSettings < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    unless check_constraint_exists?(:wxw_status_settings, name: 'wxw_status_settings_remote_visibility')
      add_check_constraint :wxw_status_settings,
                           "NOT (settings ? 'remote_visibility') OR settings->'remote_visibility' IN ('0'::jsonb, '1'::jsonb, '2'::jsonb, '3'::jsonb)",
                           name: 'wxw_status_settings_remote_visibility',
                           validate: false
    end

    validate_check_constraint :wxw_status_settings, name: 'wxw_status_settings_remote_visibility'

    unless check_constraint_exists?(:wxw_status_settings, name: 'wxw_status_settings_edit_keys')
      add_check_constraint :wxw_status_settings,
                           "status_edit_id IS NULL OR NOT (settings ? 'remote_visibility')",
                           name: 'wxw_status_settings_edit_keys',
                           validate: false
    end

    validate_check_constraint :wxw_status_settings, name: 'wxw_status_settings_edit_keys'
  end

  def down
    remove_check_constraint :wxw_status_settings, name: 'wxw_status_settings_edit_keys', if_exists: true
    remove_check_constraint :wxw_status_settings, name: 'wxw_status_settings_remote_visibility', if_exists: true
  end
end
