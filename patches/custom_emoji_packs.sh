#!/bin/bash
set -e
migration_version=20260812114514

# 覆盖层文件
conflicts=$(cd overlay/custom_emoji_packs && find . -type f -printf '%P\n' | while read -r f; do
  if test -e "../../src/$f"; then echo "$f"; fi
done)
test -z "$conflicts" || { echo "Refusing to overwrite upstream files: $conflicts" >&2; exit 1; }
test -f "overlay/custom_emoji_packs/db/migrate/${migration_version}_create_wxw_emoji_tables.rb"
cp -R overlay/custom_emoji_packs/. src/

# 接口路由
api_routes="src/config/routes/api.rb"
test "$(grep -Fxc "    resources :custom_emojis, only: [:index]" "$api_routes")" -eq 1
sed -i "s|^    resources :custom_emojis, only: \[:index\]\$|&, controller: 'wxw_custom_emojis'|" "$api_routes"
test "$(grep -Fxc "    resources :custom_emojis, only: [:index], controller: 'wxw_custom_emojis'" "$api_routes")" -eq 1

# 页面路由
routes="src/config/routes.rb"
test "$(grep -Fxc "  draw(:admin)" "$routes")" -eq 1
sed -i 's|^  draw(:admin)$|&\n  draw(:wxw_custom_emojis)|' "$routes"
test "$(grep -Fxc "  draw(:wxw_custom_emojis)" "$routes")" -eq 1

# 用户设置
user_settings="src/app/models/user_settings.rb"
test "$(grep -Fxc "  setting :email_subscriptions, default: false" "$user_settings")" -eq 1
sed -i 's|^  setting :email_subscriptions, default: false$|&\n\n  namespace :wxw_emoji do\n    setting :picks, default: nil\n    setting :order, default: nil\n    setting :numbered, default: true\n    setting :version, default: nil\n  end|' "$user_settings"
test "$(grep -Fxc "  namespace :wxw_emoji do" "$user_settings")" -eq 1
test "$(grep -Fxc "    setting :picks, default: nil" "$user_settings")" -eq 1
test "$(grep -Fxc "    setting :order, default: nil" "$user_settings")" -eq 1
test "$(grep -Fxc "    setting :numbered, default: true" "$user_settings")" -eq 1
test "$(grep -Fxc "    setting :version, default: nil" "$user_settings")" -eq 1

# 导航菜单
navigation="src/config/navigation.rb"
test "$(grep -c '^      s\.item :appearance,' "$navigation")" -eq 1
test "$(grep -c '^      s\.item :custom_emojis,' "$navigation")" -eq 1
sed -i "/^      s\.item :appearance,/a\      s.item :emoji, safe_join([material_symbol('mood'), t('wxw_emoji.title')]), settings_preferences_emoji_packs_path, highlights_on: %r{^/settings/preferences/emoji_packs}" "$navigation"
sed -i "/^      s\.item :custom_emojis,/a\      s.item :emoji_packs, safe_join([material_symbol('tag'), t('wxw_emoji.admin.packs.manage')]), admin_emoji_packs_path, highlights_on: %r{/admin/emoji_}, if: -> { current_user.can?(:manage_custom_emojis) }" "$navigation"
test "$(grep -Fc "settings_preferences_emoji_packs_path" "$navigation")" -eq 1
test "$(grep -Fc "admin_emoji_packs_path" "$navigation")" -eq 1

# 拖拽排序
admin_entry="src/app/javascript/entrypoints/admin.tsx"
test "$(grep -Fxc "import ready from '../mastodon/ready';" "$admin_entry")" -eq 1
sed -i "/^import ready from '..\/mastodon\/ready';$/a import '../wxw_custom_emojis';" "$admin_entry"
test "$(grep -Fxc "import '../wxw_custom_emojis';" "$admin_entry")" -eq 1

# 样式入口
application_styles="src/app/javascript/styles/application.scss"
test "$(grep -Fxc "@use 'mastodon/admin';" "$application_styles")" -eq 1
sed -i "/^@use 'mastodon\/admin';$/a @use 'mastodon/wxw_custom_emojis';" "$application_styles"
test "$(grep -Fxc "@use 'mastodon/wxw_custom_emojis';" "$application_styles")" -eq 1

# 数据库结构同步（保留上游版本号）
schema="src/db/schema.rb"
schema_version=$(sed -n 's|^ActiveRecord::Schema\[[^]]*\]\.define(version: \([0-9_]*\)).*|\1|p' "$schema" | tr -d _)
test -n "$schema_version"
test "$schema_version" -gt "$migration_version"
test "$(tail -n1 "$schema")" = "end"
test "$(grep -Fc 'create_table "wxw_emoji_' "$schema")" -eq 0
sed -i '$d' "$schema"
printf '%s\n' \
  '' \
  '  create_table "wxw_emoji_packs", force: :cascade do |t|' \
  '    t.datetime "created_at", null: false' \
  '    t.bigint "custom_emoji_category_id", null: false' \
  '    t.boolean "default_enabled", default: false, null: false' \
  '    t.string "name", default: "", null: false' \
  '    t.integer "position", default: 0, null: false' \
  '    t.bigint "section_id"' \
  '    t.datetime "updated_at", null: false' \
  '    t.index ["custom_emoji_category_id"], name: "index_wxw_emoji_packs_on_custom_emoji_category_id", unique: true' \
  '    t.index ["section_id"], name: "index_wxw_emoji_packs_on_section_id"' \
  '  end' \
  '' \
  '  create_table "wxw_emoji_sections", force: :cascade do |t|' \
  '    t.datetime "created_at", null: false' \
  '    t.string "name", default: "", null: false' \
  '    t.integer "position", default: 0, null: false' \
  '    t.datetime "updated_at", null: false' \
  '  end' \
  '' \
  '  create_table "wxw_emoji_translations", force: :cascade do |t|' \
  '    t.datetime "created_at", null: false' \
  '    t.string "language", null: false' \
  '    t.string "name", default: "", null: false' \
  '    t.bigint "translatable_id", null: false' \
  '    t.string "translatable_type", null: false' \
  '    t.datetime "updated_at", null: false' \
  '    t.index ["translatable_type", "translatable_id", "language"], name: "index_wxw_emoji_translations_on_owner_and_language", unique: true' \
  '  end' \
  'end' >> "$schema"
test "$(grep -Fc 'create_table "wxw_emoji_sections"' "$schema")" -eq 1
test "$(grep -Fc 'create_table "wxw_emoji_packs"' "$schema")" -eq 1
test "$(tail -n1 "$schema")" = "end"
