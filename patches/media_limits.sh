#!/bin/bash
set -e

test -f overlay/media_limits/app/lib/wxw/media_limits.rb
test -f overlay/media_limits/app/javascript/mastodon/components/wxw_media_gallery.tsx
test -f overlay/media_limits/app/javascript/mastodon/features/ui/components/wxw_media_modal.tsx
test -f overlay/media_limits/app/javascript/mastodon/features/compose/components/wxw_media_warning.tsx
test -f overlay/media_limits/app/javascript/styles/mastodon/media_limits.scss
while IFS= read -r file; do
  test ! -e "src/$file" || { echo "Refusing to overwrite upstream file: $file" >&2; exit 1; }
done < <(cd overlay/media_limits && find . -type f -printf '%P\n')

patch --dry-run --silent --batch --forward --fuzz=0 -p1 -d src < patches/media_limits.patch
patch --silent --batch --forward --fuzz=0 --no-backup-if-mismatch -p1 -d src < patches/media_limits.patch
cp -R overlay/media_limits/. src/
