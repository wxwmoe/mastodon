#!/bin/bash
set -e

grep -Fqx '      components << "+#{build_metadata}" if build_metadata.present?' src/lib/mastodon/version.rb
grep -Fqx "      @gem_version ||= Gem::Version.new(to_s.split('+')[0])" src/lib/mastodon/version.rb
grep -Fqx 'ARG MASTODON_VERSION_METADATA=""' src/Dockerfile

sed -i -e 's|"+#{build_metadata}"|"~#{build_metadata}"|' -e "s|split('+')|split('~')|" src/lib/mastodon/version.rb
grep -Fqx '      components << "~#{build_metadata}" if build_metadata.present?' src/lib/mastodon/version.rb
grep -Fqx "      @gem_version ||= Gem::Version.new(to_s.split('~')[0])" src/lib/mastodon/version.rb

sed -i 's|ARG MASTODON_VERSION_METADATA=""|ARG MASTODON_VERSION_METADATA="wxw"|' src/Dockerfile
grep -Fqx 'ARG MASTODON_VERSION_METADATA="wxw"' src/Dockerfile
sed -i '/^ARG MASTODON_VERSION_METADATA="wxw"$/a\ENV GITHUB_REPOSITORY="wxwmoe/mastodon"' src/Dockerfile
grep -Fqx 'ENV GITHUB_REPOSITORY="wxwmoe/mastodon"' src/Dockerfile
