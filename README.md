<p align="center">
  <a href="https://www.jianshu.com/u/29f69849848a">
    <img width="200" src="ios/Runner/Assets.xcassets/AppIcon.appiconset/icon.png">
  </a>
</p>

<h1 align="center">视界宝</h1>
<div align="center">

一键抓取网页音视频，离线播放、后台聆听、便捷分享

</div>

![](demo/Demo.png)

# 视界宝 - 网页音视频捕获与本地媒体播放工具

视界宝是一款 Flutter 音视频下载与播放应用，支持在内置 WebView 中浏览网页、识别网页中的视频和音频资源、创建下载任务，并在本地完成播放、分享和管理。

## 核心功能

- **网页音视频提取**
  - 支持扫描页面中的 `video`、`audio`、`source` 和资源加载记录。
  - 支持目标站点详情页接口解析，识别 `attachments` 中的音频和视频。
  - 一个页面中存在多个音频时，会全部识别并分别加入下载任务。
  - 提取流程见 [docs/media_download_flow.md](docs/media_download_flow.md)。

- **音频与视频下载**
  - 视频使用 FFmpegKit 下载/合并到本地 `.mp4`，完成后生成封面。
  - 音频使用带 `Referer / Origin / Cookie / User-Agent` 的直连 HTTP 流式下载，支持 `.mp3/.m4a/.aac/.wav/.ogg/.flac`。
  - 下载任务会持久化保存，重复链接会跳过，避免重复添加。
  - 详情页点击下载后会显示提取中、识别中、添加任务中的实时反馈。

- **本地播放**
  - 支持视频播放和音频播放。
  - 音频播放页提供播放/暂停、进度条、前后 10 秒跳转。
  - 视频和音频均支持后台播放；App 退到后台或锁屏后仍可继续听声音。

- **系统分享**
  - 音频、视频、图片详情页都支持直接分享源文件。
  - Android 使用 `FileProvider` 打开系统分享弹窗。
  - iOS 使用 `UIActivityViewController` 打开系统分享弹窗。
  - 可通过系统分享组件发送到微信、保存到文件，或用其他 App 打开。

- **本地加密媒体入口**
  - 支持把加密后的本地图片、音频、视频放入 `assets/local_media/`。
  - 支持图片、音频、视频三类本地媒体解密后查看/播放/分享。
  - 本地入口默认隐藏，下载 Tab 连续点击 10 次后输入密码解锁。
  - `assets/local_media/` 已加入 `.gitignore`，请自行准备本地资源，不要提交私有媒体文件。

- **收藏与导航**
  - 支持收藏网页地址。
  - 支持侧边栏快速进入收藏页面。
  - 从侧边栏切换到其他网页时，会取消旧页面的提取中状态，避免按钮卡在上一页。

## 本地加密媒体与密码配置

本地加密媒体的访问密码在 [lib/services/local_media_service.dart](lib/services/local_media_service.dart) 中校验：

```dart
static const String unlockPasswordMd5 = '<your-password-md5>';
```

请使用者自行准备一个**原文密码**和它的 **MD5 值**：

- 原文密码只在解锁和解密时输入，不要写入 README 或提交到仓库。
- 代码中只保存原文密码的 MD5 值，用于校验输入是否正确。
- 解密媒体文件时，仍然需要输入原文密码，而不是 MD5。

示例：

- 原文密码：`1234`
- `1234` 的 MD5：`81dc9bdb52d04dc20036dbd8313ed055`
- 项目中配置：

```dart
static const String unlockPasswordMd5 = '81dc9bdb52d04dc20036dbd8313ed055';
```

- 用户解锁和解密时输入：`1234`

可用下面的命令生成 MD5：

```bash
printf '1234' | md5
```

## 本地媒体资源说明

本地加密资源目录：

```text
assets/local_media/
```

应用会读取该目录下的 `index.json` 或 Flutter 资源清单，识别 `.cpp` / `.dat` 后缀的加密文件。解密后会根据原始文件名扩展名判断媒体类型：

- 图片：`.jpg/.jpeg/.png/.webp`
- 音频：`.mp3/.m4a/.aac/.wav/.ogg/.flac`
- 视频：`.mp4`

### 加密本地媒体

项目内提供了加密脚本：

