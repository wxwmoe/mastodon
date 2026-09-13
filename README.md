# mastodon

Mastodon patches used on wxw.moe.

## 特性

- 模块化构建，按需启用补丁
- 停用无需回滚迁移，`wxw_*` 扩展表仅闲置，不影响原版镜像运行

## 模块说明

按构建顺序排列

| 模块 | 作用 | 依赖 |
| --- | --- | --- |
| [replace_icons](patches/replace_icons.sh) | 定制实例图标与 Logo 素材 | — |
| [status_limit](patches/status_limit.sh) | 嘟文上限：500 → 20,000 字符 | — |
| [status_regexp_timeout](patches/status_regexp_timeout.sh) | Ruby 正则超时 1 → 3 秒，并兜底超时 | — |
| [status_reply_autosuggest](patches/status_reply_autosuggest.sh) | 停用编辑框空格后的提及、标签联想 | — |
| [status_poll_limit](patches/status_poll_limit.sh) | 投票选项上限：4 → 16 | — |
| [media_limits](patches/media_limits.sh) | 提升限制至 16 个附件、图片 99 MiB；外站接收的头像/封面 16 MiB、表情 2 MiB | — |
| [install_themes](patches/install_themes.sh) | 安装 Bird UI、Tangerine Neue 和桜主题及爪印图标 | [Mastodon Bird UI][4]、[Tangerine Neue][5] |
| [custom_emoji_preview](patches/custom_emoji_preview.sh) | 表情焦点、触摸放大，标签选择器加大 | — |
| [custom_emoji_packs](patches/custom_emoji_packs.sh) | 表情包选单、表情收藏 | 数据库前置迁移 |
| [status_settings](patches/status_settings.sh) | 嘟文标记扩展，存放各类额外参数 | 数据库前置迁移 |
| [status_highlight](patches/status_highlight.sh) | 富文本嘟文代码高亮 | [Shiki][7] |
| [status_rich_text](patches/status_rich_text.sh) | 支持富文本嘟文的编辑和联邦互操作 | `status_settings`；[Commonmarker][8]；数据库前置迁移 |
| [status_remote_visibility](patches/status_remote_visibility.sh) | 增加外站可见性和联邦互操作 | `status_settings`；数据库前置迁移 |
| [streaming_media_hosts](patches/streaming_media_hosts.sh) | 按请求来源 Host 替换 Streaming 消息中的媒体文件地址，用于镜像站 | 可选 `STREAMING_MEDIA_HOSTS` 变量 |
| [registration_reason_dedup](patches/registration_reason_dedup.sh) | 拒绝与待审核申请完全相同的注册理由 | — |
| [navigation_entry](patches/navigation_entry.sh) | 替换当前热门为本地时间线，并使用喵爪图标 | `install_themes` 提供的 `paw.svg` |
| [rate_limit_tiers](patches/rate_limit_tiers.sh) | 按用户注册年限逐年放宽请求速率，方便用户管理历史嘟文 | — |
| [chinese_search](patches/chinese_search.sh) | 全文搜索的中文分词和繁简转换 | Elasticsearch [IK][10]、[STConvert][11]；重建全文搜索索引 |
| [set_version_metadata](patches/set_version_metadata.sh) | 设置源码仓库地址，修改版本后缀为 `~wxw` | — |

### 模块选择

编辑 `build.sh` 的 `WXW.MOE_MASTODON_PATCHES` 列表：

```
status_settings                               # 安装嘟文扩展
#status_highlight                             # 支持代码高亮
status_rich_text                              # 支持富文本嘟文
```

**禁用前置模块时应同时禁用依赖它的模块**

