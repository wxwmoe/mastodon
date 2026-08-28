# frozen_string_literal: true

class Api::V1::WxwCustomEmojisController < Api::BaseController
  rescue_from ActiveRecord::StatementInvalid, with: :emoji_tables_unavailable

  def index
    return unless stale?(etag: emoji_etag, public: false, template: false)

    render json: emojis, each_serializer: REST::WxwCustomEmojiSerializer, category_names: category_names
  end

  private

  def emoji_tables_unavailable(error)
    raise error unless error.cause.is_a?(PG::UndefinedTable)

    response.headers.delete('ETag')
    response.headers.delete('Last-Modified')
    response.cache_control.replace(no_store: true)
    head 503, retry_after: 60
  end

  def anonymous?
    current_user.nil?
  end

  def numbered?
    !anonymous? && ::Wxw::EmojiPack.numbered?(current_user)
  end

  def packs
    @packs ||= anonymous? ? ::Wxw::EmojiPack.default_selection : ::Wxw::EmojiPack.selection_for(current_user)
  end

  def emojis
    @emojis ||= begin
      category_ids = packs.map(&:custom_emoji_category_id)
      rows = if category_ids.empty?
               []
             else
               CustomEmoji.listed.where(category_id: category_ids).includes(:category).order(shortcode: :asc).to_a
             end
      by_category = rows.group_by(&:category_id)
      packs.flat_map { |pack| by_category[pack.custom_emoji_category_id] || [] }
    end
  end

  def category_names
    @category_names ||= begin
      width = [picker_packs.size, 1].max.to_s.length
      picker_packs.each_with_index.to_h do |pack, index|
        name = anonymous? ? pack.name : pack.name_for(I18n.locale)
        # Picker category order is lexical.
        name = format('%0*d. ', width, index + 1) + name if numbered?
        [pack.custom_emoji_category_id, name]
      end
    end
  end

  def picker_packs
    @picker_packs ||= ::Wxw::EmojiPack.picker_packs(packs, category_ids: emojis.map(&:category_id))
  end

  def emoji_etag
    [
      anonymous? ? nil : I18n.locale,
      anonymous?,
      ::Wxw::EmojiPack.publish_version,
      anonymous? ? nil : current_user.settings[::Wxw::EmojiPack::USER_VERSION_KEY],
      anonymous? ? nil : ::Wxw::EmojiPack.picked_ids(current_user),
      anonymous? ? nil : ::Wxw::EmojiPack.order_ids(current_user),
      numbered?,
    ]
  end
end
