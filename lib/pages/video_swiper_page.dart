import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../models/download_task.dart';
import '../services/download_service.dart';
import '../services/file_share_service.dart';
import '../services/playback_service.dart';

class VideoSwiperPage extends StatefulWidget {
  const VideoSwiperPage({super.key});

  @override
  State<VideoSwiperPage> createState() => _VideoSwiperPageState();
}

class _VideoSwiperPageState extends State<VideoSwiperPage>
    with WidgetsBindingObserver {
  late PageController _pageController;
  late int _currentIndex;
  final DownloadService _downloadService = Get.find<DownloadService>();
  final PlaybackService _playback = Get.find<PlaybackService>();

  final Map<int, VideoPlayerController> _videoControllerMap = {};
  final Map<int, ChewieController> _chewieControllerMap = {};

  final Map<int, Worker> _statusWatchers = {};
  bool _leaveHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final args = Get.arguments;
    _currentIndex = (args != null && args['initialIndex'] is int)
        ? args['initialIndex']
        : 0;

    _pageController = PageController(initialPage: _currentIndex);
    _playback.attachPage(() {});
    _initControllersAround(_currentIndex);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _handleLeavePage();
    _pageController.dispose();
    for (var worker in _statusWatchers.values) {
      worker.dispose();
    }
    _statusWatchers.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final videoController = _videoControllerMap[_currentIndex];
    if (videoController == null) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      videoController.pause();
    } else if (state == AppLifecycleState.resumed) {
      videoController.play();
    }
  }

  Future<VideoPlayerController?> _initControllerAt(int index) async {
    if (index < 0 || index >= _downloadService.tasks.length) return null;
    if (_videoControllerMap.containsKey(index)) {
      return _videoControllerMap[index];
    }

    final task = _downloadService.tasks[index];
    if (task.mediaType != DownloadMediaType.video) return null;

    if (task.status != DownloadStatus.completed) {
      if (!_statusWatchers.containsKey(index)) {
        _statusWatchers[index] = ever(task.statusRx, (status) async {
          if (!mounted) return;

          if (status == DownloadStatus.completed) {
            await _initControllerAt(index);
            if (mounted) setState(() {});
          }
        });
      }
      return null;
    }

    final filePath = task.filePath;
    if (filePath == null || filePath.isEmpty) return null;

    final file = File(filePath);
    if (!await file.exists()) return null;

    await _playback.stopOtherSessionIfNeeded(filePath);

    VideoPlayerController? videoController =
        _playback.claimControllerForPath(filePath);

    if (videoController == null) {
      videoController = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: true,
        ),
      );
      await videoController.initialize();
      videoController.setLooping(false);
    }

    videoController.addListener(_videoPlayerListener);

    final chewieController = ChewieController(
      videoPlayerController: videoController,
      aspectRatio: videoController.value.aspectRatio,
      autoPlay: false,
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

    _videoControllerMap[index] = videoController;
    _chewieControllerMap[index] = chewieController;

    return videoController;
  }

  Future<void> _initControllersAround(int index) async {
    if (!mounted || _leaveHandled) return;

    final tasks = _downloadService.tasks;

    for (int i = index - 1; i <= index + 1; i++) {
      if (!mounted || _leaveHandled) return;
      if (i >= 0 && i < tasks.length) {
        await _initControllerAt(i);
      }
    }

    final keepIndexes = [index - 1, index, index + 1];
    final toRemove = _videoControllerMap.keys
        .where((k) => !keepIndexes.contains(k))
        .toList();

    for (final i in toRemove) {
      if (!mounted || _leaveHandled) return;
      _videoControllerMap[i]?.removeListener(_videoPlayerListener);
      _videoControllerMap[i]?.dispose();
      _chewieControllerMap[i]?.dispose();

      _videoControllerMap.remove(i);
      _chewieControllerMap.remove(i);
    }

    await _playOnly(index);

    if (!mounted || _leaveHandled) return;
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _playOnly(int indexToPlay) async {
    if (indexToPlay >= 0 && indexToPlay < _downloadService.tasks.length) {
      final task = _downloadService.tasks[indexToPlay];
      final path = task.filePath;
      if (path != null && path.isNotEmpty) {
        await _playback.stopOtherSessionIfNeeded(path);
      }
    }

    _videoControllerMap.forEach((index, controller) {
      if (index == indexToPlay) {
        if (controller.value.isInitialized && !controller.value.isPlaying) {
          controller.play();
        }
      } else {
        if (controller.value.isPlaying) {
          controller.pause();
        }
      }
    });
  }

  void _disposeAllControllers() {
    for (var controller in _videoControllerMap.values) {
      controller.removeListener(_videoPlayerListener);
      controller.dispose();
    }
    for (var chewie in _chewieControllerMap.values) {
      chewie.dispose();
    }
    _videoControllerMap.clear();
    _chewieControllerMap.clear();
  }

  bool get _canTransferCurrentSession {
    if (_currentIndex < 0 || _currentIndex >= _downloadService.tasks.length) {
      return false;
    }

    final task = _downloadService.tasks[_currentIndex];
    if (task.mediaType != DownloadMediaType.video) return false;
    if (task.status != DownloadStatus.completed) return false;

    final filePath = task.filePath;
    if (filePath == null || filePath.isEmpty) return false;

    return _videoControllerMap[_currentIndex] != null;
  }

  Future<void> _transferCurrentToBackground() async {
    final controller = _videoControllerMap.remove(_currentIndex);
    _chewieControllerMap.remove(_currentIndex)?.dispose();

    final otherIndexes = _videoControllerMap.keys.toList();
    for (final index in otherIndexes) {
      _videoControllerMap[index]?.removeListener(_videoPlayerListener);
      _videoControllerMap[index]?.dispose();
      _chewieControllerMap[index]?.dispose();
      _videoControllerMap.remove(index);
      _chewieControllerMap.remove(index);
    }

    if (controller == null) return;

    controller.removeListener(_videoPlayerListener);

    final task = _downloadService.tasks[_currentIndex];
    await _playback.receiveFromPageLeave(
      controller: controller,
      path: task.filePath!,
      title: task.fileName ?? '视频',
      mediaType: DownloadMediaType.video,
    );
  }

  void _handleLeavePage() {
    if (_leaveHandled) return;
    _leaveHandled = true;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    if (_canTransferCurrentSession) {
      _transferCurrentToBackground();
      return;
    }

    _disposeAllControllers();
    _playback.detachPage();
  }

  bool get _isUserPoppingGesture {
    return ModalRoute.of(context)?.navigator?.userGestureInProgress ?? false;
  }

  void _videoPlayerListener() {
    final controller = _videoControllerMap[_currentIndex];
    if (controller == null || !controller.value.isInitialized) return;
    if (_isUserPoppingGesture) return;

    _updateStatusBar(isDarkBackground: true);
  }

  void _updateStatusBar({required bool isDarkBackground}) {
    final brightness = isDarkBackground ? Brightness.light : Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: isDarkBackground ? Colors.black : Colors.white,
      statusBarIconBrightness: brightness,
      statusBarBrightness:
          isDarkBackground ? Brightness.dark : Brightness.light,
    ));
  }

  void _onPageChanged(int index) {
    _initControllersAround(index);
  }

  Future<void> _shareTask(DownloadTask task) async {
    final path = task.filePath;
    if (path == null || path.isEmpty) return;

    try {
      await FileShareService.shareFile(path, title: task.fileName);
    } catch (e) {
      Get.snackbar('分享失败', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _handleLeavePage();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Obx(() {
          final tasks = _downloadService.tasks;
          if (tasks.isEmpty) {
            return const Center(child: Text('暂无视频'));
          }

          return PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _downloadService.tasks.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final task = _downloadService.tasks[index];

              if (task.status == DownloadStatus.completed) {
                if (task.mediaType != DownloadMediaType.video) {
                  return SafeArea(
                    child: Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.audiotrack,
                            color: Colors.white70,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            task.fileName ?? '音频文件',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '音频已下载，当前页面仅播放视频',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 20),
                          IconButton.filledTonal(
                            tooltip: '分享',
                            onPressed: () => _shareTask(task),
                            icon: const Icon(Icons.share),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final chewieController = _chewieControllerMap[index];
                final filePath = task.filePath;

                if (filePath == null || filePath.isEmpty) {
                  return const Center(
                    child: Text('文件路径不存在', style: TextStyle(color: Colors.red)),
                  );
                }

                final file = File(filePath);
                if (!file.existsSync()) {
                  return const Center(
                    child: Text('文件不存在', style: TextStyle(color: Colors.red)),
                  );
                }

                if (chewieController == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                return SafeArea(
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Chewie(controller: chewieController),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: IconButton.filledTonal(
                          tooltip: '分享',
                          onPressed: () => _shareTask(task),
                          icon: const Icon(Icons.share),
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                return SafeArea(
                  child: Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${task.fileName}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20),
                        ),
                        Text(
                          '状态：${task.status.name}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20),
                        ),
                        if (task.status == DownloadStatus.downloading) ...[
                          const SizedBox(height: 12),
                          LinearProgressIndicator(value: task.progress),
                          const SizedBox(height: 8),
                          Text(
                            '${(task.progress * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (task.status != DownloadStatus.downloading)
                          ElevatedButton.icon(
                            onPressed: () {
                              _downloadService.retryDownload(task);
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('重新下载'),
                          ),
                      ],
                    ),
                  ),
                );
              }
            },
          );
        }),
      ),
    );
  }
}
