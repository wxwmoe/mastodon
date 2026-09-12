# frozen_string_literal: true

class Settings::Preferences::EmojiFavoritesController < Settings::Preferences::BaseController
  before_action :set_pack, only: [:edit, :update]

  def index
    @packs = ordered_favorites
    @pack_icons = ::Wxw::EmojiPack.icon_emojis_for(@packs)
  end

  def refresh_icons
    current_user.with_lock { favorite_scope.refresh_icons! }
    redirect_to settings_preferences_emoji_favorites_path, notice: t('generic.changes_saved_msg')
  end

  def new
    @emoji_ids = submitted_ids(:emoji_ids)
    @pack = ::Wxw::EmojiPack.new(user: current_user)
  end

  def edit; end

  def create
    @emoji_ids = submitted_ids(:emoji_ids)
    @pack = ::Wxw::EmojiPack.new(resource_params.merge(user: current_user))
    if current_user.with_lock { @pack.save }
      destination = if params[:return_to_choose] == '1'
                      choose_settings_preferences_emoji_favorites_path(emoji_ids: @emoji_ids, target_pack_id: @pack.id, shortcodes: params[:shortcodes].to_s, remove: params[:operation] == 'remove' ? '1' : nil)
                    else
                      settings_preferences_emoji_favorites_path
                    end
      redirect_to destination, notice: t('generic.changes_saved_msg')
    else
      render :new, status: 422
    end
  end

  def update
    saved = current_user.with_lock { @pack.with_lock { @pack.update(resource_params) } }
    if saved
      redirect_to settings_preferences_emoji_favorites_path, notice: t('generic.changes_saved_msg')
    else
      render :edit, status: 422
    end
  end

  def batch
    raise ActionController::BadRequest unless params[:delete]

    current_user.with_lock do
      ids = submitted_ids(:pack_ids)
      return redirect_to settings_preferences_emoji_favorites_path, alert: t('wxw_emoji.admin.packs.no_selection') if ids.empty?
      raise ActionController::BadRequest unless favorite_scope.where(id: ids).count == ids.size

      favorite_scope.where(id: ids).order(:id).each do |pack|
        pack.user = current_user
        pack.with_lock { pack.destroy! }
      end
    end
    redirect_to settings_preferences_emoji_favorites_path, notice: t('generic.changes_saved_msg')
  end

  # Choosing a destination is read-only, so search can link here with a GET form.
  def choose
    @operation = params[:remove] ? 'remove' : 'add'
    @emoji_ids = submitted_ids(:emoji_ids)
    return redirect_to search_settings_preferences_emoji_packs_path, alert: t('wxw_emoji.favorites.no_selection') if @operation == 'remove' && @emoji_ids.empty?

    load_destinations
    @shortcodes = params[:shortcodes].to_s
  end

  def apply
    @operation = params[:operation].to_s
    raise ActionController::BadRequest unless %w(add remove).include?(@operation)

    @emoji_ids = submitted_ids(:emoji_ids)
    @shortcodes = params[:shortcodes].to_s
    @pack = favorite_scope.find(params[:target_pack_id])
    load_destinations
    if @emoji_ids.empty? && @shortcodes.blank?
      render_selection_error(t('wxw_emoji.favorites.no_selection'))
      return render :choose, status: 422
    end

    current_user.with_lock do
      @pack.with_lock do
        ids = resolved_emoji_ids
        return render :choose, status: 422 unless ids

        if @operation == 'add'
          add_members(ids)
        else
          @pack.favorites.where(custom_emoji_id: ids).destroy_all
        end
        @pack.touch
      end
    end
    redirect_to search_settings_preferences_emoji_packs_path(pack_id: @pack.id), notice: t('generic.changes_saved_msg')
  end

  private

  def favorite_scope
    ::Wxw::EmojiPack.where(user_id: current_user.id)
  end

  def set_pack
    @pack = favorite_scope.find(params[:id])
  end

  def ordered_packs
    by_id = ::Wxw::EmojiPack.management_packs(current_user).index_by(&:id)
    Array(::Wxw::EmojiPack.order_ids(current_user)).filter_map { |id| by_id.delete(id) } + by_id.values
  end

  def ordered_favorites
    ordered_packs.select(&:favorite?)
  end

  def load_destinations
    @packs = ordered_favorites
    @target_pack_id = params[:target_pack_id].to_s
  end

  def resource_params
    params.expect(wxw_emoji_pack: [:name, :featured_shortcode])
  end

  def submitted_ids(key)
    raw = params[key] || []
    raise ActionController::BadRequest unless raw.is_a?(Array) && raw.all?(String)

    ids = raw.reject(&:empty?).map { |value| Integer(value, exception: false) }
    raise ActionController::BadRequest unless ids.all? { |id| id&.positive? && id <= 9_223_372_036_854_775_807 } && ids.uniq.size == ids.size

    ids
  end

  def resolved_emoji_ids
    codes = @shortcodes.split(/[\s,，]+/).reject(&:empty?).map { |code| code.delete_prefix(':').delete_suffix(':') }.uniq
    scope = @operation == 'add' ? CustomEmoji.listed : CustomEmoji.local
    by_code = scope.where(shortcode: codes).pluck(:shortcode, :id).to_h
    missing = codes - by_code.keys
    return render_selection_error(t('wxw_emoji.favorites.invalid_shortcodes', shortcodes: missing.join(', '))) if missing.any?

    ids = (@emoji_ids + codes.filter_map { |code| by_code[code] }).uniq
    return render_selection_error(t('wxw_emoji.favorites.no_selection')) if ids.empty?
    raise ActionController::BadRequest unless scope.where(id: ids).count == ids.size

    ids
  end

  def add_members(ids)
    ids.each do |id|
      ::Wxw::EmojiFavorite.find_or_initialize_by(user: current_user, custom_emoji_id: id).update!(pack: @pack)
    end
  end

  def render_selection_error(message)
    @selection_error = message
    nil
  end
end
