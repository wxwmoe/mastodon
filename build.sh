#!/bin/bash
set -e
MASTODON_VERSION="4.7.0"

# 拉取源代码
echo "Downloading Mastodon ${MASTODON_VERSION} source..."
rm -rf src && wget "https://github.com/mastodon/mastodon/archive/refs/tags/v${MASTODON_VERSION}.tar.gz" -O source.tar.gz
mkdir src && tar -xzf source.tar.gz --strip-components=1 -C src && rm -rf source.tar.gz

# 编辑源代码
while read -r patch _; do
  echo "Applying ${patch} patch..."
  bash "patches/${patch}.sh" < /dev/null
done << 'WXW.MOE MASTODON PATCHES'
replace_icons                                 # 替换图标文件
status_limit                                  # 修改字数上限
regexp_timeout                                # 放宽正则超时
extractor_timeout_fallback                    # 兜底正则超时
poll_limit                                    # 修改投票上限
media_limits                                  # 修改媒体上限
install_themes                                # 安装站点主题
custom_emoji_preview                          # 安装表情预览
custom_emoji_packs                            # 安装表情选单
reply_autosuggest                             # 修复回复建议
streaming_media_hosts                         # 替换媒体资源网址
navigation_entry                              # 替换当前热门入口
rate_limit_tiers                              # 用户年限放宽限速
chinese_search                                # 全文搜索中文优化
version_format                                # 修改版本输出样式
docker_version_metadata                       # 修改 Mastodon 版本
WXW.MOE MASTODON PATCHES
echo "All patches applied."

# 编译 Mastodon 镜像
echo "Building Mastodon ${MASTODON_VERSION} Docker image..."
cd src && docker build --no-cache -t wxwmoe/mastodon -t wxwmoe/mastodon:v${MASTODON_VERSION} . && cd ..

# 编译 Mastodon Streaming 镜像
echo "Building Mastodon Streaming ${MASTODON_VERSION} Docker image..."
printf 'FROM ghcr.io/mastodon/mastodon-streaming:v%s\nCOPY index.js /opt/mastodon/streaming/index.js\n' "${MASTODON_VERSION}" > src/streaming/Dockerfile
cd src/streaming && docker build -t wxwmoe/mastodon-streaming -t wxwmoe/mastodon-streaming:v${MASTODON_VERSION} . && cd ../..
