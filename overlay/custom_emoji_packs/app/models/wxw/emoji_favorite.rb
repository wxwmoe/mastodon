# frozen_string_literal: true

class Wxw::EmojiFavorite < ApplicationRecord
  belongs_to :pack, class_name: 'Wxw::EmojiPack', inverse_of: :favorites, touch: true
  belongs_to :custom_emoji
  belongs_to :user

  before_validation :assign_user
  validates :custom_emoji_id, uniqueness: { scope: :user_id }
  validate :personal_pack_and_local_emoji

  private

  def assign_user
    self.user = pack&.user
  end

  def personal_pack_and_local_emoji
    errors.add(:pack, :invalid) unless pack&.favorite?
    errors.add(:custom_emoji, :invalid) unless custom_emoji&.local?
  end
end
