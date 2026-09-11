# frozen_string_literal: true

module Wxw::StatusFormatConcern
  def wxw_content_type
    return 'text/html' unless local?

    "text/#{wxw_setting(:text_type) || 'plain'}"
  end

  def wxw_content_type=(value)
    raise ArgumentError, 'Invalid content type' unless value.nil? || %w(text/plain text/html text/markdown).include?(value)

    wxw_write_setting(:text_type, value == 'text/plain' ? nil : value&.delete_prefix('text/'))
  end

  def wxw_content_type_changed?
    return false unless local?

    record = wxw_status_setting
    record.present? && (record.settings_in_database || {})['text_type'] != wxw_setting(:text_type)
  end
end
