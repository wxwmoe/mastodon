#!/bin/bash
set -e
MASTODON_VERSION="4.7.0"

# 拉取源代码
rm -rf src && wget "https://github.com/mastodon/mastodon/archive/refs/tags/v${MASTODON_VERSION}.tar.gz" -O source.tar.gz
mkdir src && tar -xzf source.tar.gz --strip-components=1 -C src && rm -rf source.tar.gz

# 替换图标文件
bash patches/replace_icons.sh

# 修改字数上限
bash patches/status_limit.sh

# 放宽正则超时
bash patches/regexp_timeout.sh

# 兜底正则超时
bash patches/extractor_timeout_fallback.sh

# 修改媒体上限
bash patches/media_limits.sh

# 修改投票上限
bash patches/poll_limit.sh

# 安装站点主题
bash patches/install_themes.sh

# 安装表情预览
bash patches/custom_emoji_preview.sh

# 修复回复建议
bash patches/reply_autosuggest.sh

# 替换媒体资源网址
bash patches/streaming_media_hosts.sh

# 替换当前热门入口
bash patches/navigation_entry.sh

# 调整媒体请求阈值
bash patches/media_proxy_rate_limit.sh

# 全文搜索中文优化
bash patches/chinese_search.sh

# 修改版本输出样式
bash patches/version_format.sh

# 修改 Mastodon 版本
bash patches/docker_version_metadata.sh

# 编译 Mastodon 镜像
cd src && docker build --no-cache -t wxwmoe/mastodon -t wxwmoe/mastodon:v${MASTODON_VERSION} . && cd ..

# 编译 Streaming 镜像
printf 'FROM ghcr.io/mastodon/mastodon-streaming:v%s\nCOPY index.js /opt/mastodon/streaming/index.js\n' "${MASTODON_VERSION}" > src/streaming/Dockerfile
cd src/streaming && docker build -t wxwmoe/mastodon-streaming -t wxwmoe/mastodon-streaming:v${MASTODON_VERSION} . && cd ../..
