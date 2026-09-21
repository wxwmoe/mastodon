# Streaming 媒体地址映射

`streaming_media_hosts` 根据 WebSocket 请求的 Host，替换 Streaming 消息中的媒体地址，用于通过不同媒体域名访问的镜像站

在 Docker Compose 的 streaming 服务设置可选变量：

```yaml
services:
  streaming:
    environment:
      STREAMING_MEDIA_HOSTS: >-
        {
          "wss.example.net": {"s3.example.com": "s3.example.net", "cache.example.com": "cache.example.net"},
          "wss.example.org": {"s3.example.com": "s3.example.org", "cache.example.com": "cache.example.org"}
        }
```

- 外层键为 WebSocket 请求域名，内层为该站点的「原媒体地址 → 目标媒体地址」替换列表
- 请求域名忽略大小写和端口；配置中的请求域名不包含端口
- 未配置、变量为空、替换列表为空或请求 Host 未匹配时，消息保持原样；列表中未配置的来源保持原地址
- 变量须为有效 JSON 对象，格式错误会阻止 Streaming 启动；不兼容旧的 `source` / `hosts` 结构

替换作用于整个 Streaming 消息文本，按字面匹配原地址，较长来源优先；一次完成替换，生成的地址不会再次匹配。REST API 返回的 URL 不受影响
