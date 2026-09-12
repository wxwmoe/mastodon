# frozen_string_literal: true

module Wxw::StatusRemoteVisibilityConcern
  extend ActiveSupport::Concern

  included do
    scope :wxw_remote_visibility_in, lambda { |*values|
      left_joins(:wxw_status_setting).where(
        "CASE WHEN statuses.local OR statuses.uri IS NULL THEN GREATEST((wxw_status_settings.settings->>'remote_visibility')::integer, statuses.visibility) ELSE statuses.visibility END IN (?)",
        values.map { |value| visibilities.fetch(value.to_s) }
      )
    }

    before_validation :wxw_normalize_remote_visibility
  end

  def wxw_remote_visibility
    return unless local?

    value = wxw_setting(:remote_visibility)
    value = Status.visibilities.key(value) if value.is_a?(Integer)
    WxwStatusSetting.normalize_remote_visibility(visibility, value)
  end

  def wxw_remote_visibility=(value)
    value = value.to_s unless value.nil?

    wxw_write_setting(:remote_visibility, value.nil? ? nil : Status.visibilities.fetch(value, value))
  end

  def wxw_effective_remote_visibility
    wxw_remote_visibility || visibility
  end

  def wxw_remote_distributable?
    %w(public unlisted).include?(wxw_effective_remote_visibility)
  end

  def sign?
    wxw_remote_distributable?
  end

  def wxw_federatable?
    return true unless reblog? && reblog.wxw_remote_visibility.present?
    return true if reblog.wxw_remote_distributable?

    account_id == reblog.account_id && reblog.wxw_effective_remote_visibility == 'private'
  end

  def wxw_remote_reblog_visibility
    'private' if wxw_remote_visibility.present? && wxw_effective_remote_visibility == 'private'
  end

  def wxw_remote_inbox_for(recipient)
    return if recipient.local? || !recipient.activitypub?
    return if wxw_remote_visibility.present? && !StatusPolicy.new(recipient, self, federation: true).show?

    recipient.preferred_inbox_url
  end

  private

  def wxw_normalize_remote_visibility
    return unless local?

    self.wxw_remote_visibility = wxw_remote_visibility unless wxw_setting(:remote_visibility).nil?
  end
end
