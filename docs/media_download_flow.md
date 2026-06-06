# Media Download Flow

```mermaid
flowchart TD
  A["用户点击提取媒体"] --> B["获取当前页面 URL 和标题"]
  B --> C["扫描 DOM 中的 video/audio/source"]
  B --> D{"URL 是否为 /post/details?pid=..."}
  D -->|"否"| I["合并并去重媒体地址"]
  D -->|"是"| E["请求同源 /api/topic/{pid}，携带 WebView Cookie"]
  E --> F{"响应 isEncrypted?"}
  F -->|"是"| G["Base64 连续解码 3 次，再 JSON.parse"]
  F -->|"否"| H["读取 data 字段"]
  G --> J["遍历 attachments"]
  H --> J
  J --> K{"category"}
  K -->|"audio"| L["读取 remoteUrl 作为 mp3 下载地址"]
  K -->|"video"| M{"remoteUrl 是否为空"}
  M -->|"否"| N["使用 remoteUrl 作为视频源"]
  M -->|"是"| O["请求 /api/topic/att/{attachmentId}"]
  O --> P["解码线路列表，选择非空 url"]
  L --> I
  N --> I
  P --> I
  I --> Q{"是否找到媒体"}
  Q -->|"否"| R["提示未找到可下载音频或视频"]
  Q -->|"是"| S["按 audio/video 创建下载任务"]
  S --> T{"媒体类型"}
  T -->|"audio"| U["输出 .mp3，不生成封面"]
  T -->|"video"| V["FFmpeg 复制/合并到 .mp4，完成后生成封面"]
```

Notes:

- Audio normally comes from `attachments[].remoteUrl` and is a direct file URL.
- Video may come from `attachments[].remoteUrl`, or from `/api/topic/att/{id}` when the topic detail only has an empty `remoteUrl`.
- If every video line returns an empty `url`, the app cannot download it because the site did not provide a playable source for the current login state.
