import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../models/download_task.dart';
import '../services/file_share_service.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  bool _isFileExists = false;
  bool _checked = false;
  bool _isInitialized = false;
  String _title = '视频';
  String? _filePath;
  String? _playbackError;
  DownloadMediaType _mediaType = DownloadMediaType.video;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime _lastAudioProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool? _lastStatusBarDarkBackground;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    String? path;
    if (args is String) {
      path = args;
    } else if (args is Map) {
      path = args['path'] as String?;
      _title = (args['title'] as String?) ?? _title;
      _mediaType = _mediaTypeFromArgument(args['mediaType']);
    }

    if (path == null || path.isEmpty) {
      _checked = true;
      _isFileExists = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.snackbar('错误', '无效的文件路径参数');
      });
      return;
    }

    if (args is String) {
      _mediaType = _inferMediaType(path);
    }
    if (_mediaType == DownloadMediaType.audio && _title == '视频') {
      _title = '音频';
    }
    _filePath = path;

    final file = File(path);

    file.exists().then((exists) async {
      if (!mounted) return;

      setState(() {
        _isFileExists = exists;
        _checked = true;
      });

      if (!exists) {
        Get.snackbar('错误', '文件不存在：$path');
        return;
      }

      final videoPlayerController = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: true,
        ),
      );
      _videoPlayerController = videoPlayerController;

      // 监听播放状态变化，同步状态栏文字颜色
      videoPlayerController.addListener(_videoPlayerListener);

      try {
        await videoPlayerController.initialize();
        if (!mounted) return;

        _duration = videoPlayerController.value.duration;
        _position = videoPlayerController.value.position;

        if (_mediaType == DownloadMediaType.audio) {
          await videoPlayerController.play();
        }

        setState(() {
          _isInitialized = true;
          if (_mediaType == DownloadMediaType.video) {
            _chewieController = ChewieController(
              videoPlayerController: videoPlayerController,
              aspectRatio: videoPlayerController.value.aspectRatio,
              autoPlay: true,
              looping: false,
              allowFullScreen: true,
              allowPlaybackSpeedChanging: true,
              deviceOrientationsOnEnterFullScreen: const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
              deviceOrientationsAfterFullScreen: const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
            );
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _playbackError = '媒体初始化失败：$e';
        });
        Get.snackbar('播放失败', _playbackError!);
      }
    });
  }

  DownloadMediaType _mediaTypeFromArgument(Object? value) {
    if (value is DownloadMediaType) return value;
    if (value?.toString().toLowerCase() == 'audio') {
      return DownloadMediaType.audio;
    }
    return DownloadMediaType.video;
  }

  DownloadMediaType _inferMediaType(String path) {
    final lower = path.toLowerCase();
    const audioExtensions = ['.mp3', '.m4a', '.aac', '.wav', '.ogg', '.flac'];
    return audioExtensions.any(lower.endsWith)
        ? DownloadMediaType.audio
        : DownloadMediaType.video;
  }

  bool get _isUserPoppingGesture {
    return ModalRoute.of(context)?.navigator?.userGestureInProgress ?? false;
  }

  void _videoPlayerListener() {
    final videoPlayerController = _videoPlayerController;
    if (videoPlayerController == null ||
        !videoPlayerController.value.isInitialized) {
      return;
    }

    // 正在侧滑返回手势中，暂时不更新状态栏
    if (_isUserPoppingGesture) return;

    if (_mediaType == DownloadMediaType.audio && mounted) {
      final now = DateTime.now();
      if (now.difference(_lastAudioProgressUpdate).inMilliseconds < 300) {
        return;
      }
      _lastAudioProgressUpdate = now;

      final value = videoPlayerController.value;
      setState(() {
        _position = value.position;
        _duration = value.duration;
      });
    }

    // 例如：播放时保持黑底白字，暂停时可以调整
    if (videoPlayerController.value.isPlaying) {
      _updateStatusBar(isDarkBackground: true);
    } else {
      // 你也可以根据需求改变，这里示例为播放暂停都保持黑底白字
      _updateStatusBar(isDarkBackground: true);
    }
  }

  void _updateStatusBar({required bool isDarkBackground}) {
    if (_lastStatusBarDarkBackground == isDarkBackground) return;
    _lastStatusBarDarkBackground = isDarkBackground;

    final brightness = isDarkBackground ? Brightness.light : Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: isDarkBackground ? Colors.black : Colors.white,
      statusBarIconBrightness: brightness,
      statusBarBrightness:
          isDarkBackground ? Brightness.dark : Brightness.light, // iOS
    ));
  }

  @override
  void dispose() {
    _videoPlayerController?.removeListener(_videoPlayerListener);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();

    // 恢复默认状态栏风格（可根据需求调整）
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    super.dispose();
  }

  Future<void> _togglePlay() async {
    final controller = _videoPlayerController;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (!mounted) return;
    final value = controller.value;
    setState(() {
      _position = value.position;
      _duration = value.duration;
    });
    _updateStatusBar(isDarkBackground: true);
  }

  Future<void> _seekTo(Duration position) async {
    final controller = _videoPlayerController;
    if (controller == null || !controller.value.isInitialized) return;

    await controller.seekTo(position);
    if (!mounted) return;
    final value = controller.value;
    setState(() {
      _position = value.position;
      _duration = value.duration;
      _lastAudioProgressUpdate = DateTime.now();
    });
  }

  Future<void> _seekBy(Duration offset) async {
    final controller = _videoPlayerController;
    if (controller == null || !controller.value.isInitialized) return;

    final target = controller.value.position + offset;
    final duration = controller.value.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > duration
            ? duration
            : target;
    await _seekTo(clamped);
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _shareCurrentFile() async {
    final path = _filePath;
    if (path == null || path.isEmpty) return;

    try {
      await FileShareService.shareFile(path, title: _title);
    } catch (e) {
      Get.snackbar('分享失败', e.toString());
    }
  }

  Widget _buildAudioPlayer() {
    final controller = _videoPlayerController;
    final isPlaying = controller?.value.isPlaying ?? false;
    final durationMs = _duration.inMilliseconds;
    final positionMs =
        _position.inMilliseconds.clamp(0, durationMs == 0 ? 0 : durationMs);

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.audiotrack,
            color: Colors.white70,
            size: 84,
          ),
          const SizedBox(height: 24),
          Text(
            _title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          Slider(
            min: 0,
            max: durationMs <= 0 ? 1 : durationMs.toDouble(),
            value: durationMs <= 0 ? 0 : positionMs.toDouble(),
            onChanged: durationMs <= 0
                ? null
                : (value) {
                    _seekTo(Duration(milliseconds: value.round()));
                  },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: () => _seekBy(const Duration(seconds: -10)),
                icon: const Icon(Icons.replay_10),
                iconSize: 32,
              ),
              const SizedBox(width: 24),
              IconButton.filled(
                onPressed: _togglePlay,
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                iconSize: 42,
              ),
              const SizedBox(width: 24),
              IconButton.filledTonal(
                onPressed: () => _seekBy(const Duration(seconds: 10)),
                icon: const Icon(Icons.forward_10),
                iconSize: 32,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_checked) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isFileExists) {
      return const Center(
        child: Text(
          '文件不存在，无法播放',
          style: TextStyle(fontSize: 16, color: Colors.red),
        ),
      );
    }

    if (_playbackError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _playbackError!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.red),
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_mediaType == DownloadMediaType.audio) {
      return _buildAudioPlayer();
    }

    return _chewieController != null
        ? Chewie(controller: _chewieController!)
        : const Center(child: CircularProgressIndicator());
  }

  @override
  Widget build(BuildContext context) {
    final isAudio = _mediaType == DownloadMediaType.audio;
    final canShare = _isFileExists && _filePath != null;
    return Scaffold(
      appBar: _isFileExists && !isAudio
          ? null
          : AppBar(
              title: Text(_title),
              actions: [
                IconButton(
                  tooltip: '分享',
                  onPressed: canShare ? _shareCurrentFile : null,
                  icon: const Icon(Icons.share),
                ),
              ],
            ),
      backgroundColor: _isFileExists ? Colors.black : Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            _buildBody(),
            if (canShare && !isAudio)
              Positioned(
                top: 12,
                right: 12,
                child: IconButton.filledTonal(
                  tooltip: '分享',
                  onPressed: _shareCurrentFile,
                  icon: const Icon(Icons.share),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
