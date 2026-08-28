# frozen_string_literal: true

class Wxw::EmojiPack < ApplicationRecord
  include Wxw::Named

  PICKS_KEY = 'wxw_emoji.picks'
  ORDER_KEY = 'wxw_emoji.order'
  NUMBERED_KEY = 'wxw_emoji.numbered'
  VERSION_KEY = 'wxw_emoji.version'

  belongs_to :section, class_name: 'Wxw::EmojiSection', inverse_of: :packs, optional: true
  belongs_to :custom_emoji_category
  accepts_nested_attributes_for :custom_emoji_category, update_only: true
  validates :custom_emoji_category_id, uniqueness: true
  validate :validate_featured_shortcode
  after_save :apply_featured_shortcode
  attr_writer :featured_shortcode

  def featured_shortcode
    return @featured_shortcode if defined?(@featured_shortcode)

    custom_emoji_category&.featured_emoji&.shortcode
  end

  scope :ordered, -> { includes(:translations).order(:position, :id) }

  private

  def featured_shortcode_submitted?
    defined?(@featured_shortcode)
  end

  def resolved_featured_emoji
    code = @featured_shortcode.to_s.strip.delete(':')
    return nil if code.empty?

    CustomEmoji.listed.find_by(shortcode: code, category_id: custom_emoji_category_id)
  end

  def validate_featured_shortcode
    return unless featured_shortcode_submitted?
    return if @featured_shortcode.to_s.strip.delete(':').empty?
    return if resolved_featured_emoji

    errors.add(:featured_shortcode, :invalid)
  end

  def apply_featured_shortcode
    return unless featured_shortcode_submitted?

    custom_emoji_category&.update_column(:featured_emoji_id, resolved_featured_emoji&.id)
  end

  class << self
    def default_selection
      ordered.where(default_enabled: true).to_a
    end

    def picker_packs(selection, category_ids: nil)
      return [] if selection.empty?

      category_ids ||= CustomEmoji.listed
        .where(category_id: selection.map(&:custom_emoji_category_id))
        .distinct
        .pluck(:category_id)
      categories = category_ids.index_with(true)
      selection.select { |pack| categories.key?(pack.custom_emoji_category_id) }
    end

    # nil selects defaults; [] selects none.
    def selection_for(user)
      ids = picked_ids(user)
      selection = ids.nil? ? default_selection : ordered_by_ids(ids)
      order = order_ids(user)
      return selection unless order

      by_id = selection.index_by(&:id)
      order.filter_map { |id| by_id.delete(id) } + by_id.values
    end

    def picked_ids(user)
      setting_ids(user, PICKS_KEY)
    end

    def order_ids(user)
      setting_ids(user, ORDER_KEY)
    end

    def dump_ids(ids)
      JSON.generate(Array(ids).filter_map { |value| Integer(value, exception: false) }.uniq)
    end

    def numbered?(user)
      user.settings[NUMBERED_KEY]
    end

    def publish_version
      Setting[VERSION_KEY]
    end

    def icon_emojis_for(packs)
      categories = packs.filter_map(&:custom_emoji_category).uniq(&:id)
      icons = categories.to_h { |category| [category.id, category.featured_emoji] }
      missing_ids = icons.filter_map { |category_id, emoji| category_id unless emoji }
      if missing_ids.any?
        fallbacks = CustomEmoji.local.enabled
          .where(category_id: missing_ids)
          .select('DISTINCT ON (category_id) custom_emojis.*')
          .order(:category_id, :shortcode, :id)
        icons.merge!(fallbacks.index_by(&:category_id))
      end
      packs.to_h { |pack| [pack.id, icons[pack.custom_emoji_category_id]] }
    end

    def ordered_by_ids(ids)
      return [] if ids.empty?

      by_id = includes(:translations).where(id: ids).index_by(&:id)
      ids.filter_map { |id| by_id[id] }
    end

    def setting_ids(user, key)
      raw = user.settings[key]
      return nil if raw.nil?

      parsed = begin
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
      return nil unless parsed.is_a?(Array)

      parsed.filter_map { |value| Integer(value, exception: false) }.uniq
    end

    def publish!
      Setting[VERSION_KEY] = SecureRandom.uuid
    end

    def refresh!
      transaction do
        position = maximum(:position) || 0
        CustomEmojiCategory.where.not(id: select(:custom_emoji_category_id)).order(:id).each do |category|
          name = category.name.presence&.first(Wxw::Named::NAME_LIMIT) || "pack_#{category.id}"
          # Isolate concurrent inserts from the outer transaction.
          begin
            transaction(requires_new: true) do
              create!(custom_emoji_category: category, name: name, position: position + 1)
            end
            position += 1
          rescue ActiveRecord::RecordNotUnique
            next if exists?(custom_emoji_category_id: category.id)

            raise
          end
        end
      end
    end
  end
end
