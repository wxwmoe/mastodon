# frozen_string_literal: true

class Wxw::EmojiTranslation < ApplicationRecord
  belongs_to :translatable, polymorphic: true
  validates :language, presence: true, uniqueness: { scope: [:translatable_type, :translatable_id] }
  validates :name, presence: true, length: { maximum: Wxw::Named::NAME_LIMIT }
end
