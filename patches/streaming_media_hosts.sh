#!/bin/bash
set -e

grep -Fqx "initializeLogLevel(process.env, environment);" src/streaming/index.js
grep -Fqx "      output(event, encodedPayload);" src/streaming/index.js
sed -i -e '/^initializeLogLevel(process.env, environment);$/a\const streamingMediaHosts = process.env.STREAMING_MEDIA_HOSTS?.trim() ? JSON.parse(process.env.STREAMING_MEDIA_HOSTS) : null;\nconst rewriteMediaHost = (payload, req) => {\n  const host = streamingMediaHosts?.hosts?.[req.headers.host?.replace(/:[0-9]+$/, "").toLowerCase()];\n  return host \&\& Array.isArray(streamingMediaHosts.source) ? streamingMediaHosts.source.filter(Boolean).reduce((rewritten, source) => rewritten.replaceAll(source, host), payload) : payload;\n};' -e 's|^      output(event, encodedPayload);$|      output(event, rewriteMediaHost(encodedPayload, req));|' src/streaming/index.js
grep -Fqx "const streamingMediaHosts = process.env.STREAMING_MEDIA_HOSTS?.trim() ? JSON.parse(process.env.STREAMING_MEDIA_HOSTS) : null;" src/streaming/index.js
grep -Fqx "  const host = streamingMediaHosts?.hosts?.[req.headers.host?.replace(/:[0-9]+$/, \"\").toLowerCase()];" src/streaming/index.js
grep -Fqx "  return host && Array.isArray(streamingMediaHosts.source) ? streamingMediaHosts.source.filter(Boolean).reduce((rewritten, source) => rewritten.replaceAll(source, host), payload) : payload;" src/streaming/index.js
grep -Fqx "      output(event, rewriteMediaHost(encodedPayload, req));" src/streaming/index.js
