import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../models/download_task.dart';
import '../services/download_service.dart';

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

  final Map<int, VideoPlayerController> _videoControllerMap = {};
  final Map<int, ChewieController> _chewieControllerMap = {};

  final Map<int, Worker> _statusWatchers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final args = Get.arguments;
    _currentIndex = (args != null && args['initialIndex'] is int)
        ? args['initialIndex']
        : 0;

    _pageController = PageController(initialPage: _currentIndex);

    _initControllersAround(_currentIndex);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeAllControllers();
    _pageController.dispose();
    // 清除 Rx 监听器
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
    if (_videoControllerMap.containsKey(index))
      return _videoControllerMap[index];

    final task = _downloadService.tasks[index];

    // 如果未完成，监听其变化，等完成后再初始化
    if (task.status != DownloadStatus.completed) {
      if (!_statusWatchers.containsKey(index)) {
        _statusWatchers[index] = ever(task.statusRx, (status) async {
          // 页面已被释放，不再响应
          if (!mounted) return;

          if (status == DownloadStatus.completed) {
            await _initControllerAt(index); // 会自动跳过重复初始化
            if (mounted) setState(() {});
          }
        });
      }
      return null;
    }

    // 如果已经是完成状态，正常初始化 controller
    final filePath = task.filePath;
    if (filePath == null || filePath.isEmpty) return null;

    final file = File(filePath);
    if (!await file.exists()) return null;

    final videoController = VideoPlayerController.file(file);
    await videoController.initialize();

    videoController.setLooping(false);
    videoController.addListener(_videoPlayerListener);

    final chewieController = ChewieController(
      videoPlayerController: videoController,
      aspectRatio: videoController.value.aspectRatio,
      autoPlay: false,
      looping: false,
    );

    _videoControllerMap[index] = videoController;
    _chewieControllerMap[index] = chewieController;

    return videoController;
  }

  Future<void> _initControllersAround(int index) async {
    final tasks = _downloadService.tasks;

    // 初始化当前页、前一页、后一页
    for (int i = index - 1; i <= index + 1; i++) {
      if (i >= 0 && i < tasks.length) {
        await _initControllerAt(i);
      }
    }

    // 移除其他页面 controller（仅保留最多 3 个）
    final keepIndexes = [index - 1, index, index + 1];
    final toRemove = _videoControllerMap.keys
        .where((k) => !keepIndexes.contains(k))
        .toList();

    for (final i in toRemove) {
      _videoControllerMap[i]?.removeListener(_videoPlayerListener);
      _videoControllerMap[i]?.dispose();
      _chewieControllerMap[i]?.dispose();

      _videoControllerMap.remove(i);
      _chewieControllerMap.remove(i);
    }

    _playOnly(index);

    setState(() {
      _currentIndex = index;
    });
  }

  void _playOnly(int indexToPlay) {
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

  bool get _isUserPoppingGesture {
    return ModalRoute.of(context)?.navigator?.userGestureInProgress ?? false;
  }

  void _videoPlayerListener() {
    final controller = _videoControllerMap[_currentIndex];
    if (controller == null || !controller.value.isInitialized) return;
    if (_isUserPoppingGesture) return;

    if (controller.value.isPlaying) {
      _updateStatusBar(isDarkBackground: true);
    } else {
      _updateStatusBar(isDarkBackground: true);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  ],
                ),
              );
            } else {
              // 非完成状态，显示下载状态与进度，并提供重试按钮
              return SafeArea(
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '状态：${task.fileName}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 20),
                      ),
                      Text(
                        '状态：${task.status.name}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 20),
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
    );
  }
}
