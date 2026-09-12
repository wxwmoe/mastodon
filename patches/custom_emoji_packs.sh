#!/bin/bash
set -e

command -v patch > /dev/null
test -f overlay/custom_emoji_packs/db/migrate/20260812114514_create_wxw_emoji_tables.rb
test -f overlay/custom_emoji_packs/db/migrate/20260812121212_add_wxw_emoji_favorites.rb
while IFS= read -r file; do
  test ! -e "src/$file" || { echo "Refusing to overwrite upstream file: $file" >&2; exit 1; }
done < <(cd overlay/custom_emoji_packs && find . -type f -printf '%P\n')

schema_version=$(sed -n 's|^ActiveRecord::Schema\[[^]]*\]\.define(version: \([0-9_]*\)).*|\1|p' src/db/schema.rb | tr -d _)
test -n "$schema_version"
test "$schema_version" -gt 20260812121212

patch --dry-run --silent --batch --forward --fuzz=0 -p1 -d src < patches/custom_emoji_packs.patch
patch --silent --batch --forward --fuzz=0 --no-backup-if-mismatch -p1 -d src < patches/custom_emoji_packs.patch
cp -R overlay/custom_emoji_packs/. src/
patch --dry-run --silent --batch --reverse --fuzz=0 -p1 -d src < patches/custom_emoji_packs.patch
