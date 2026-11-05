# frozen_string_literal: true

class Api::V1::WxwCustomEmojisController < Api::BaseController
  rescue_from ActiveRecord::StatementInvalid, with: :emoji_tables_unavailable

  def index
    return unless stale?(etag: emoji_etag, public: false, template: false)

    render json: serialized_emojis
  end

  private

  def current_resource_owner
    super if doorkeeper_token&.accessible?
  end

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

  def emoji_entries
    @emoji_entries ||= ::Wxw::EmojiPack.picker_entries(packs)
  end

  def emoji_groups
    @emoji_groups ||= begin
      by_pack = emoji_entries.group_by(&:first)
      packs.filter_map { |pack| [pack, by_pack[pack].map(&:last)] if by_pack.key?(pack) }
    end
  end

  def serialized_emojis
    width = [emoji_groups.size, 1].max.to_s.length
    emoji_groups.each_with_index.flat_map do |(pack, rows), pack_index|
      name = anonymous? ? pack.name : pack.name_for(I18n.locale)
      # The native picker sorts category names and shortcodes lexically.
      name = format('%0*d. ', width, pack_index + 1) + name if numbered?

      rows.map do |emoji|
        REST::WxwCustomEmojiSerializer.new(emoji, category: name, featured_emoji_id: pack.featured_emoji_id).as_json
      end
    end
  end

  def favorites_cache_key
    return if anonymous?

    personal_packs = ::Wxw::EmojiPack.favorites.where(user_id: current_user.id)
    picked_ids = ::Wxw::EmojiPack.picked_ids(current_user)
    personal_packs = personal_packs.where(id: picked_ids) unless picked_ids.nil?
    values = personal_packs.order(:id).pluck(:id, :featured_emoji_id, :updated_at)
      .map { |pack_id, emoji_id, updated_at| [pack_id, emoji_id, updated_at.utc.to_fs(:usec)] }
    return if values.empty?

    # FK deletions/nullification do not touch the parent pack's updated_at.
    members = ::Wxw::EmojiFavorite.joins(:custom_emoji).merge(CustomEmoji.listed)
      .where(pack_id: values.map(&:first)).order(:pack_id, :custom_emoji_id)
      .pluck(:pack_id, :custom_emoji_id, 'custom_emojis.updated_at')
      .map { |pack_id, emoji_id, updated_at| [pack_id, emoji_id, updated_at.utc.to_fs(:usec)] }
    Digest::SHA256.hexdigest(JSON.generate([values, members]))
  end

  def emoji_etag
    [
      anonymous? ? nil : I18n.locale,
      anonymous?,
      current_user&.id,
      ::Wxw::EmojiPack.publish_version,
      anonymous? ? nil : ::Wxw::EmojiPack.picked_ids(current_user),
      anonymous? ? nil : ::Wxw::EmojiPack.order_ids(current_user),
      numbered?,
      favorites_cache_key,
    ]
  end
end
