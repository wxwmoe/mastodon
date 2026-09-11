# frozen_string_literal: true

module Wxw::StatusFormatSettingConcern
  extend ActiveSupport::Concern

  TEXT_TYPES = %w(markdown html).freeze

  included do
    self.supported_setting_keys += %w(text_type)
    validate :supported_text_type
  end

  private

  def supported_text_type
    return unless settings.is_a?(Hash) && settings.key?('text_type')

    errors.add(:settings, :invalid) unless TEXT_TYPES.include?(settings['text_type'])
  end
end
