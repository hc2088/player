import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:get/get.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isFileExists = false;

  @override
  void initState() {
    super.initState();
    final path = Get.arguments as String;

    // 先检查文件是否存在
    File file = File(path);
    file.exists().then((exists) {
      if (!exists) {
        Get.snackbar('错误', '文件不存在：$path');
        setState(() {
          _isFileExists = false;
        });
        return;
      }

      setState(() {
        _isFileExists = true;
      });

      // 初始化播放器，播放本地文件
      _videoPlayerController = VideoPlayerController.file(file)
        ..initialize().then((_) {
          setState(() {
            _chewieController = ChewieController(
              videoPlayerController: _videoPlayerController,
              aspectRatio: _videoPlayerController.value.aspectRatio,
              autoPlay: true,
              looping: false,
            );
          });
        });
    });
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('视频播放'),
      //   leading: IconButton(
      //     icon: const Icon(Icons.arrow_back),
      //     onPressed: () => Get.back(),
      //   ),
      // ),
      body: SafeArea(
        child: _isFileExists
            ? (_chewieController != null
                ? Chewie(controller: _chewieController!)
                : const Center(child: CircularProgressIndicator()))
            : Center(
                child: Text(
                  '文件不存在，无法播放',
                  style: TextStyle(fontSize: 16, color: Colors.red),
                ),
              ),
      ),
    );
  }
}
