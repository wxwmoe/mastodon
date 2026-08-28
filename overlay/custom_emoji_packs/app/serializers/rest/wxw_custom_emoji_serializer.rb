# frozen_string_literal: true

class REST::WxwCustomEmojiSerializer < REST::CustomEmojiSerializer
  def category
    category_names[object.category_id]
  end

  def category_loaded?
    category_names.key?(object.category_id)
  end

  private

  def category_names
    instance_options[:category_names]
  end
end
