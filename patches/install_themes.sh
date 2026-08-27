#!/bin/bash
set -e

styles_dir="src/app/javascript/styles"
source_tmp="$(mktemp -d)"; trap 'rm -rf "$source_tmp"' EXIT

# Mastodon Bird UI
bird_ui_dir="$styles_dir/mastodon-bird-ui"
bird_ui_tmp="$source_tmp/bird-ui"
mkdir -p "$bird_ui_tmp"
wget "https://github.com/rollecode/mastodon-bird-ui/archive/5614118f735266dabb7915a8efa11474350698fd.tar.gz" -O "$bird_ui_tmp/source.tar.gz"
tar -xzf "$bird_ui_tmp/source.tar.gz" --strip-components=1 -C "$bird_ui_tmp"
mkdir -p "$bird_ui_dir"
cp "$bird_ui_tmp/src/_index.scss" "$bird_ui_dir/_index.scss"
for dir in variables components components/profile components/profile/icons layouts micro-interactions variants; do
  mkdir -p "$bird_ui_dir/$dir"
  cp "$bird_ui_tmp/src/$dir/"_*.scss "$bird_ui_dir/$dir/"
done
printf '%s\n' '@use "index";' > "$bird_ui_dir/mastodon-bird-ui.scss"
printf '%s\n' "@use 'application';" "@use 'mastodon-bird-ui';" "@use 'mastodon-bird-ui/variables/light-mixin' as light;" '' '[data-color-scheme="light"] {' '  @include light.tokens;' '}' '' '@media (prefers-color-scheme: light) {' '  html:not([data-color-scheme]) {' '    @include light.tokens;' '  }' '}' > "$styles_dir/mastodon-bird-ui-auto.scss"

# Tangerine Neue
tangerine_tmp="$source_tmp/tangerine"
mkdir -p "$tangerine_tmp"
wget "https://github.com/mattbirchler/Tangerine-Neue-for-Mastodon/archive/34cd010bec276d9e180cb2b830eeff9372b161d9.tar.gz" -O "$tangerine_tmp/source.tar.gz"
tar -xzf "$tangerine_tmp/source.tar.gz" --strip-components=1 -C "$tangerine_tmp"
# Show only the active announcement slide.
tangerine_theme_files=("$tangerine_tmp/mastodon/app/javascript/styles"/tangerineui*/tangerineui*.scss)
test "${#tangerine_theme_files[@]}" -eq 5
for tangerine_theme_file in "${tangerine_theme_files[@]}"; do
  awk 'p == ".app-body .announcements {" && $0 == "    overflow: visible;" { found++ } { p = $0 } END { exit found == 1 ? 0 : 1 }' "$tangerine_theme_file"
  sed -i '/^\.app-body \.announcements {$/ { N; s/\n    overflow: visible;$/\n    overflow: hidden;/; }' "$tangerine_theme_file"
  awk 'p == ".app-body .announcements {" && $0 == "    overflow: hidden;" { found++ } { p = $0 } END { exit found == 1 ? 0 : 1 }' "$tangerine_theme_file"
done
cp -R "$tangerine_tmp/mastodon/app/javascript/styles/." "$styles_dir/"
cp "$tangerine_tmp/mastodon/config/locales/tangerineui.yml" src/config/locales/tangerineui.yml

# Sakura themes
: << ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      Generated using ChatGPT 5.6 Sol (Ultra),
|    Sakura palettes sourced from NIPPON COLORS.    |
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
cp -R overlay/themes/styles/. "$styles_dir/"
cp overlay/themes/paw.svg src/app/javascript/material-icons/400-24px

