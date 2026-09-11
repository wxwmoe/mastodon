# frozen_string_literal: true

module Wxw::RemoteVisibilitySettingConcern
  extend ActiveSupport::Concern

  included do
    self.supported_setting_keys += %w(remote_visibility)

    validate :supported_remote_visibility
  end

  class_methods do
    def normalize_remote_visibility(visibility, remote_visibility)
      return if remote_visibility.nil?

      remote_visibility = remote_visibility.to_s
      local_rank = Status.visibilities[visibility.to_s]
      remote_rank = Status.visibilities[remote_visibility]
      return remote_visibility if local_rank.nil? || remote_rank.nil?

      remote_visibility if remote_rank > local_rank
    end
  end

  private

  def supported_remote_visibility
    return unless settings.is_a?(Hash) && settings.key?('remote_visibility')

    value = settings['remote_visibility']
    errors.add(:settings, :invalid) unless status_edit.nil? && value.is_a?(Integer) && (0..3).cover?(value)
  end
end
