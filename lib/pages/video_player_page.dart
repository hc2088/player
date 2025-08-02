import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;

  bool _isFileExists = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is! String) {
      _checked = true;
      _isFileExists = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.snackbar('错误', '无效的文件路径参数');
      });
      return;
    }

    final path = Get.arguments as String;
    final file = File(path);

    file.exists().then((exists) {
      setState(() {
        _isFileExists = exists;
        _checked = true;
      });
      _updateStatusBar(isDarkBackground: exists);

      if (!exists) {
        Get.snackbar('错误', '文件不存在：$path');
        return;
      }

      _videoPlayerController = VideoPlayerController.file(file);

      // 监听播放状态变化，同步状态栏文字颜色
      _videoPlayerController.addListener(_videoPlayerListener);

      _videoPlayerController.initialize().then((_) {
        setState(() {
          _chewieController = ChewieController(
            videoPlayerController: _videoPlayerController,
            aspectRatio: _videoPlayerController.value.aspectRatio,
            autoPlay: true,
            looping: false,
          );
        });
        _updateStatusBar(isDarkBackground: true);
      });
    });
  }

  void _videoPlayerListener() {
    if (!_videoPlayerController.value.isInitialized) return;

    // 例如：播放时保持黑底白字，暂停时可以调整
    if (_videoPlayerController.value.isPlaying) {
      _updateStatusBar(isDarkBackground: true);
    } else {
      // 你也可以根据需求改变，这里示例为播放暂停都保持黑底白字
      _updateStatusBar(isDarkBackground: true);
    }
  }

  void _updateStatusBar({required bool isDarkBackground}) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: isDarkBackground ? Colors.black : Colors.white,
      statusBarIconBrightness:
          isDarkBackground ? Brightness.light : Brightness.dark,
      statusBarBrightness:
          isDarkBackground ? Brightness.dark : Brightness.light, // iOS
    ));
  }

  @override
  void dispose() {
    _videoPlayerController.removeListener(_videoPlayerListener);
    _videoPlayerController.dispose();
    _chewieController?.dispose();

    // 恢复默认状态栏风格（可根据需求调整）
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isFileExists ? Colors.black : Colors.white,
      body: SafeArea(
        child: !_checked
            ? const Center(child: CircularProgressIndicator())
            : _isFileExists
                ? (_chewieController != null
                    ? Chewie(controller: _chewieController!)
                    : const Center(child: CircularProgressIndicator()))
                : const Center(
                    child: Text(
                      '文件不存在，无法播放',
                      style: TextStyle(fontSize: 16, color: Colors.red),
                    ),
                  ),
      ),
    );
  }
}
