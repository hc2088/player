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
  late final PageController _pageController;

  List<_ImagePreviewItem> _items = const [];
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;

    if (args is Map) {
      final rawItems = args['items'];
      if (rawItems is List) {
        _items = rawItems
            .whereType<Map>()
            .map((item) {
              final path = item['path']?.toString();
              if (path == null || path.isEmpty) return null;
              return _ImagePreviewItem(
                path: path,
                title: item['title']?.toString() ?? '图片',
              );
            })
            .whereType<_ImagePreviewItem>()
            .toList(growable: false);
      }

      if (_items.isEmpty) {
        final path = args['path'] as String?;
        if (path != null && path.isNotEmpty) {
          _items = [
            _ImagePreviewItem(
              path: path,
              title: (args['title'] as String?) ?? '图片',
            ),
          ];
        }
      }

      _currentIndex = (args['initialIndex'] as int?) ?? 0;
    } else if (args is String) {
      _items = [
        _ImagePreviewItem(path: args, title: '图片'),
      ];
    }

    if (_items.isEmpty) {
      _currentIndex = 0;
    } else {
      _currentIndex = _currentIndex.clamp(0, _items.length - 1);
    }
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _shareFile() async {
    if (_items.isEmpty) return;
    final item = _items[_currentIndex];

    try {
      await FileShareService.shareFile(item.path, title: item.title);
    } catch (e) {
      Get.snackbar('分享失败', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = _items.isNotEmpty;
    final currentTitle = hasItems ? _items[_currentIndex].title : '图片';
    final title = hasItems && _items.length > 1
        ? '$currentTitle ${_currentIndex + 1}/${_items.length}'
        : currentTitle;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '分享',
            onPressed: hasItems && File(_items[_currentIndex].path).existsSync()
                ? _shareFile
                : null,
            icon: const Icon(Icons.share),
          ),
        ],
      ),
      body: hasItems
          ? PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _items.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final item = _items[index];
                return _ZoomableImagePage(item: item);
              },
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

class _ZoomableImagePage extends StatefulWidget {
  const _ZoomableImagePage({required this.item});

  final _ImagePreviewItem item;

  @override
  State<_ZoomableImagePage> createState() => _ZoomableImagePageState();
}

class _ZoomableImagePageState extends State<_ZoomableImagePage> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.item.path);
    if (!file.existsSync()) {
      return const Center(
        child: Text(
          '图片文件不存在',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return InteractiveViewer(
      transformationController: _controller,
      minScale: 0.5,
      maxScale: 6,
      boundaryMargin: const EdgeInsets.all(80),
      child: Center(
        child: Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white70,
                size: 56,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ImagePreviewItem {
  const _ImagePreviewItem({
    required this.path,
    required this.title,
  });

  final String path;
  final String title;
}
