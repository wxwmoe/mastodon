# frozen_string_literal: true

module Wxw::ThemeColors
  MASK_ICON = '#F596AA'
  PALETTES = {
    'mastodon-sakura' => { dark: '#0B346E', light: '#F596AA' },
    'mastodon-bird-ui-sakura' => { dark: '#0B1013', light: '#FEDFE1' },
  }.freeze

  def self.for(theme)
    PALETTES.fetch(theme, Themes::THEME_COLORS)
  end
end
