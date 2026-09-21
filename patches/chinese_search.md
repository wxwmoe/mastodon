# 中文全文搜索

`chinese_search` 调整 Elasticsearch 分词配置，支持中文分词和繁简转换

需在 Elasticsearch 安装与其版本对应的 [IK](https://github.com/infinilabs/analysis-ik) 和 [STConvert](https://github.com/infinilabs/analysis-stconvert) 插件

启用、停用模块或变更分词配置后，使用目标镜像重建索引：

```bash
docker compose run --rm web bin/tootctl search deploy
```

索引不会随 Mastodon 镜像切换自动更新。切回原版分词时，先用原版镜像重建索引，再按需移除 Elasticsearch 插件
