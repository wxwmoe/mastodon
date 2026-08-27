#!/bin/bash
set -e

grep -Fqx $'    `[${searchTokens.join(\'\')}${WORD}+-]+(\\\\s[\\\\p{Script=Latin}\\\\p{Script=Cyrillic}\\\\p{M}]+)?$`,' src/app/javascript/mastodon/components/autosuggest/utils.ts
sed -i '/const regex = new RegExp(/,/);/s|]+(.*|]+$`,|' src/app/javascript/mastodon/components/autosuggest/utils.ts
grep -Fqx $'    `[${searchTokens.join(\'\')}${WORD}+-]+$`,' src/app/javascript/mastodon/components/autosuggest/utils.ts
grep -Fqx "      [1, '#hash tag']," src/app/javascript/mastodon/components/autosuggest/utils.test.ts
grep -Fqx "      [1, '@alice reply']," src/app/javascript/mastodon/components/autosuggest/utils.test.ts
grep -Fqx "      [1, '@алиса пример']," src/app/javascript/mastodon/components/autosuggest/utils.test.ts
sed -i -e "s|      \[1, '#hash tag'\],|      [null, null],|" -e "s|      \[1, '@alice reply'\],|      [null, null],|" -e "s|      \[1, '@алиса пример'\],|      [null, null],|" src/app/javascript/mastodon/components/autosuggest/utils.test.ts
grep -Fqx "      [null, null]," src/app/javascript/mastodon/components/autosuggest/utils.test.ts
test "$(grep -Fxc "      [null, null]," src/app/javascript/mastodon/components/autosuggest/utils.test.ts)" -eq 8
