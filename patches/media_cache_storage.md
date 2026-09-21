# 独立缓存 S3

`media_cache_storage` 将远程附件、头像、横幅、表情及链接预览图片存入独立 S3，本站媒体仍使用主存储

启用后仅影响新文件，旧文件需手动迁移

## 配置

> 主存储须已启用 S3

完成数据库迁移、创建缓存桶后，为 web、Sidekiq 和 tootctl 配置相同的环境变量：

```dotenv
CACHE_S3_ENABLED=true
CACHE_S3_BUCKET=remote-media
CACHE_S3_ENDPOINT=https://s3-cache.example.com
CACHE_S3_REGION=us-east-1
CACHE_AWS_ACCESS_KEY_ID=...
CACHE_AWS_SECRET_ACCESS_KEY=...
CACHE_S3_ALIAS_HOST=cache.example.com
```

- 缓存桶和凭据必须单独设置；其他 S3 参数按需配置对应的 `CACHE_S3_*` 变量，不继承主存储配置
- `CACHE_S3_ENABLED=false` 只停止新文件写入缓存；已有缓存文件仍需保留完整配置

## 迁移

```sh
bin/tootctl media migrate-storage --to cache --dry-run
bin/tootctl media migrate-storage --to cache
bin/tootctl cache clear
```

- `--type attachments|accounts|emojis|previews`：按类型筛选，默认全部迁移
- `--start-after ID`：从指定记录之后开始，须同时指定 `--type`
- `--concurrency N`：并发数，默认 5；`--retries N`：重试次数，默认 2，范围 0–10
- 失败后重跑原命令即可，已完成的文件会跳过；容器需预留足够的临时磁盘空间

源存储启用 ACL 时，凭据须允许 `s3:GetObjectAcl`
源存储禁用 ACL、目标启用 ACL 时，须用 `--source-permission public-read|private` 指定源文件权限
私有文件不能迁往禁用 ACL 的存储桶

## 清理

迁移保留源文件。确认旧地址不再使用后，从迁出后端清理副本

副本会随附件一并收回权限或删除；禁用 ACL 的副本在收回权限时删除

以下示例适用于迁往 cache 后清理 main：

```sh
bin/tootctl media remove-orphans --storage main --remove-migrated --days 7 --dry-run
bin/tootctl media remove-orphans --storage main --remove-migrated --days 7
```

- `--storage main|cache|all`：指定后端，默认 `all`
- `--remove-migrated`：清除迁移副本；未指定时保留这些副本
- `--days N`：只清理超过指定天数的对象，默认 7；按对象年龄计算，非迁移后的等待时间
- `--start-after`：完整 S3 key，须用 `--storage` 指定单个后端

## 停用

先设置 `CACHE_S3_ENABLED=false` 并重启 web、Sidekiq，再执行：

```sh
bin/tootctl media migrate-storage --to main
bin/tootctl cache clear
bin/tootctl media remove-orphans --storage cache --remove-migrated --days 0 --dry-run
bin/tootctl media remove-orphans --storage cache --remove-migrated --days 0
```

确认 `wxw_media_caches` 无记录、cache 副本已清理、相关 Sidekiq 清理任务完成后，再移除模块和缓存配置或切回原版镜像
