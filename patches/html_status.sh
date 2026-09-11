#!/bin/bash
set -e

test -f overlay/html_status/app/lib/wxw/html_formatter.rb
test -f src/app/models/wxw_status_setting.rb
while IFS= read -r file; do
  test ! -e "src/$file" || { echo "Refusing to overwrite upstream file: $file" >&2; exit 1; }
done < <(cd overlay/html_status && find . -type f -printf '%P\n')

patch --dry-run --silent --batch --forward --fuzz=0 -p1 -d src < patches/html_status.patch
patch --silent --batch --forward --fuzz=0 --no-backup-if-mismatch -p1 -d src < patches/html_status.patch
cp -R overlay/html_status/. src/
patch --dry-run --silent --batch --reverse --fuzz=0 -p1 -d src < patches/html_status.patch
