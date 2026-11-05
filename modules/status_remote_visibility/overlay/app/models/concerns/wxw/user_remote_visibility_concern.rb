# frozen_string_literal: true

module Wxw::UserRemoteVisibilityConcern
  extend ActiveSupport::Concern

  included do
    before_validation :wxw_normalize_default_remote_privacy
  end

  def wxw_default_remote_privacy
    WxwStatusSetting.normalize_remote_visibility(setting_default_privacy, settings['wxw_default_remote_privacy'])
  end

  def wxw_normalize_default_remote_privacy
    return if settings['wxw_default_remote_privacy'].nil? || account.nil?

    settings['wxw_default_remote_privacy'] = wxw_default_remote_privacy
  end
end