```bash
bash scripts/encrypt_local_media.sh -i /path/to/plain_media --clean
```

请用 **bash** 运行，不要用 `sh`。脚本内部使用了 Bash 语法（如 `< <(...)` 进程替换），若执行 `sh scripts/encrypt_local_media.sh ...` 会报错：

```text
scripts/encrypt_local_media.sh: line 107: syntax error near unexpected token `<'
```

以下写法均可：

```bash
bash scripts/encrypt_local_media.sh -i /path/to/plain_media --clean
./scripts/encrypt_local_media.sh -i /path/to/plain_media --clean   # 需先 chmod +x
```

脚本会：

- 扫描输入目录中的图片、音频、视频文件。
- 提示输入原文密码，并输出该密码的 MD5，方便配置 `unlockPasswordMd5`。
- 使用 OpenSSL `aes-256-cbc -a -salt -md sha256` 加密文件。
- 默认输出到 `assets/local_media/`，文件名形如 `demo.mp3.cpp`。
- 自动生成 `assets/local_media/index.json`，App 会用这个索引读取加密资源。

如果 OpenSSL 输出 `deprecated key derivation used` 提示，可以忽略；当前 App 解密逻辑就是按这个 OpenSSL Salted 格式实现的。不要自行添加 `-pbkdf2`，除非同步修改 App 端解密逻辑。

示例：

```bash
mkdir -p ~/Desktop/plain_media
cp ~/Downloads/demo.mp3 ~/Desktop/plain_media/
bash scripts/encrypt_local_media.sh -i ~/Desktop/plain_media --clean
```

如果希望在自动化环境中使用，也可以通过环境变量传入密码：

```bash
LOCAL_MEDIA_PASSWORD='1234' bash scripts/encrypt_local_media.sh -i ./plain_media --clean
```

加密完成后，确认脚本输出的 MD5 已写入 `LocalMediaService.unlockPasswordMd5`，然后重新构建 App。解锁和播放时输入的仍然是原文密码。

### 在电脑端解密查看

如果只是想在电脑上临时解密并查看这些文件，可以使用配套解密脚本：

```bash
bash scripts/decrypt_local_media.sh -i assets/local_media -o ~/Desktop/decrypted_media --clean
```

同样请用 **bash** 运行，不要用 `sh`（原因同上）。

脚本会：

- 扫描输入目录中的 `.cpp/.dat` 加密文件。
- 提示输入原文密码，并打印该密码的 MD5 供核对。
- 默认兼容 `sha256` 和旧版 `md5` 两种 OpenSSL 派生方式。
- 把 `demo.mp3.cpp` 解密还原为 `demo.mp3`，输出到指定目录。

自动化用法：

```bash
LOCAL_MEDIA_PASSWORD='1234' bash scripts/decrypt_local_media.sh -o ./decrypted_media --clean
```

这里同样要输入原文密码，不是 MD5。解密后的文件是明文媒体文件，请不要提交到仓库。

## 项目结构

```text
lib/
├── config/          # 配置相关
├── controllers/     # GetX 控制器
├── models/          # 下载任务、本地媒体等数据模型
├── pages/           # 网页详情、下载列表、播放页、本地媒体页等
├── routes/          # 路由管理
├── services/        # 下载、提取、分享、本地媒体解密等服务
├── utils/           # 工具类函数
└── widgets/         # 复用组件
```

## 主要依赖

- `flutter_inappwebview`：内置 WebView 和 Cookie 获取。
- `ffmpeg_kit_flutter_new`：视频下载、合并和封面生成。
- `video_player` / `chewie`：音视频播放。
- `get` / `get_storage`：路由、状态管理和本地持久化。
- `crypto` / `pointycastle`：密码 MD5 校验和本地加密媒体解密。

## 验证

常用检查命令：

```bash
dart format lib test
flutter test
flutter analyze
```

当前 Android Gradle 环境如果使用 Java 21，旧版 Gradle 可能会出现 `Unsupported class file major version 65`，需要切换到兼容的 JDK 或升级 Gradle 后再进行 Android 原生编译验证。

## 后续规划

- 增加锁屏媒体控制和通知栏播放控制。
- 优化下载列表中的任务状态展示。
- 扩展更多音视频站点的解析兼容性。

欢迎使用与反馈。
