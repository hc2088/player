import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:chewie/chewie.dart';

import '../models/download_task.dart';
import '../services/file_share_service.dart';
import '../services/playback_service.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final PlaybackService _playback = Get.find<PlaybackService>();

  ChewieController? _chewieController;
  bool _shouldAutoPlayVideo = false;

  bool _checked = false;
  String _title = '视频';
  String? _filePath;
  DownloadMediaType _mediaType = DownloadMediaType.video;
  bool? _lastStatusBarDarkBackground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final args = Get.arguments;
    String? path;

    if (args is String) {
      path = args;
    } else if (args is Map) {
      path = args['path'] as String?;
      _title = (args['title'] as String?) ?? _title;
      _mediaType = PlaybackService.mediaTypeFromArgument(args['mediaType']);
    }

    if (path == null || path.isEmpty) {
      if (!mounted) return;
      setState(() => _checked = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.snackbar('错误', '无效的文件路径参数');
      });
      return;
    }

    if (args is String) {
      _mediaType = PlaybackService.inferMediaType(path);
    }
    if (_mediaType == DownloadMediaType.audio && _title == '视频') {
      _title = '音频';
    }
    _filePath = path;

    final sessionReused = _playback.isSameSession(path);
    if (!sessionReused) {
      await _playback.open(
        path: path,
        title: _title,
        mediaType: _mediaType,
      );
    } else {
      _title = _playback.title.value;
      _mediaType = _playback.mediaType.value;
    }
    _shouldAutoPlayVideo =
        _mediaType == DownloadMediaType.video && !sessionReused;

    if (!mounted) return;

    setState(() {
      _checked = true;
      _syncFromService();
    });

    if (_playback.playbackError.value != null) {
      return;
    }

    if (sessionReused && _mediaType == DownloadMediaType.video) {
      _chewieController?.dispose();
      _chewieController = null;
    }
    await _initVideoUi();
    if (!mounted) return;

    _playback.attachPage(_onPlaybackUpdated);
  }

  Future<void> _initVideoUi() async {
    final controller = _playback.controller;
    if (_mediaType != DownloadMediaType.video ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    await _ensureChewieController();
  }

  void _onPlaybackUpdated() {
    if (!mounted) return;

    if (_isUserPoppingGesture) return;

    if (_mediaType == DownloadMediaType.video && _chewieController == null) {
      _initVideoUi();
    }

    _safeSetState(_syncFromService);
    _updateStatusBar(isDarkBackground: true);
  }

  void _syncFromService() {
    _title = _playback.title.value;
    _mediaType = _playback.mediaType.value;
  }

  Future<void> _ensureChewieController() async {
    final controller = _playback.controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_chewieController != null) return;

    final wasPlaying = controller.value.isPlaying;
    _chewieController = ChewieController(
      videoPlayerController: controller,
      aspectRatio: controller.value.aspectRatio,
      autoPlay: _shouldAutoPlayVideo || wasPlaying,
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

    if (_shouldAutoPlayVideo && !wasPlaying) {
      await controller.play();
    } else if (wasPlaying) {
      // Reattaching Chewie to a playing controller: refresh the video surface.
      await controller.pause();
      await controller.play();
    }

    if (mounted) {
      _safeSetState(() {});
    }
  }

  void _safeSetState(VoidCallback update) {
    if (!mounted) return;

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(update);
      });
      return;
    }

    setState(update);
  }

  bool get _isUserPoppingGesture {
    return ModalRoute.of(context)?.navigator?.userGestureInProgress ?? false;
  }

  void _updateStatusBar({required bool isDarkBackground}) {
    if (_lastStatusBarDarkBackground == isDarkBackground) return;
    _lastStatusBarDarkBackground = isDarkBackground;

    final brightness = isDarkBackground ? Brightness.light : Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: isDarkBackground ? Colors.black : Colors.white,
      statusBarIconBrightness: brightness,
      statusBarBrightness:
          isDarkBackground ? Brightness.dark : Brightness.light,
    ));
  }

  void _handlePop() {
    _chewieController?.dispose();
    _chewieController = null;
    _playback.detachPage();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _chewieController = null;
    _playback.detachPage();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  Future<void> _togglePlay() async {
    await _playback.toggle();
    if (!mounted) return;
    setState(_syncFromService);
    _updateStatusBar(isDarkBackground: true);
  }

  Future<void> _seekTo(Duration position) async {
    await _playback.seekTo(position);
  }

  Future<void> _seekBy(Duration offset) async {
    await _playback.seekBy(offset);
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _stopPlayback() async {
    await _playback.stop();
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Get.back();
    }
  }

  Future<void> _shareCurrentFile() async {
    final path = _filePath ?? _playback.filePath;
    if (path == null || path.isEmpty) return;

    try {
      await FileShareService.shareFile(path, title: _title);
    } catch (e) {
      Get.snackbar('分享失败', e.toString());
    }
  }

  Widget _buildAudioPlayer() {
    return Obx(() {
      final isPlaying = _playback.isPlaying.value;
      final position = _playback.position.value;
      final duration = _playback.duration.value;
      final durationMs = duration.inMilliseconds;
      final positionMs =
          position.inMilliseconds.clamp(0, durationMs == 0 ? 0 : durationMs);

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
                  _formatDuration(position),
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  _formatDuration(duration),
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
    });
  }

  Widget _buildBody() {
    if (!_checked) {
      return const Center(child: CircularProgressIndicator());
    }

    final playbackError = _playback.playbackError.value;
    if (playbackError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            playbackError,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.red),
          ),
        ),
      );
    }

    final playbackController = _playback.controller;
    final initialized = _playback.isInitialized.value ||
        (playbackController?.value.isInitialized ?? false);

    if (!initialized) {
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
    final canShare = _filePath != null && _playback.playbackError.value == null;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _handlePop();
        }
      },
      child: Scaffold(
        appBar: !isAudio
            ? null
            : AppBar(
                title: Text(_title),
                actions: [
                  IconButton(
                    tooltip: '停止',
                    onPressed: _stopPlayback,
                    icon: const Icon(Icons.stop),
                  ),
                  IconButton(
                    tooltip: '分享',
                    onPressed: canShare ? _shareCurrentFile : null,
                    icon: const Icon(Icons.share),
                  ),
                ],
              ),
        backgroundColor: Colors.black,
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
      ),
    );
  }
}
