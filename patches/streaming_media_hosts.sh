#!/bin/bash
set -e

file="src/streaming/index.js"
helper="streaming/wxw_media_hosts.js"
import="import { createMediaHostRewriter } from './wxw_media_hosts.js';"

test -f "overlay/streaming_media_hosts/$helper"
test ! -e "src/$helper"
test "$(grep -Fxc "import { isTruthy, normalizeHashtag, firstParam } from './utils.js';" "$file")" -eq 1
test "$(grep -Fxc "initializeLogLevel(process.env, environment);" "$file")" -eq 1
test "$(grep -Fxc "      output(event, encodedPayload);" "$file")" -eq 1
test "$(grep -Fxc "$import" "$file")" -eq 0

sed -i \
  -e "/^import { isTruthy, normalizeHashtag, firstParam } from '.\/utils.js';$/a\\$import" \
  -e '/^initializeLogLevel(process.env, environment);$/a\const rewriteMediaHost = createMediaHostRewriter(process.env.STREAMING_MEDIA_HOSTS);' \
  -e 's|^      output(event, encodedPayload);$|      output(event, rewriteMediaHost(encodedPayload, req.headers.host));|' \
  "$file"
cp "overlay/streaming_media_hosts/$helper" "src/$helper"

grep -Fqx "$import" "$file"
grep -Fqx "      output(event, rewriteMediaHost(encodedPayload, req.headers.host));" "$file"
