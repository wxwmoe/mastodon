#!/bin/bash
set -e

command -v patch > /dev/null
test -f overlay/status_settings/db/migrate/20260812131415_create_wxw_status_settings.rb
while IFS= read -r file; do
  test ! -e "src/$file" || { echo "Refusing to overwrite upstream file: $file" >&2; exit 1; }
done < <(cd overlay/status_settings && find . -type f -printf '%P\n')

schema_version=$(sed -n 's|^ActiveRecord::Schema\[[^]]*\]\.define(version: \([0-9_]*\)).*|\1|p' src/db/schema.rb | tr -d _)
test -n "$schema_version"
test "$schema_version" -gt 20260812131415

patch --dry-run --silent --batch --forward --fuzz=0 -p1 -d src < patches/status_settings.patch
patch --silent --batch --forward --fuzz=0 --no-backup-if-mismatch -p1 -d src < patches/status_settings.patch
cp -R overlay/status_settings/. src/
patch --dry-run --silent --batch --reverse --fuzz=0 -p1 -d src < patches/status_settings.patch
