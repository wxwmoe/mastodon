# Streaming 媒体地址映射

`streaming_media_hosts` 根据 WebSocket 请求的 Host，替换 Streaming 消息中的媒体地址，用于通过不同媒体域名访问的镜像站

在 Docker Compose 的 streaming 服务设置可选变量：

```yaml
services:
  streaming:
    environment:
      STREAMING_MEDIA_HOSTS: >-
        {"source":["s3.example.com"],"hosts":{"wss.example.net":"s3.example.net"}}
```

- `source`：需要替换的原地址，可以指定多个
- `hosts`：WebSocket 请求域名到目标地址的映射，键使用小写域名，不包含端口
- 未配置、变量为空或请求 Host 未匹配时，消息保持原样，变量须为有效 JSON

替换作用于整个 Streaming 消息文本，REST API 返回的 URL 不受影响
