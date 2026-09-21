#!/bin/bash
set -e

command -v patch > /dev/null
test -f src/config/initializers/paperclip.rb
overlay="overlay/media_cache_storage"
test -d "$overlay" || { echo "Missing overlay directory: $overlay" >&2; exit 1; }
required_files=(
  app/models/wxw_media_cache.rb
  app/workers/wxw_media_cache_cleanup_worker.rb
  config/initializers/wxw_media_cache_storage.rb
  db/migrate/20260812131419_create_wxw_media_caches.rb
  lib/wxw/media_cache_storage.rb
  lib/wxw/media_cache_storage/attachment.rb
  lib/wxw/media_cache_storage/cli.rb
  lib/wxw/media_cache_storage/migration.rb
)
for file in "${required_files[@]}"; do
  test -f "$overlay/$file" && test -r "$overlay/$file" || { echo "Missing or unreadable overlay file: $file" >&2; exit 1; }
done
files="$(cd "$overlay" && find . -type f -printf '%P\n')"
while IFS= read -r file; do
  [[ ! -e "src/$file" && ! -L "src/$file" ]] || { echo "Refusing to overwrite upstream file: $file" >&2; exit 1; }
done <<< "$files"

patch --dry-run --silent --batch --forward --fuzz=0 -p1 -d src < patches/media_cache_storage.patch
patch --silent --batch --forward --fuzz=0 --no-backup-if-mismatch -p1 -d src < patches/media_cache_storage.patch
cp -R "$overlay/." src/
patch --dry-run --silent --batch --reverse --fuzz=0 -p1 -d src < patches/media_cache_storage.patch