# patch components
announcements_styles="$styles_dir/mastodon/components.scss"
awk 'p2 == "    max-height: 50vh;" && p1 == "    overflow: hidden;" && $0 == "    flex-direction: column;" { found++ } { p2 = p1; p1 = $0 } END { exit found == 1 ? 0 : 1 }' "$announcements_styles"
sed -i '/^    max-height: 50vh;$/ { N; N; s/\n    flex-direction: column;$/\n    display: flex;\n    flex-direction: column;\n\n    > div {\n      display: flex;\n      flex-direction: column;\n      min-height: 0;\n    }/; }' "$announcements_styles"
awk 'p3 == "    max-height: 50vh;" && p2 == "    overflow: hidden;" && p1 == "    display: flex;" && $0 == "    flex-direction: column;" { found++ } { p3 = p2; p2 = p1; p1 = $0 } END { exit found == 1 ? 0 : 1 }' "$announcements_styles"
awk 'p4 == "    > div {" && p3 == "      display: flex;" && p2 == "      flex-direction: column;" && p1 == "      min-height: 0;" && $0 == "    }" { found++ } { p4 = p3; p3 = p2; p2 = p1; p1 = $0 } END { exit found == 1 ? 0 : 1 }' "$announcements_styles"
printf '%s\n' '' '.reactions-bar__item__emoji {' '  overflow: hidden;' '}' >> "$announcements_styles"
printf '%s\n' '' '.announcements__root {' '  flex-direction: column-reverse;' '}' '' '.announcements {' '  width: 100%;' '}' '' '.announcements__mastodon {' '  align-self: flex-start;' '}' >> "$announcements_styles"
printf '%s\n' '' 'html.has-modal:has(> body.layout-multiple-columns),' 'html.has-modal > body.layout-multiple-columns {' '  scrollbar-gutter: auto;' '}' '' '.media-modal__closer > .zoomable-image {' '  overflow: hidden;' '}' >> "$announcements_styles"

# patch theme helper
grep -qx "  def theme_color_tags(color_scheme)" src/app/helpers/theme_helper.rb
grep -q "content: Themes::THEME_COLORS" src/app/helpers/theme_helper.rb
sed -i 's/content: Themes::THEME_COLORS/content: theme_colors/g' src/app/helpers/theme_helper.rb
sed -i "/^  def theme_color_tags(color_scheme)$/a\    theme_colors = { 'mastodon-sakura' => { dark: '#0B346E', light: '#F596AA' }, 'mastodon-bird-ui-sakura' => { dark: '#0B1013', light: '#FEDFE1' } }.fetch(current_theme, Themes::THEME_COLORS)\n" src/app/helpers/theme_helper.rb
grep -Fqx "      %link{ rel: 'mask-icon', href: frontend_asset_path('images/logo-symbol-icon.svg'), color: '#6364FF' }/" src/app/views/layouts/application.html.haml
sed -i "s/color: '#6364FF'/color: '#F596AA'/" src/app/views/layouts/application.html.haml

# patch themes & locales
sed -i '$a\mastodon-sakura: styles/mastodon-sakura.scss\nmastodon-bird-ui-auto: styles/mastodon-bird-ui-auto.scss\nmastodon-bird-ui-sakura: styles/mastodon-bird-ui-sakura.scss\ntangerineui: styles/tangerineui.scss\ntangerineui-purple: styles/tangerineui-purple.scss\ntangerineui-cherry: styles/tangerineui-cherry.scss\ntangerineui-lagoon: styles/tangerineui-lagoon.scss\ntangerineui-granite: styles/tangerineui-granite.scss' src/config/themes.yml
printf '%s\n' 'en:' '  themes:' '    mastodon-sakura: Mastodon (Sakura)' '    mastodon-bird-ui-auto: Mastodon Bird UI' '    mastodon-bird-ui-sakura: Mastodon Bird UI (Sakura)' 'zh-CN:' '  themes:' '    mastodon-sakura: Mastodon · 桜' '    mastodon-bird-ui-sakura: Mastodon Bird UI · 桜' 'zh-HK:' '  themes:' '    mastodon-sakura: Mastodon · 桜' '    mastodon-bird-ui-sakura: Mastodon Bird UI · 桜' 'zh-TW:' '  themes:' '    mastodon-sakura: Mastodon · 桜' '    mastodon-bird-ui-sakura: Mastodon Bird UI · 桜' 'ja:' '  themes:' '    mastodon-sakura: Mastodon · 桜' '    mastodon-bird-ui-sakura: Mastodon Bird UI · 桜' > src/config/locales/themes.yml
