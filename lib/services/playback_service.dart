import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../models/download_task.dart';
import '../routes/route_helper.dart';

class PlaybackService extends GetxService {
  final hasSession = false.obs;
  final showMiniPlayer = false.obs;
  final isPageAttached = false.obs;
  final isPlaying = false.obs;
  final position = Duration.zero.obs;
  final duration = Duration.zero.obs;
  final title = '视频'.obs;
  final mediaType = DownloadMediaType.video.obs;
  final isInitialized = false.obs;
  final playbackError = RxnString();

  VideoPlayerController? _controller;
  String? _filePath;
  VoidCallback? _pageListener;
  int _pageAttachmentToken = 0;

  VideoPlayerController? get controller => _controller;
  String? get filePath => _filePath;

  bool isSameSession(String path) =>
      _filePath == path &&
      _controller != null &&
      _controller!.value.isInitialized;

  Future<void> open({
    required String path,
    required String title,
    required DownloadMediaType mediaType,
  }) async {
    if (isSameSession(path)) {
      this.title.value = title;
      this.mediaType.value = mediaType;
      playbackError.value = null;
      return;
    }

    _pageAttachmentToken++;
    await stop(silent: true);

    final file = File(path);
    if (!await file.exists()) {
      playbackError.value = '文件不存在：$path';
      Get.snackbar('错误', playbackError.value!);
      return;
    }

    _filePath = path;
    this.title.value = title;
    this.mediaType.value = mediaType;
    playbackError.value = null;
    hasSession.value = true;
    showMiniPlayer.value = false;
    isInitialized.value = false;

    final videoPlayerController = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(
        allowBackgroundPlayback: true,
      ),
    );
    _controller = videoPlayerController;
    videoPlayerController.addListener(_controllerListener);

    try {
      await videoPlayerController.initialize();
      _syncFromController();
      isInitialized.value = true;

      if (mediaType == DownloadMediaType.audio) {
        await videoPlayerController.play();
        _syncFromController();
      }
    } catch (e) {
      playbackError.value = '媒体初始化失败：$e';
      Get.snackbar('播放失败', playbackError.value!);
      await stop(silent: true);
    }
  }

  void attachPage(VoidCallback onControllerUpdate) {
    final token = ++_pageAttachmentToken;
    _pageListener = onControllerUpdate;

    _scheduleUiState(() {
      if (token != _pageAttachmentToken) return;

      isPageAttached.value = true;
      showMiniPlayer.value = false;
      _syncFromController();
      onControllerUpdate();
    });
  }

  void detachPage() {
    final token = ++_pageAttachmentToken;
    _pageListener = null;
    final shouldShowMiniPlayer = _controller != null && hasSession.value;

    _scheduleUiState(() {
      if (token != _pageAttachmentToken) return;

      isPageAttached.value = false;

      if (shouldShowMiniPlayer) {
        showMiniPlayer.value = true;
      }
      _syncFromController();
    });
  }

  /// 全屏页（VideoPlayerPage / VideoSwiperPage）接管已有控制器，不 dispose。
  VideoPlayerController? claimControllerForPath(String path) {
    if (!isSameSession(path)) return null;

    final controller = _controller;
    if (controller == null) return null;

    controller.removeListener(_controllerListener);
    _controller = null;
    _filePath = null;
    _pageListener = null;

    _scheduleUiState(() {
      hasSession.value = false;
      showMiniPlayer.value = false;
      isPlaying.value = false;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      isInitialized.value = false;
    });

    return controller;
  }

  /// 竖滑页 / 全屏页返回时，将当前控制器交给全局会话并显示迷你条。
  Future<void> receiveFromPageLeave({
    required VideoPlayerController controller,
    required String path,
    required String title,
    required DownloadMediaType mediaType,
  }) async {
    if (_controller != null && _controller != controller) {
      await stop(silent: true);
    }

    final token = ++_pageAttachmentToken;
    _controller = controller;
    _filePath = path;
    _pageListener = null;

    controller.removeListener(_controllerListener);
    controller.addListener(_controllerListener);

    _scheduleUiState(() {
      if (token != _pageAttachmentToken) return;

      this.title.value = title;
      this.mediaType.value = mediaType;
      playbackError.value = null;
      hasSession.value = true;
      isInitialized.value = controller.value.isInitialized;
      isPageAttached.value = false;
      showMiniPlayer.value = true;
      _syncFromController();
    });
  }

  void updateSessionFile({
    required String oldPath,
    required String newPath,
    required String title,
  }) {
    if (_filePath != oldPath) return;

    _filePath = newPath;
    this.title.value = title;
  }

  Future<void> stopOtherSessionIfNeeded(String path) async {
    if (hasSession.value && !isSameSession(path)) {
      await stop(silent: true);
    }
  }

  Future<void> stop({bool silent = false}) async {
    _pageAttachmentToken++;

    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_controllerListener);
      await controller.dispose();
    }

    _controller = null;
    _filePath = null;
    _pageListener = null;
    hasSession.value = false;
    showMiniPlayer.value = false;
    isPageAttached.value = false;
    isPlaying.value = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    isInitialized.value = false;
    playbackError.value = null;
    title.value = '视频';
    mediaType.value = DownloadMediaType.video;
  }

  void _scheduleUiState(VoidCallback action) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) => action());
    binding.ensureVisualUpdate();
  }

  Future<void> toggle() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    _syncFromController();
  }

  Future<void> seekTo(Duration target) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    await controller.seekTo(target);
    _syncFromController();
  }

  Future<void> seekBy(Duration offset) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final currentDuration = controller.value.duration;
    final target = controller.value.position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > currentDuration
            ? currentDuration
            : target;
    await seekTo(clamped);
  }

  Future<void> openFullPlayer() async {
    if (_filePath == null || !hasSession.value) return;
    if (Get.currentRoute == RouteHelper.player) return;

    await Get.toNamed(
      RouteHelper.player,
      arguments: {
        'path': _filePath,
        'title': title.value,
        'mediaType': mediaType.value,
        'reuseSession': true,
      },
    );
  }

  Map<String, dynamic> sessionArguments() {
    return {
      'path': _filePath,
      'title': title.value,
      'mediaType': mediaType.value,
      'reuseSession': true,
    };
  }

  void _controllerListener() {
    _syncFromController();
    _pageListener?.call();
  }

  void _syncFromController() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final value = controller.value;
    isPlaying.value = value.isPlaying;
    position.value = value.position;
    duration.value = value.duration;
  }

  static DownloadMediaType mediaTypeFromArgument(Object? value) {
    if (value is DownloadMediaType) return value;
    if (value?.toString().toLowerCase() == 'audio') {
      return DownloadMediaType.audio;
    }
    return DownloadMediaType.video;
  }

  static DownloadMediaType inferMediaType(String path) {
    final lower = path.toLowerCase();
    const audioExtensions = ['.mp3', '.m4a', '.aac', '.wav', '.ogg', '.flac'];
    return audioExtensions.any(lower.endsWith)
        ? DownloadMediaType.audio
        : DownloadMediaType.video;
  }
}
