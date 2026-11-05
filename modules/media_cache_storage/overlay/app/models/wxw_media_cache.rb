# frozen_string_literal: true

class WxwMediaCache < ApplicationRecord
  belongs_to :record, polymorphic: true, inverse_of: :wxw_media_caches
  validates :attachment_name, presence: true
end
