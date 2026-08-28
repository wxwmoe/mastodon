# frozen_string_literal: true

module Admin
  class EmojiPacksController < BaseController
    before_action :set_pack, only: [:edit, :update]
    before_action :set_sections, only: [:edit, :update]

    def index
      authorize :custom_emoji, :index?
      load_index
    end

    def edit
      authorize :custom_emoji, :update?
    end

    def update
      authorize :custom_emoji, :update?
      if @pack.update(resource_params)
        redirect_to admin_emoji_packs_path
      else
        render :edit, status: 422
      end
    rescue ActiveRecord::RecordNotUnique
      @pack.errors.add(:base, :taken)
      render :edit, status: 422
    end

    def batch
      authorize :custom_emoji, :update?
      load_index
      if action_from_button == 'group'
        @pack_ids = selected_batch_ids
        unless @pack_ids&.any?
          return redirect_to admin_emoji_packs_path, alert: I18n.t('wxw_emoji.admin.packs.no_selection')
        end
        set_sections
        return render :group
      end

      unless assign_batch_params
        @packs.first&.errors&.add(:base, :invalid)
        return render :index, status: 422
      end
      Wxw::EmojiPack.transaction { @packs.select(&:changed?).each(&:save!) }
      redirect_to admin_emoji_packs_path
    rescue ActionController::ParameterMissing
      return redirect_to admin_emoji_packs_path, alert: I18n.t('wxw_emoji.admin.packs.no_selection') if action_from_button == 'group'

      @packs.first&.errors&.add(:base, :invalid)
      render :index, status: 422
    rescue ActiveRecord::RecordInvalid
      render :index, status: 422
    end

    def update_group
      authorize :custom_emoji, :update?
      @pack_ids = submitted_group_ids
      return head :unprocessable_entity unless @pack_ids&.any?

      @packs = Wxw::EmojiPack.where(id: @pack_ids).to_a
      return head :unprocessable_entity unless @packs.size == @pack_ids.size

      section_id = params.dig(:emoji_packs, :section_id)
      section = Wxw::EmojiSection.find_by(id: Integer(section_id, exception: false)) if section_id.present?
      if section_id.present? && !section
        @packs.first.errors.add(:base, :invalid)
        set_sections
        return render :group, status: 422
      end

      Wxw::EmojiPack.transaction { @packs.each { |pack| pack.update!(section: section) } }
      redirect_to admin_emoji_packs_path
    end

    def publish
      authorize :custom_emoji, :update?
      Wxw::EmojiPack.publish!
      redirect_to admin_emoji_packs_path
    end

    def refresh
      authorize :custom_emoji, :update?
      Wxw::EmojiPack.refresh!
      redirect_to admin_emoji_packs_path
    end

    private

    def set_pack
      @pack = Wxw::EmojiPack.find(params[:id])
    end

    def set_sections
      @sections = Wxw::EmojiSection.ordered.to_a
    end

    def load_index
      @packs = Wxw::EmojiPack.ordered.includes(section: :translations, custom_emoji_category: :featured_emoji).to_a
      @pack_icons = Wxw::EmojiPack.icon_emojis_for(@packs)
    end

    def resource_params
      params
        .expect(wxw_emoji_pack: [:name, :section_id, :featured_shortcode, custom_emoji_category_attributes: [:name], translations_attributes: [[:id, :language, :name, :_destroy]]])
    end

    def assign_batch_params
      selected_ids = selected_batch_ids
      return false if selected_ids.nil?

      packs = @packs
      case action_from_button
      when 'save_order'
        order = submitted_order_ids
        return false unless order

        by_id = packs.index_by(&:id)
        packs = order.filter_map { |id| by_id[id] }
      when 'reorder'
        packs = @packs.sort_by do |pack|
          section = pack.section
          [section ? 0 : 1, section&.position || 0, section&.id || 0, pack.name_for(I18n.locale).downcase, pack.id]
        end
      end
      if %w(save_order reorder).include?(action_from_button)
        packs.each_with_index do |pack, index|
          pack.position = index + 1
        end
      end
      case action_from_button
      when 'enable', 'disable'
        enabled = action_from_button == 'enable'
        selected = selected_ids.index_with(true)
        packs.each { |pack| pack.default_enabled = enabled if selected.key?(pack.id) }
      when 'save_order', 'reorder'
        nil
      else
        return false
      end
      true
    end

    def selected_batch_ids
      raw = params.expect(emoji_packs: {}).to_h
      rows = raw.each_with_object({}) do |(id, values), result|
        id = Integer(id, exception: false)
        return unless id&.positive? && values.is_a?(Hash)

        result[id] = values
      end
      return unless rows.size == raw.size && rows.keys.sort == @packs.map(&:id).sort

      valid_selections = %w(0 1)
      @packs.each do |pack|
        values = rows.fetch(pack.id)
        return unless values['selected'].is_a?(String) && valid_selections.include?(values['selected'])
      end

      @packs.filter_map { |pack| pack.id if rows.fetch(pack.id)['selected'] == '1' }
    end

    def submitted_group_ids
      raw = params.dig(:emoji_packs, :ids)
      return unless raw.is_a?(Array) && raw.all?(String)

      ids = raw.map { |id| Integer(id, exception: false) }
      return unless ids.all? { |id| id&.positive? }

      ids.uniq
    end

    def submitted_order_ids
      raw = params[:order]
      return unless raw.is_a?(Array) && raw.all?(String)

      ids = raw.map { |id| Integer(id, exception: false) }
      return unless ids.all? { |id| id&.positive? }
      return unless ids.uniq.size == ids.size && ids.sort == @packs.map(&:id).sort

      ids
    end

    def action_from_button
      return 'enable' if params[:enable]
      return 'disable' if params[:disable]
      return 'group' if params[:group]
      return 'reorder' if params[:reorder]
      return 'save_order' if params[:save_order]

      nil
    end
  end
end
