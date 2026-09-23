# frozen_string_literal: true

class Wxw::EmojiTranslation < ApplicationRecord
  self.table_name = 'wxw_emoji_translations'

  belongs_to :translatable, polymorphic: true
  validates :language, presence: true, uniqueness: { scope: [:translatable_type, :translatable_id] }
  validates :name, presence: true, length: { maximum: Wxw::Named::NAME_LIMIT }
end
