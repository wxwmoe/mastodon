# frozen_string_literal: true

module Wxw::PostingDefaultsConcern
  extend ActiveSupport::Concern

  included do
    helper_method :wxw_default_remote_privacy, :wxw_default_quote_hint
  end

  private

  def wxw_default_remote_privacy
    current_user.wxw_default_remote_privacy || current_user.setting_default_privacy
  end

  def wxw_default_quote_hint
    visibilities = [current_user.setting_default_privacy, wxw_default_remote_privacy]
    visibility = visibilities.find { |value| %w(private direct).include?(value) } || ('unlisted' if visibilities.include?('unlisted'))
    visibility = 'private' if visibility == 'direct'

    I18n.t("simple_form.hints.defaults.setting_default_quote_policy_#{visibility}") if %w(unlisted private).include?(visibility)
  end

  def wxw_normalize_default_quote_policy(params)
    settings = params[:settings_attributes]
    visibility = settings[:default_privacy] || current_user.setting_default_privacy
    remote_visibility = settings.fetch(:wxw_default_remote_privacy, current_user.settings['wxw_default_remote_privacy']).presence || visibility

    settings[:default_quote_policy] = 'nobody' if [visibility, remote_visibility].intersect?(%w(private direct))
  end
end
