# frozen_string_literal: true

class Wxw::EmojiSection < ApplicationRecord
  include Wxw::Named

  has_many :packs,
           class_name: 'Wxw::EmojiPack',
           foreign_key: :section_id,
           inverse_of: :section,
           dependent: :restrict_with_error
  scope :ordered, -> { includes(:translations).order(:position, :id) }
end
