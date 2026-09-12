# frozen_string_literal: true

module Wxw::EmojiSettingsConcern
  extend ActiveSupport::Concern

  included do
    namespace :wxw_emoji do
      setting :picks, default: nil
      setting :order, default: nil
      setting :numbered, default: true
    end
  end
end
