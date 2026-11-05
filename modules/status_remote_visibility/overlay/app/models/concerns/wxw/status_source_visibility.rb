# frozen_string_literal: true

module Wxw::StatusSourceVisibility
  extend ActiveSupport::Concern

  included do
    attribute :wxw_remote_visibility
  end
end
