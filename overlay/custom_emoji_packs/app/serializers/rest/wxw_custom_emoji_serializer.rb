# frozen_string_literal: true

class REST::WxwCustomEmojiSerializer < REST::CustomEmojiSerializer
  def category
    instance_options[:category]
  end

  def category_loaded?
    true
  end

  def featured
    object.id == instance_options[:featured_emoji_id]
  end
end
