# frozen_string_literal: true

class Wxw::EmojiPack < ApplicationRecord
  self.table_name = 'wxw_emoji_packs'

  include Wxw::Named

  PICKS_KEY = 'wxw_emoji.picks'
  ORDER_KEY = 'wxw_emoji.order'
  NUMBERED_KEY = 'wxw_emoji.numbered'
  VERSION_KEY = 'wxw_emoji.version'

  belongs_to :user, optional: true
  belongs_to :section, class_name: 'Wxw::EmojiSection', inverse_of: :packs, optional: true
  belongs_to :custom_emoji_category, optional: true
  belongs_to :featured_emoji, class_name: 'CustomEmoji', optional: true
  has_many :favorites, class_name: 'Wxw::EmojiFavorite', foreign_key: :pack_id, inverse_of: :pack, dependent: :delete_all
  has_many :custom_emojis, through: :favorites
  accepts_nested_attributes_for :custom_emoji_category, update_only: true
  validates :custom_emoji_category_id, uniqueness: true, allow_nil: true
  validates :custom_emoji_category, presence: true, unless: :favorite?
  validates :user, presence: true, if: :favorite?
  validates :custom_emoji_category_id, :section_id, absence: true, if: :favorite?
  validates :translations, absence: true, if: :favorite?
  before_validation :assign_featured_shortcode
  after_create :add_to_user_selection, if: :favorite?
  after_destroy :remove_from_user_selection, if: :favorite?
  attr_writer :featured_shortcode

  scope :public_packs, -> { where(user_id: nil) }
  scope :favorites, -> { where.not(user_id: nil) }
  scope :for_user, ->(user) { where(user_id: [nil, user&.id]) }
  scope :ordered, -> { includes(:translations).order(:position, :id) }

  def favorite?
    user_id.present? || user.present?
  end

  def name_for(locale)
    favorite? ? name : super
  end

  def featured_shortcode
    return @featured_shortcode if defined?(@featured_shortcode)

    return unless featured_emoji

    [featured_emoji.shortcode, featured_emoji.domain].compact.join('@')
  end

  private

  def assign_featured_shortcode
    return unless defined?(@featured_shortcode)

    code = @featured_shortcode.to_s.strip
    if code.empty?
      self.featured_emoji = nil
      return
    end

    code = code[1...-1] if code.start_with?(':') && code.end_with?(':')
    shortcode, domain = code.split('@', 2)
    emoji = CustomEmoji.find_by(shortcode: shortcode, domain: domain&.downcase) if shortcode&.match?(CustomEmoji::SHORTCODE_ONLY_RE) && (domain.nil? || domain.present?)
    if emoji
      self.featured_emoji = emoji
    else
      errors.add(:featured_shortcode, :invalid)
    end
  end

  def add_to_user_selection
    user.with_lock do
      picks = self.class.picked_ids(user)
      user.settings[PICKS_KEY] = self.class.dump_ids([id, *picks]) unless picks.nil?
      order = self.class.order_ids(user)
      user.settings[ORDER_KEY] = self.class.dump_ids([id, *order]) unless order.nil?
      user.update_column(:settings, user.settings)
    end
  end

  def remove_from_user_selection
    user.with_lock do
      [PICKS_KEY, ORDER_KEY].each do |key|
        ids = self.class.setting_ids(user, key)
        user.settings[key] = self.class.dump_ids(ids - [id]) unless ids.nil?
      end
      user.update_column(:settings, user.settings)
    end
  end

  class << self
    def management_packs(user)
      favorites_for(user) + public_packs.ordered.includes(:featured_emoji, section: :translations).to_a
    end

    def default_selection(user = nil)
      favorites_for(user) + public_packs.ordered.where(default_enabled: true).to_a
    end

    def favorites_for(user)
      return [] unless user

      favorites.where(user_id: user.id).includes(:featured_emoji).to_a.sort_by { |pack| [pack.name.downcase, pack.id] }
    end

    def picker_entries(selection)
      return [] if selection.empty?

      public_by_category = selection.reject(&:favorite?).index_by(&:custom_emoji_category_id)
      personal_by_id = selection.select(&:favorite?).index_by(&:id)
      favorite_packs = Wxw::EmojiFavorite.where(pack_id: personal_by_id.keys).pluck(:custom_emoji_id, :pack_id).to_h
      emojis = CustomEmoji.listed
      emojis.where(category_id: public_by_category.keys).or(emojis.where(id: favorite_packs.keys))
        .order(:shortcode, :id).map do |emoji|
        [personal_by_id[favorite_packs[emoji.id]] || public_by_category[emoji.category_id], emoji]
      end
    end

    def picker_packs(selection)
      return [] if selection.empty?

      members = Wxw::EmojiFavorite.where(pack_id: selection.select(&:favorite?).map(&:id))
      categories = CustomEmoji.listed.where(category_id: selection.filter_map(&:custom_emoji_category_id))
        .where.not(id: members.select(:custom_emoji_id)).distinct.pluck(:category_id).index_with(true)
      personal = members.joins(:custom_emoji).merge(CustomEmoji.listed).distinct.pluck(:pack_id).index_with(true)
      selection.select { |pack| pack.favorite? ? personal.key?(pack.id) : categories.key?(pack.custom_emoji_category_id) }
    end

    # nil selects defaults; [] selects none.
    def selection_for(user)
      ids = picked_ids(user)
      selection = ids.nil? ? default_selection(user) : ordered_by_ids(ids, user: user)
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
      packs.to_h { |pack| [pack.id, pack.featured_emoji] }
    end

    def ordered_by_ids(ids, user: nil)
      return [] if ids.empty?

      by_id = for_user(user).includes(:translations, :featured_emoji).where(id: ids).index_by(&:id)
      ids.filter_map { |id| by_id[id] }
    end

    def setting_ids(user, key)
      raw = user.settings[key]
      return nil if raw.nil?

      parsed = begin
        JSON.parse(raw)
      rescue JSON::ParserError, TypeError
        nil
      end
      return nil unless parsed.is_a?(Array)

      parsed.filter_map { |value| Integer(value, exception: false) }.uniq
    end

    def publish!
      Setting[VERSION_KEY] = SecureRandom.uuid
    end

    def refresh!
      import_categories!
      cleaned = clean_unavailable_users!
      public_packs.refresh_icons!
      cleaned
    end

    def refresh_icons!
      where(featured_emoji_id: nil).find_each do |pack|
        pack.with_lock do
          next if pack.featured_emoji_id.present?

          emoji = if pack.favorite?
                    pack.custom_emojis.order(:shortcode, :id).first
                  else
                    pack.custom_emoji_category&.featured_emoji || CustomEmoji.where(category_id: pack.custom_emoji_category_id).order(:shortcode, :id).first
                  end
          # Refresh is the only automatic fallback; normal reads never choose an icon.
          pack.update!(featured_emoji: emoji) if emoji
        end
      rescue ActiveRecord::RecordNotFound, ActiveRecord::InvalidForeignKey
        # A pack or its candidate emoji may have been deleted during refresh.
        next
      end
    end

    private

    def import_categories!
      transaction do
        position = public_packs.maximum(:position) || 0
        CustomEmojiCategory.where.not(id: public_packs.select(:custom_emoji_category_id)).order(:id).each do |category|
          name = category.name.presence&.first(Wxw::Named::NAME_LIMIT) || "pack_#{category.id}"
          # Isolate concurrent inserts from the outer transaction.
          begin
            transaction(requires_new: true) do
              create!(custom_emoji_category: category, name: name, position: position + 1)
            end
            position += 1
          rescue ActiveRecord::RecordNotUnique
            next if public_packs.exists?(custom_emoji_category_id: category.id)

            raise
          rescue ActiveRecord::RecordInvalid => error
            raise unless error.record.errors.size == 1 && error.record.errors.of_kind?(:custom_emoji_category_id, :taken)
            raise unless public_packs.exists?(custom_emoji_category_id: category.id)
          end
        end
      end
    end

    def clean_unavailable_users!
      cleaned = { users: 0, packs: 0 }
      User.joins(:account).merge(Account.local)
        .where('accounts.suspended_at IS NOT NULL OR accounts.requested_deletion_at IS NOT NULL')
        .find_each do |user|
        user.account.with_lock do
          user.account.association(:deletion_request).reset
          next unless user.account.permanently_unavailable?

          user.with_lock do
            count = favorites.where(user_id: user.id).delete_all
            original_settings = user.settings.as_json.dup
            [PICKS_KEY, ORDER_KEY, NUMBERED_KEY].each { |key| user.settings[key] = nil }
            next if count.zero? && original_settings == user.settings.as_json

            user.update_column(:settings, user.settings)
            cleaned[:users] += 1
            cleaned[:packs] += count
          end
        end
      rescue ActiveRecord::RecordNotFound
        next
      end
      cleaned
    end
  end
end
