# frozen_string_literal: true

module Wxw::PostFormatPreference
  extend ActiveSupport::Concern

  included do
    setting :wxw_default_post_format, default: 'plain', in: %w(plain markdown html)
  end
end
