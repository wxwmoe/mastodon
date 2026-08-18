#!/bin/bash
set -e
MASTODON_VERSION="4.6.6"

# 拉取源代码
rm -rf src && wget --progress=dot:giga "https://github.com/mastodon/mastodon/archive/refs/tags/v${MASTODON_VERSION}.tar.gz" -O source.tar.gz
mkdir src && tar -xzf source.tar.gz --strip-components=1 -C src && rm -rf source.tar.gz

# 替换图标文件
cp icons/*.png src/app/javascript/icons
cp images/* src/app/javascript/images
cp icons/paw.svg src/app/javascript/material-icons/400-24px

# 修改字数上限
sed -i "s|MAX_CHARS = 500|MAX_CHARS = 20000|" src/app/validators/status_length_validator.rb

# 修改媒体上限
sed -i "s|pixels: 8_294_400|pixels: 9_999_999|" src/app/models/media_attachment.rb
sed -i "s|IMAGE_LIMIT = 16|IMAGE_LIMIT = 99|" src/app/models/media_attachment.rb

# 修改投票上限
sed -i "s|MAX_OPTIONS      = 4|MAX_OPTIONS      = 16|" src/app/validators/poll_options_validator.rb

# 安装站点主题
bash theme.sh || exit 1
bash emoji.sh || exit 1

# 修复回复建议
grep -Fq '(\\s[${WORD}]+)?$' src/app/javascript/mastodon/components/autosuggest/utils.ts
sed -i '/const regex = new RegExp(/,/);/s|]+(.*|]+$`,|' src/app/javascript/mastodon/components/autosuggest/utils.ts
grep -Fq '${WORD}+-]+$' src/app/javascript/mastodon/components/autosuggest/utils.ts

# 替换媒体资源网址
grep -qx "initializeLogLevel(process.env, environment);" src/streaming/index.js
grep -qx "      output(event, encodedPayload);" src/streaming/index.js
sed -i -e '/^initializeLogLevel(process.env, environment);$/a\const streamingMediaHosts = process.env.STREAMING_MEDIA_HOSTS?.trim() ? JSON.parse(process.env.STREAMING_MEDIA_HOSTS) : null;\nconst rewriteMediaHost = (payload, req) => {\n  const host = streamingMediaHosts?.hosts?.[req.headers.host?.replace(/:[0-9]+$/, "").toLowerCase()];\n  return host \&\& Array.isArray(streamingMediaHosts.source) ? streamingMediaHosts.source.filter(Boolean).reduce((rewritten, source) => rewritten.replaceAll(source, host), payload) : payload;\n};' -e 's|^      output(event, encodedPayload);$|      output(event, rewriteMediaHost(encodedPayload, req));|' src/streaming/index.js

# 替换当前热门入口
grep -qx "import SearchIcon from '@/material-icons/400-24px/search.svg?react';" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
grep -qx "              to='/explore'" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
sed -i -e "s|^import SearchIcon from '@/material-icons/400-24px/search.svg?react';$|import PawIcon from '@/material-icons/400-24px/paw.svg?react';|" -e "s|^  menu: { id: 'tabs_bar.menu', defaultMessage: 'Menu' },$|&\n  firehose: { id: 'column.firehose', defaultMessage: 'Live feeds' },|" -e "s|^              title={intl.formatMessage(messages.search)}$|              title={intl.formatMessage(messages.firehose)}|" -e "s|^              to='/explore'$|              to='/public/local'|" -e "s|^              icon={<Icon id='' icon={SearchIcon} />}$|              icon={<Icon id='' icon={PawIcon} />}|" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx

# 调整媒体请求阈值
grep -qx "  throttle('throttle_media_proxy', limit: 30, period: 10.minutes) do |req|" src/config/initializers/rack_attack.rb
sed -i "/throttle_media_proxy/,/end$/c\  throttle('throttle_media_proxy_authenticated', limit: 600, period: 10.minutes) do |req|\n    (req.authenticated_user_id || req.warden_user_id) if req.path.start_with?('/media_proxy')\n  end\n\n  throttle('throttle_media_proxy_unauthenticated', limit: 30, period: 1.hour) do |req|\n    req.throttleable_remote_ip if req.path.start_with?('/media_proxy') \&\& !req.authenticated_user_id \&\& !req.warden_user_id\n  end" src/config/initializers/rack_attack.rb

# 全文搜索中文优化
sed -i "/verbatim/,/}/{s|standard|ik_max_word|}" src/app/chewy/accounts_index.rb
sed -i "s|analyzer: {|char_filter: {\n      tsconvert: {\n        type: 'stconvert',\n        keep_both: false,\n        delimiter: '#',\n        convert_type: 't2s',\n      },\n    },\n\n    analyzer: {|" src/app/chewy/{statuses_index,public_statuses_index,tags_index}.rb
sed -i "/content/,/}/{s|standard'|ik_max_word',\n        char_filter: %w(tsconvert)|}" src/app/chewy/{statuses_index,public_statuses_index}.rb
sed -i "s|keyword'|ik_smart',\n        char_filter: %w(tsconvert)|" src/app/chewy/tags_index.rb

# 修改版本输出样式
sed -i "/to_s/,/repository/{s|+|~|}" src/lib/mastodon/version.rb

# 修改 Mastodon 版本
sed -i 's|ARG MASTODON_VERSION_METADATA=""|ARG MASTODON_VERSION_METADATA="wxw"|' src/Dockerfile
sed -i '/ARG MASTODON_VERSION_METADATA/a\ENV GITHUB_REPOSITORY="wxwmoe/mastodon"' src/Dockerfile

# 编译 Mastodon 镜像
cd src && docker build --no-cache -t wxwmoe/mastodon -t wxwmoe/mastodon:v${MASTODON_VERSION} . && cd ..

# 编译 Streaming 镜像
printf 'FROM ghcr.io/mastodon/mastodon-streaming:v%s\nCOPY index.js /opt/mastodon/streaming/index.js\n' "${MASTODON_VERSION}" > src/streaming/Dockerfile
cd src/streaming && docker build -t wxwmoe/mastodon-streaming -t wxwmoe/mastodon-streaming:v${MASTODON_VERSION} . && cd ../..
