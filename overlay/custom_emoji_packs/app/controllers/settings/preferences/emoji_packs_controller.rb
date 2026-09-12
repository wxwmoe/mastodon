# frozen_string_literal: true

class Settings::Preferences::EmojiPacksController < Settings::Preferences::BaseController
  before_action :set_packs, only: :index

  def index; end

  def search
    @packs = ordered_packs(::Wxw::EmojiPack.management_packs(current_user), ::Wxw::EmojiPack.order_ids(current_user))
    @selected_pack_id = params[:pack_id].to_s
    pack_id = Integer(@selected_pack_id, exception: false)
    @reset_params = { pack_id: @selected_pack_id }
    @shortcode = params[:shortcode].to_s.strip
    @emojis = CustomEmoji.listed
    if pack_id == 0
      selected = ::Wxw::EmojiPack.selection_for(current_user)
      category_ids = selected.reject(&:favorite?).map(&:custom_emoji_category_id)
      favorite_ids = ::Wxw::EmojiFavorite.where(pack_id: selected.select(&:favorite?).map(&:id)).select(:custom_emoji_id)
      @emojis = @emojis.where(category_id: category_ids).or(@emojis.where(id: favorite_ids))
    elsif @selected_pack_id.present?
      @pack = @packs.find { |pack| pack.id == pack_id }
      @emojis = if @pack&.favorite?
                  @pack.custom_emojis
                elsif @pack
                  @emojis.where(category_id: @pack.custom_emoji_category_id)
                else
                  @emojis.none
                end
    end
    @emojis = @emojis.merge(CustomEmoji.search(@shortcode)) if @shortcode.present?
    category_order = @packs.filter_map(&:custom_emoji_category_id)
    @emojis = @emojis.in_order_of(:category_id, category_order, filter: false) if @pack.nil? && category_order.any?
    @emojis = @emojis.order(:shortcode, :id)
    @emojis = @emojis.page(params[:page])
  end

  def update
    saved = current_user.with_lock do
      set_packs
      return render_invalid_submission unless valid_submission?

      case action_from_button
      when 'reset'
        current_user.settings[::Wxw::EmojiPack::PICKS_KEY] = nil
        current_user.settings[::Wxw::EmojiPack::ORDER_KEY] = nil
      when 'save_order'
        current_user.settings[::Wxw::EmojiPack::ORDER_KEY] = ::Wxw::EmojiPack.dump_ids(submitted_order_ids)
      end
      current_user.settings_will_change!
      current_user.update(user_params)
    end
    if saved
      I18n.locale = current_user.locale
      redirect_to after_update_redirect_path, notice: I18n.t('generic.changes_saved_msg')
    else
      render :index, status: 422
    end
  end

  private

  def set_packs
    all_packs = ::Wxw::EmojiPack.management_packs(current_user)
    @management_order = all_packs.map(&:id)
    @default_picks = all_packs.filter_map { |pack| pack.id if pack.favorite? || pack.default_enabled? }
    @saved_picks = ::Wxw::EmojiPack.picked_ids(current_user)
    picked_ids = @saved_picks || @default_picks
    @numbered = ::Wxw::EmojiPack.numbered?(current_user)
    @packs = ordered_packs(all_packs, ::Wxw::EmojiPack.order_ids(current_user))
    @pack_icons = ::Wxw::EmojiPack.icon_emojis_for(@packs)
    picked_lookup = picked_ids.index_with(true)
    picked_packs = @packs.select { |pack| picked_lookup.key?(pack.id) }
    @picked_ids = picked_packs.map(&:id)
    @picked_lookup = @picked_ids.index_with(true)
    picker_packs = @numbered ? ::Wxw::EmojiPack.picker_packs(picked_packs) : []
    @picker_positions = picker_packs.map(&:id).each_with_index.to_h
    @number_width = [picker_packs.size, 1].max.to_s.length
  end

  def after_update_redirect_path
    settings_preferences_emoji_packs_path
  end

  def user_params
    settings = emoji_settings
    settings.empty? ? {} : { settings_attributes: settings }
  end

  def emoji_settings
    return {} if action_from_button == 'reset'
    return { ::Wxw::EmojiPack::NUMBERED_KEY => numbered_after_button ? '1' : '0' } if action_from_button == 'numbered'
    return {} if action_from_button == 'save_order'

    picks = picks_after_action
    return {} if picks.nil?

    settings = {}
    settings[::Wxw::EmojiPack::PICKS_KEY] = ::Wxw::EmojiPack.dump_ids(picks)
    settings[::Wxw::EmojiPack::NUMBERED_KEY] = numbered_after_button ? '1' : '0'
    settings
  end

  def submitted_ids
    raw = params.dig(:user, :emoji_ids)
    return nil unless raw.is_a?(Array) && raw.all?(String)

    ids = raw.reject(&:empty?).map { |id| Integer(id, exception: false) }
    return nil unless ids.all? { |id| id&.positive? }

    ids.uniq
  end

  def submitted_order_ids
    raw = params.dig(:user, :emoji_order)
    return unless raw.is_a?(Array) && raw.all?(String)

    ids = raw.map { |id| Integer(id, exception: false) }
    return unless ids.all? { |id| id&.positive? }
    return unless ids.uniq.size == ids.size && ids.sort == @management_order.sort

    ids
  end

  def action_from_button
    return 'enable' if params[:enable]
    return 'disable' if params[:disable]
    return 'numbered' if params[:numbered]
    return 'reset' if params[:reset]
    return 'save_order' if params[:save_order]

    nil
  end

  def numbered_after_button
    action_from_button == 'numbered' ? !@numbered : @numbered
  end

  def picks_after_action
    return @saved_picks if %w(numbered save_order).include?(action_from_button)
    return nil if action_from_button == 'reset'
    return @picks_after_action if defined?(@picks_after_action)

    ids = submitted_ids
    @picks_after_action = unless ids.nil?
                            picks = case action_from_button
                                    when 'enable'  then @picked_ids | ids
                                    when 'disable' then @picked_ids - ids
                                    else @picked_ids
                                    end
                            normalize(picks)
                          end
  end

  def ordered_packs(all_packs, order_ids)
    return all_packs unless order_ids

    by_id = all_packs.index_by(&:id)
    order_ids.filter_map { |id| by_id.delete(id) } + by_id.values
  end

  def normalize(ids)
    selected = ids.index_with(true)
    @packs.filter_map { |pack| pack.id if selected.key?(pack.id) }
  end

  def valid_submission?
    case action_from_button
    when 'enable', 'disable'
      !submitted_ids.nil? && (submitted_ids - @management_order).empty?
    when 'save_order'
      !submitted_order_ids.nil?
    when 'numbered', 'reset'
      true
    else
      false
    end
  end

  def render_invalid_submission
    current_user.errors.add(:base, :invalid)
    render :index, status: 422
  end
end
