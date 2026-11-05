# frozen_string_literal: true

module Wxw::StatusSourceFormat
  extend ActiveSupport::Concern

  included do
    attribute :content_type
  end

  def content_type
    object.wxw_content_type
  end
end
