# frozen_string_literal: true

module Wxw::EmojiNavigationHelper
  def wxw_emoji_preferences_navigation(navigation)
    navigation.item :emoji, safe_join([material_symbol('mood'), t('wxw_emoji.title')]), settings_preferences_emoji_packs_path, highlights_on: %r{^/settings/preferences/emoji_packs}
  end

  def wxw_emoji_admin_navigation(navigation)
    navigation.item :emoji_packs, safe_join([material_symbol('tag'), t('wxw_emoji.admin.packs.manage')]), admin_emoji_packs_path, highlights_on: %r{/admin/emoji_}, if: -> { current_user.can?(:manage_custom_emojis) }
  end
end
