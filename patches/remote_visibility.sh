#!/bin/bash
set -e

command -v patch > /dev/null
test -f src/app/models/wxw_status_setting.rb
while IFS= read -r file; do
  test ! -e "src/$file" || { echo "Refusing to overwrite upstream file: $file" >&2; exit 1; }
done < <(cd overlay/remote_visibility && find . -type f -printf '%P\n')

patch --dry-run --silent --batch --forward --fuzz=0 -p1 -d src < patches/remote_visibility.patch
patch --silent --batch --forward --fuzz=0 --no-backup-if-mismatch -p1 -d src < patches/remote_visibility.patch
cp -R overlay/remote_visibility/. src/
patch --dry-run --silent --batch --reverse --fuzz=0 -p1 -d src < patches/remote_visibility.patch
