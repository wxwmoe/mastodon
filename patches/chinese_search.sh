#!/bin/bash
set -e

grep -Fqx "        tokenizer: 'standard'," src/app/chewy/accounts_index.rb
sed -i "/verbatim/,/}/{s|tokenizer: 'standard'|tokenizer: 'ik_max_word'|}" src/app/chewy/accounts_index.rb
grep -Fqx "        tokenizer: 'ik_max_word'," src/app/chewy/accounts_index.rb
for file in src/app/chewy/{statuses_index,public_statuses_index,tags_index}.rb; do grep -Fqx "    analyzer: {" "$file"; done
sed -i "s|^    analyzer: {$|    char_filter: {\n      tsconvert: {\n        type: 'stconvert',\n        keep_both: false,\n        delimiter: '#',\n        convert_type: 't2s',\n      },\n    },\n\n    analyzer: {|" src/app/chewy/{statuses_index,public_statuses_index,tags_index}.rb
for file in src/app/chewy/{statuses_index,public_statuses_index,tags_index}.rb; do grep -Fqx "    char_filter: {" "$file"; done
for file in src/app/chewy/{statuses_index,public_statuses_index}.rb; do grep -Fqx "        tokenizer: 'standard'," "$file"; done
sed -i "/content/,/}/{s|tokenizer: 'standard'|tokenizer: 'ik_max_word',\n        char_filter: %w(tsconvert)|}" src/app/chewy/{statuses_index,public_statuses_index}.rb
for file in src/app/chewy/{statuses_index,public_statuses_index}.rb; do grep -Fqx "        tokenizer: 'ik_max_word'," "$file"; grep -Fqx "        char_filter: %w(tsconvert)," "$file"; done
grep -Fqx "        tokenizer: 'keyword'," src/app/chewy/tags_index.rb
sed -i "s|^        tokenizer: 'keyword',$|        tokenizer: 'ik_smart',\n        char_filter: %w(tsconvert),|" src/app/chewy/tags_index.rb
grep -Fqx "        tokenizer: 'ik_smart'," src/app/chewy/tags_index.rb
grep -Fqx "        char_filter: %w(tsconvert)," src/app/chewy/tags_index.rb
