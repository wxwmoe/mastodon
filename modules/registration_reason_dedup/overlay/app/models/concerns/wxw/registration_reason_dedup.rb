# frozen_string_literal: true

module Wxw::RegistrationReasonDedup
  extend ActiveSupport::Concern

  included do
    validates :text, uniqueness: { conditions: -> { joins(:user).merge(User.pending) } }, allow_blank: true, on: :create
  end
end
