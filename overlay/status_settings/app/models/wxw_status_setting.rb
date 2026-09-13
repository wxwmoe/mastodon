# frozen_string_literal: true

class WxwStatusSetting < ApplicationRecord
  class_attribute :supported_setting_keys, instance_writer: false, default: []

  belongs_to :status, inverse_of: :wxw_status_setting, optional: true
  belongs_to :status_edit, inverse_of: :wxw_status_setting, optional: true

  validate :supported_settings
  validate :local_owner

  private

  def supported_settings
    keys = self.class.supported_setting_keys
    valid = settings.is_a?(Hash) && settings.present? &&
            settings.except(*keys) == (settings_in_database || {}).except(*keys)

    errors.add(:settings, :invalid) unless valid
  end

  def local_owner
    errors.add(:base, :invalid) unless status.present? ^ status_edit.present?
    errors.add(:base, :invalid) unless (status || status_edit)&.local?
  end
end
