# frozen_string_literal: true

module Wxw::RemotePrivacyPreference
  extend ActiveSupport::Concern

  included do
    setting :wxw_default_remote_privacy, default: nil, in: [nil, 'public', 'unlisted', 'private', 'direct']
  end
end
