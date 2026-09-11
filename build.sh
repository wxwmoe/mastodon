#!/bin/bash
set -e
MASTODON_VERSION="4.7.1"

# 预校验
if [[ $# -gt 1 || ( $# -eq 1 && $1 != --check && $1 != --no-cache ) ]]; then
  echo "Usage: $0 [--check|--no-cache]" >&2
  exit 2
fi
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
for script in build.sh patches/*.sh; do
  bash -n "$script"
done

# 拉取源代码
echo "Downloading Mastodon ${MASTODON_VERSION} source..."
source_tmp="$(mktemp -d)"; trap 'rm -rf "$source_tmp"' EXIT
wget "https://github.com/mastodon/mastodon/archive/refs/tags/v${MASTODON_VERSION}.tar.gz" -O "$source_tmp/source.tar.gz"
mkdir "$source_tmp/src"
tar -xzf "$source_tmp/source.tar.gz" --strip-components=1 -C "$source_tmp/src"
rm -rf src
mv "$source_tmp/src" src

# 编辑源代码
while read -r patch _; do
  echo "Applying ${patch} patch..."
  bash "patches/${patch}.sh" < /dev/null
done << 'WXW.MOE MASTODON PATCHES'
replace_icons                                 # 替换图标文件
status_limit                                  # 修改字数上限
status_regexp_timeout                         # 修复正则超时
reply_autosuggest                             # 修复回复建议
poll_limit                                    # 修改投票上限
media_limits                                  # 修改媒体上限
install_themes                                # 安装站点主题
custom_emoji_preview                          # 安装表情预览
custom_emoji_packs                            # 安装表情选单
status_settings                               # 安装嘟文扩展
html_status                                   # 支持富文本嘟文
streaming_media_hosts                         # 替换媒体资源网址
registration_reason_dedup                     # 拦截重复注册理由
navigation_entry                              # 替换当前热门入口
rate_limit_tiers                              # 用户年限放宽限速
chinese_search                                # 全文搜索中文优化
version_format                                # 修改版本输出样式
docker_version_metadata                       # 修改 Mastodon 版本
WXW.MOE MASTODON PATCHES
echo "All patches applied."

# 编译 Mastodon 镜像
[[ ${1:-} != --check ]] || exit 0
build_args=()
if [[ ${1:-} == --no-cache ]]; then
  build_args+=(--no-cache)
fi
echo "Building Mastodon ${MASTODON_VERSION} Docker image..."
docker build "${build_args[@]}" -t wxwmoe/mastodon -t wxwmoe/mastodon:v${MASTODON_VERSION} src

# 编译 Mastodon Streaming 镜像
echo "Building Mastodon Streaming ${MASTODON_VERSION} Docker image..."
printf 'FROM ghcr.io/mastodon/mastodon-streaming:v%s\nCOPY index.js /opt/mastodon/streaming/index.js\n' "${MASTODON_VERSION}" > src/streaming/Dockerfile
docker build -t wxwmoe/mastodon-streaming -t wxwmoe/mastodon-streaming:v${MASTODON_VERSION} src/streaming
