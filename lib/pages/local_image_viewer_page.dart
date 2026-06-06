import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/file_share_service.dart';

class LocalImageViewerPage extends StatefulWidget {
  const LocalImageViewerPage({super.key});

  @override
  State<LocalImageViewerPage> createState() => _LocalImageViewerPageState();
}

class _LocalImageViewerPageState extends State<LocalImageViewerPage> {
  final TransformationController _transformationController =
      TransformationController();

  String? _filePath;
  String _title = '图片';

  @override
  void initState() {
    super.initState();

    final args = Get.arguments;
    if (args is Map) {
      _filePath = args['path'] as String?;
      _title = (args['title'] as String?) ?? _title;
    } else if (args is String) {
      _filePath = args;
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _zoom(double scale) {
    final next = Matrix4.copy(_transformationController.value);
    final storage = next.storage;
    storage[0] *= scale;
    storage[1] *= scale;
    storage[2] *= scale;
    storage[3] *= scale;
    storage[4] *= scale;
    storage[5] *= scale;
    storage[6] *= scale;
    storage[7] *= scale;
    _transformationController.value = next;
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  Future<void> _shareFile() async {
    final path = _filePath;
    if (path == null || path.isEmpty) return;

    try {
      await FileShareService.shareFile(path, title: _title);
    } catch (e) {
      Get.snackbar('分享失败', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _filePath;
    final fileExists = path != null && File(path).existsSync();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '分享',
            onPressed: fileExists ? _shareFile : null,
            icon: const Icon(Icons.share),
          ),
          IconButton(
            tooltip: '缩小',
            onPressed: fileExists ? () => _zoom(0.8) : null,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            tooltip: '放大',
            onPressed: fileExists ? () => _zoom(1.25) : null,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '还原',
            onPressed: fileExists ? _resetZoom : null,
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
      body: fileExists
          ? InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 6,
              child: Center(
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                ),
              ),
            )
          : const Center(
              child: Text(
                '图片文件不存在',
                style: TextStyle(color: Colors.white70),
              ),
            ),
    );
  }
}
