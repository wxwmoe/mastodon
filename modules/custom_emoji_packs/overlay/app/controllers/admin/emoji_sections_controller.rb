# frozen_string_literal: true

module Admin
  class EmojiSectionsController < BaseController
    before_action :set_section, except: [:index, :new, :create, :batch]

    def index
      authorize :custom_emoji, :index?
      load_sections
    end

    def new
      authorize :custom_emoji, :create?
      @section = Wxw::EmojiSection.new
    end

    def edit
      authorize :custom_emoji, :update?
    end

    def create
      authorize :custom_emoji, :create?
      @section = Wxw::EmojiSection.new(resource_params.merge(position: next_position))
      if @section.save
        redirect_to admin_emoji_sections_path
      else
        render :new, status: 422
      end
    rescue ActiveRecord::RecordNotUnique
      @section.errors.add(:base, :taken)
      render :new, status: 422
    end

    def update
      authorize :custom_emoji, :update?
      if @section.update(resource_params)
        redirect_to admin_emoji_sections_path
      else
        render :edit, status: 422
      end
    rescue ActiveRecord::RecordNotUnique
      @section.errors.add(:base, :taken)
      render :edit, status: 422
    end

    def destroy
      authorize :custom_emoji, :destroy?
      return redirect_to admin_emoji_sections_path if @section.destroy

      load_sections
      render :index, status: 422
    end

    def batch
      action = action_from_button
      authorize :custom_emoji, action == 'delete' ? :destroy? : :update?
      load_sections
      case action
      when 'save_order'
        order = submitted_order_ids
        return render_invalid_submission unless order

        by_id = @sections.index_by(&:id)
        Wxw::EmojiSection.transaction do
          order.each_with_index { |id, index| by_id.fetch(id).update!(position: index + 1) }
        end
      when 'delete'
        selected_ids = selected_batch_ids
        return render_invalid_submission unless selected_ids&.any?

        by_id = @sections.index_by(&:id)
        Wxw::EmojiSection.transaction { selected_ids.each { |id| by_id.fetch(id).destroy! } }
      else
        return render_invalid_submission
      end
      redirect_to admin_emoji_sections_path
    rescue ActionController::ParameterMissing
      render_invalid_submission
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => error
      @section = error.record
      render :index, status: 422
    end

    private

    def set_section
      @section = Wxw::EmojiSection.find(params[:id])
    end

    def load_sections
      @sections = Wxw::EmojiSection.ordered.to_a
    end

    def next_position
      (Wxw::EmojiSection.maximum(:position) || 0) + 1
    end

    def resource_params
      params
        .expect(wxw_emoji_section: [:name, translations_attributes: [[:id, :language, :name, :_destroy]]])
    end

    def submitted_order_ids
      raw = params[:order]
      return unless raw.is_a?(Array) && raw.all?(String)

      ids = raw.map { |id| Integer(id, exception: false) }
      return unless ids.all? { |id| id&.positive? }
      return unless ids.uniq.size == ids.size && ids.sort == @sections.map(&:id).sort

      ids
    end

    def selected_batch_ids
      raw = params.expect(emoji_sections: {}).to_h
      rows = raw.each_with_object({}) do |(id, values), result|
        id = Integer(id, exception: false)
        return unless id&.positive? && values.is_a?(Hash)

        result[id] = values
      end
      return unless rows.size == raw.size && rows.keys.sort == @sections.map(&:id).sort

      valid_selections = %w(0 1)
      @sections.each do |section|
        values = rows.fetch(section.id)
        return unless values['selected'].is_a?(String) && valid_selections.include?(values['selected'])
      end

      @sections.filter_map { |section| section.id if rows.fetch(section.id)['selected'] == '1' }
    end

    def action_from_button
      return 'save_order' if params[:save_order]
      return 'delete' if params[:delete]

      nil
    end

    def render_invalid_submission
      @section = @sections.first
      @section&.errors&.add(:base, :invalid)
      render :index, status: 422
    end
  end
end
