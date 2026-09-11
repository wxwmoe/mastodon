# frozen_string_literal: true

module Wxw::StatusSettingsConcern
  extend ActiveSupport::Concern

  included do
    before_validation :wxw_discard_empty_settings
  end

  def wxw_setting(key)
    record = wxw_status_setting
    record.settings[key.to_s] if record && !record.marked_for_destruction? && record.settings.is_a?(Hash)
  end

  def wxw_write_setting(key, value)
    record = wxw_status_setting
    settings = (record&.settings || {}).dup
    value.nil? ? settings.delete(key.to_s) : settings[key.to_s] = value
    return if record.nil? && settings.empty?

    if record&.marked_for_destruction?
      association(:wxw_status_setting).reset
      record = wxw_status_setting
    end

    (record || build_wxw_status_setting).settings = settings
    wxw_discard_empty_settings if settings.empty?
  end

  private

  def wxw_discard_empty_settings
    record = wxw_status_setting
    return unless record && record.settings == {}

    if record.persisted?
      record.mark_for_destruction
    else
      association(:wxw_status_setting).target = nil
    end
  end
end
