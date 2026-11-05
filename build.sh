#!/bin/bash
set -euo pipefail
MASTODON_VERSION="4.7.5"

# 预校验
build_mode=${1:-}
if [[ $# -gt 1 || ( $# -eq 1 && $build_mode != --check && $build_mode != --no-cache ) ]]; then
  echo "Usage: $0 [--check|--no-cache]" >&2
  exit 2
fi
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# 编辑源代码
source ./loader/loader.sh
APPLY << WXW.MOE_MASTODON_PATCHES
replace_icons                                     # 替换图标文件
status_limit                                      # 修改字数上限
status_regexp_timeout                             # 修复正则超时
status_reply_autosuggest                          # 修复回复建议
status_poll_limit                                 # 修改投票上限
media_limits                                      # 修改媒体上限
media_cache_storage                               # 外站独立缓存
install_themes                                    # 安装站点主题
custom_emoji_preview                              # 安装表情预览
custom_emoji_packs                                # 安装表情选单
status_settings                                   # 安装嘟文扩展
status_highlight                                  # 支持代码高亮
status_rich_text                                  # 支持富文本嘟文
status_remote_visibility                          # 支持外站可见性
streaming_media_hosts                             # 替换媒体资源网址
registration_reason_dedup                         # 拦截重复注册理由
navigation_entry                                  # 替换当前热门入口
rate_limit_tiers                                  # 用户年限放宽限速
chinese_search                                    # 全文搜索中文优化
WXW.MOE_MASTODON_PATCHES

# 编译 Mastodon 镜像
[[ $build_mode != --check ]] || exit 0

build_args=()
if [[ $build_mode == --no-cache ]]; then
  build_args+=(--no-cache)
fi

echo "Building Mastodon ${MASTODON_VERSION} Docker image..."
docker build "${build_args[@]}" -f src/Dockerfile \
  -t wxwmoe/mastodon -t "wxwmoe/mastodon:v${MASTODON_VERSION}" src

echo "Building Mastodon Streaming ${MASTODON_VERSION} Docker image..."
docker build "${build_args[@]}" -f src/streaming/Dockerfile --build-arg MASTODON_VERSION_METADATA=wxw \
  -t wxwmoe/mastodon-streaming -t "wxwmoe/mastodon-streaming:v${MASTODON_VERSION}" src
