#!/bin/bash
set -e

test -f overlay/status_highlight/app/javascript/mastodon/components/wxw_code_highlight.tsx

while IFS= read -r file; do
  test ! -e "src/$file" || { echo "Refusing to overwrite upstream file: $file" >&2; exit 1; }
done < <(cd overlay/status_highlight && find . -type f -printf '%P\n')

patch --dry-run --silent --batch --forward --fuzz=0 -p1 -d src < patches/status_highlight.patch
patch --silent --batch --forward --fuzz=0 --no-backup-if-mismatch -p1 -d src < patches/status_highlight.patch
cp -R overlay/status_highlight/. src/
patch --dry-run --silent --batch --reverse --fuzz=0 -p1 -d src < patches/status_highlight.patch
