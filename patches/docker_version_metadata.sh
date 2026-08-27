#!/bin/bash
set -e

grep -Fqx 'ARG MASTODON_VERSION_METADATA=""' src/Dockerfile
sed -i 's|ARG MASTODON_VERSION_METADATA=""|ARG MASTODON_VERSION_METADATA="wxw"|' src/Dockerfile
grep -Fqx 'ARG MASTODON_VERSION_METADATA="wxw"' src/Dockerfile
sed -i '/^ARG MASTODON_VERSION_METADATA="wxw"$/a\ENV GITHUB_REPOSITORY="wxwmoe/mastodon"' src/Dockerfile
grep -Fqx 'ENV GITHUB_REPOSITORY="wxwmoe/mastodon"' src/Dockerfile
