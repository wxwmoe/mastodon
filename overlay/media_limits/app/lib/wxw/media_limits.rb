# frozen_string_literal: true

module Wxw::MediaLimits
  REMOTE_EMOJI_SIZE = 2.megabytes
  REMOTE_ACCOUNT_IMAGE_SIZE = 16.megabytes

  def self.emoji_size(emoji)
    emoji.local? ? CustomEmoji::LIMIT : REMOTE_EMOJI_SIZE
  end

  def self.account_image_size(account, local_limit)
    account.local? ? local_limit : REMOTE_ACCOUNT_IMAGE_SIZE
  end
end
