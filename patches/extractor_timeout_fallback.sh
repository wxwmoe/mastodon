#!/bin/bash
set -e

grep -Fqx "    entities = extract_urls_with_indices(text, options) +" src/app/lib/extractor.rb
grep -Fqx "               extract_extra_uris_with_indices(text)" src/app/lib/extractor.rb
sed -i '/^    entities = extract_urls_with_indices/,/^               extract_extra_uris_with_indices(text)$/c\    entities = [\n      -> { extract_urls_with_indices(text, options) },\n      -> { extract_hashtags_with_indices(text, check_url_overlap: false) },\n      -> { extract_mentions_or_lists_with_indices(text) },\n      -> { extract_extra_uris_with_indices(text) },\n    ].flat_map do |extract|\n      extract.call\n    rescue Regexp::TimeoutError\n      []\n    end' src/app/lib/extractor.rb
grep -Fqx "    entities = [" src/app/lib/extractor.rb
grep -Fqx "    ].flat_map do |extract|" src/app/lib/extractor.rb
grep -Fqx "    rescue Regexp::TimeoutError" src/app/lib/extractor.rb
