# frozen_string_literal: true

module Wxw::Named
  extend ActiveSupport::Concern

  NAME_LIMIT = 255

  included do
    has_many :translations,
             -> { order(language: :asc) },
             class_name: 'Wxw::EmojiTranslation',
             as: :translatable,
             inverse_of: :translatable,
             dependent: :destroy
    accepts_nested_attributes_for :translations,
                                  reject_if: ->(attributes) { attributes['name'].blank? },
                                  allow_destroy: true
    validates :name, presence: true, length: { maximum: NAME_LIMIT }
  end

  def name_for(locale)
    tag = locale.to_s
    by_language = translations.index_by(&:language)

    [tag, tag.split('-').first, 'en'].uniq.filter_map { |language| by_language[language]&.name.presence }.first || name
  end
end
