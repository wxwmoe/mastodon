#!/bin/bash
set -euo pipefail

styles_dir="app/javascript/styles"
source_tmp="$(mktemp -d)"; trap 'rm -rf "$source_tmp"' EXIT

mkdir -p "$styles_dir" config/locales

# Mastodon Bird UI
bird_ui_dir="$styles_dir/mastodon-bird-ui"
bird_ui_tmp="$source_tmp/bird-ui"
mkdir -p "$bird_ui_tmp"
curl --fail --silent --show-error --location --retry 2 --output "$bird_ui_tmp/source.tar.gz" "https://codeload.github.com/rollecode/mastodon-bird-ui/tar.gz/refs/tags/4.0.0"
printf '%s  %s\n' aec8fcf50551ce8438b0df61e8efe4a4404b7c61a204157e1fa3280a2d978c87 "$bird_ui_tmp/source.tar.gz" | sha256sum --check
tar -xzf "$bird_ui_tmp/source.tar.gz" --strip-components=1 -C "$bird_ui_tmp"
mkdir -p "$bird_ui_dir"
cp "$bird_ui_tmp/src/_index.scss" "$bird_ui_dir/_index.scss"
for dir in variables components components/profile components/profile/icons layouts micro-interactions variants; do
  mkdir -p "$bird_ui_dir/$dir"
  cp "$bird_ui_tmp/src/$dir/"_*.scss "$bird_ui_dir/$dir/"
done

# Tangerine Neue
tangerine_tmp="$source_tmp/tangerine"
mkdir -p "$tangerine_tmp"
curl --fail --silent --show-error --location --retry 2 --output "$tangerine_tmp/source.tar.gz" "https://codeload.github.com/mattbirchler/Tangerine-Neue-for-Mastodon/tar.gz/refs/tags/2.6.5"
printf '%s  %s\n' eef6767ed8d2f18cf29a55d3bc00808ac9e3cea27ba01b2e5fb28cd1a93d54ae "$tangerine_tmp/source.tar.gz" | sha256sum --check
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
cp "$tangerine_tmp/mastodon/config/locales/tangerineui.yml" config/locales/tangerineui.yml

cp "$bird_ui_tmp/LICENSE" "$bird_ui_dir/LICENSE"
cp "$tangerine_tmp/LICENSE" "$styles_dir/tangerineui/LICENSE"
