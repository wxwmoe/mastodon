#!/bin/bash
set -e

grep -Fqx '      components << "+#{build_metadata}" if build_metadata.present?' src/lib/mastodon/version.rb
grep -Fqx "      @gem_version ||= Gem::Version.new(to_s.split('+')[0])" src/lib/mastodon/version.rb
sed -i -e 's|"+#{build_metadata}"|"~#{build_metadata}"|' -e "s|split('+')|split('~')|" src/lib/mastodon/version.rb
grep -Fqx '      components << "~#{build_metadata}" if build_metadata.present?' src/lib/mastodon/version.rb
grep -Fqx "      @gem_version ||= Gem::Version.new(to_s.split('~')[0])" src/lib/mastodon/version.rb