模块禁用不会删除扩展数据，相关影响见[切回原版镜像](#切回原版镜像)

## 使用

### 构建

Debian 13 示例：

```bash
apt update
apt install -y git wget ca-certificates patch docker.io docker-cli docker-buildx docker-compose
systemctl enable --now docker
```

拉取本仓库并构建：

```bash
git clone https://github.com/wxwmoe/mastodon.git
cd mastodon && bash build.sh
```

| 命令 | 行为 |
| --- | --- |
| `bash build.sh` | 下载源码、应用补丁，并构建镜像 |
| `bash build.sh --check` | 不构建镜像，用于源码检查 |
| `bash build.sh --no-cache` | 禁用编译缓存的完整构建 |

构建镜像标签随 `MASTODON_VERSION` 变化，同时生成 `latest` 标签：

| 用途 | 镜像标签 |
| --- | --- |
| Web / Sidekiq | `wxwmoe/mastodon:latest`, `wxwmoe/mastodon:v${MASTODON_VERSION}` |
| Streaming | `wxwmoe/mastodon-streaming:latest`, `wxwmoe/mastodon-streaming:v${MASTODON_VERSION}` |

后续更新或调整模块：

**跨上游版本的升级还需核对目标版本的迁移要求**

更新本仓库、核对版本与模块选择，重新构建，再按需执行[迁移与切换](#迁移与切换)流程

### 运行配置

修改 Docker Compose 配置：

```yaml
services:
  web:
    image: wxwmoe/mastodon
    pull_policy: never

  sidekiq:
    image: wxwmoe/mastodon
    pull_policy: never

  streaming:
    image: wxwmoe/mastodon-streaming
    pull_policy: never
    environment:
      STREAMING_MEDIA_HOSTS: >-
        {"source":["s3.example.com"],"hosts":{"wss.example.net":"s3.example.net"}}
```

`STREAMING_MEDIA_HOSTS` 可选，无需映射时删除此变量：

`source` 为需要替换的原地址，`hosts` 为 WebSocket 请求域名到目标地址的映射

使用 `chinese_search` 时，在 Elasticsearch 安装对应版本的 [IK][10]、[STConvert][11]

分词配置变更后，需要用目标镜像重建索引：

```bash
docker compose run --rm web bin/tootctl search deploy
```

### 迁移与切换

在生产环境 Docker Compose 目录执行

> 操作前备份数据库、媒体及环境配置；构建脚本不执行迁移

#### 前置迁移（按需执行）

启用相关模块时，在切换服务前执行：

```bash
docker compose run --rm -e SKIP_POST_DEPLOYMENT_MIGRATIONS=true web bundle exec rails db:migrate
```

随后切换服务到新镜像：

```bash
docker compose up -d
```

#### 后置迁移（按需执行）

在服务切换并确认相关功能正常后执行：

```bash
docker compose run --rm web bundle exec rails db:migrate
```

完整示例

```bash
docker compose run --rm -e SKIP_POST_DEPLOYMENT_MIGRATIONS=true web bundle exec rails db:migrate
docker compose up -d
docker compose run --rm web bundle exec rails db:migrate    # ← 执行后置迁移
```

#### 切换清理（按需执行）

前置迁移成功后切换服务，随后执行清理：

```bash
docker compose run --rm web bin/tootctl cache clear
```

> 变更模块或切换官方/定制镜像时，建议清除应用缓存

Docker 重建不会清除共享 Redis 缓存，普通更新无需每次清理

### 切回原版镜像

支持切回**相同上游版本**，不等同于数据库降级

> 原版不读取 `wxw_*` 扩展表，闲置表不影响运行，无需删除或回滚迁移

替换 Docker Compose 镜像并移除 `pull_policy: never`：

| 服务 | 原版镜像仓库 |
| --- | --- |
| `web`、`sidekiq` | `ghcr.io/mastodon/mastodon` |
| `streaming` | `ghcr.io/mastodon/mastodon-streaming` |

> 注意核对使用版本并指定上游镜像的版本标签

```bash
docker compose pull web streaming
docker compose up -d
```

缓存清理见[切换清理](#切换清理按需执行)

| 功能 | 切回原版后的影响 |
| --- | --- |
| 富文本与高亮 | 本地富文本嘟文按源码显示；官方镜像编辑不更新扩展格式标记，新编辑历史缺少格式，重新启用时可能解析错误，需核对正文与格式 |
| 外站可见性 | **外站限制失效，仅按嘟文的本站可见性处理**；读取、转发、引用及投递范围可能扩大，切换前核对嘟文可见性 |
| 表情包与收藏 | 表情保留；表情包分组、排序、收藏和预览停用 |
| 字数、投票与媒体 | 恢复官方限制；超限内容的展示、编辑可能受限 |
| 定时发布 | 超限等校验失败可能导致定时稿丢失，切换前检查、转换或导出待发布任务 |
| 超限附件编辑 | 在原版网页编辑超过 4 个附件的嘟文，会将附件顺序写为前 4 个，编辑后附件保留但重新启用模块不会恢复展示 |
| 主题与外观 | 不可用的主题会回退至有效站点主题或原版默认主题 |
| 请求控制与媒体地址 | 恢复原版限速、注册校验；停止替换 Streaming 媒体地址 |
| 中文搜索 | 已有索引不随镜像切换；恢复原版分词需重建索引，再按需移除插件 |

关闭对应模块时，也需核对上述影响

### 目录结构

| 路径 | 内容 |
| --- | --- |
| [build.sh](build.sh) | 镜像构建入口 |
| [patches/](patches/) | 模块安装脚本和集成补丁 |
| [overlay/](overlay/) | 模块依赖的各类相关文件 |
| `src/` | 生成的最终源码，不纳入版本控制 |

## 版权声明

> (> ʌ <) 都看到这了，点个 Star 吧 ~

基准源码

- [mastodon / AGPL-3.0][1]

互操作参考

- [mastodon-glitch / AGPL-3.0][2]
- [misskey / AGPL-3.0][3]

实例主题

- [Mastodon Bird UI / MIT][4] — Mastodon Bird UI
- [Tangerine Neue / MIT][5] — Tangerine UI
- [NIPPON COLORS][6] — 桜主题配色参考

相关依赖

- [Shiki / MIT][7] — 代码高亮
- [Commonmarker / MIT][8] — Markdown 解析与渲染
- [Elasticsearch Analysis IK / Apache-2.0][10] — 全文搜索中文分词
- [Elasticsearch Analysis STConvert / Apache-2.0][11] — 全文搜索繁简转换

###### 引用的项目、主题与相关依赖保留各自的版权及许可证

AGPL-3.0 © wxw.moe

  [1]: https://github.com/mastodon/mastodon
  [2]: https://github.com/glitch-soc/mastodon
  [3]: https://github.com/misskey-dev/misskey
  [4]: https://github.com/rollecode/mastodon-bird-ui
  [5]: https://github.com/mattbirchler/Tangerine-Neue-for-Mastodon
  [6]: https://nipponcolors.com
  [7]: https://github.com/shikijs/shiki
  [8]: https://github.com/gjtorikian/commonmarker
  [10]: https://github.com/infinilabs/analysis-ik
  [11]: https://github.com/infinilabs/analysis-stconvert
