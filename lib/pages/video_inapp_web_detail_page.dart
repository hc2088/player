import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

import '../config/event_names.dart';
import '../models/favorite.dart';
import '../routes/route_helper.dart';
import '../services/download_service.dart';
import '../services/favorite_service.dart';
import '../utils/event_bus_helper.dart';
import '../utils/video_extractor.dart';
import 'favorite_list_page.dart';

class VideoInAppWebDetailPage extends StatefulWidget {
  final String defaultUrl;

  const VideoInAppWebDetailPage({super.key, required this.defaultUrl});

  @override
  State<VideoInAppWebDetailPage> createState() =>
      _VideoInAppWebDetailPageState();
}

class _VideoInAppWebDetailPageState extends State<VideoInAppWebDetailPage> {
  InAppWebViewController? _controller;
  late final ValueNotifier<String> currentUrlNotifier;
  String _pageTitle = '';
  bool _showAppBar = true;
  bool isFavorite = false;

  double _lastScrollY = 0;
  double _accumulatedScroll = 0;
  final double _threshold = 30;

  StreamSubscription? _favoriteChangedSub;

  @override
  void initState() {
    super.initState();
    currentUrlNotifier = ValueNotifier(widget.defaultUrl);

    currentUrlNotifier.addListener(() {
      final url = currentUrlNotifier.value;
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      _checkIfFavorite(url);
      _updatePageTitle();
    });
    _checkIfFavorite(currentUrlNotifier.value);

    _favoriteChangedSub = listenNamedEvent<FavoriteChangedEvent>(
      name: EventNames.favoriteChanged,
      onData: (event) {
        // 只会响应 name 为 'favorite' 的事件
        _checkIfFavorite(currentUrlNotifier.value);
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = Get.arguments;
    if (args != null && args['url'] != null) {
      final newUrl = args['url'] as String;
      if (newUrl != currentUrlNotifier.value) {
        currentUrlNotifier.value = newUrl;
      }
    }
  }

  @override
  void dispose() {
    currentUrlNotifier.dispose();
    _favoriteChangedSub?.cancel();
    super.dispose();
  }

  void _onScrollChanged(double scrollY) {
    double delta = scrollY - _lastScrollY;
    if (delta.abs() < 2) return;

    _accumulatedScroll += delta;

    if (_accumulatedScroll > _threshold && _showAppBar) {
      setState(() {
        _showAppBar = false;
        _accumulatedScroll = 0;
      });
    } else if (_accumulatedScroll < -_threshold && !_showAppBar) {
      setState(() {
        _showAppBar = true;
        _accumulatedScroll = 0;
      });
    }

    _lastScrollY = scrollY;
  }

  Future<void> _updatePageTitle() async {
    String? title = await _controller?.getTitle();
    if (!mounted) return;
    setState(() {
      _pageTitle = title ?? '';
    });
  }

  void _showChangeUrlDialog() {
    final TextEditingController urlController =
        TextEditingController(text: currentUrlNotifier.value);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改 URL'),
        content: TextField(
          controller: urlController,
          decoration: InputDecoration(
            hintText: '请输入新网址',
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => urlController.clear(),
            ),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newUrl = urlController.text.trim();
              if (newUrl.isNotEmpty) {
                currentUrlNotifier.value = newUrl;
              }
              Navigator.of(context).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _goBack() async {
    if (await _controller?.canGoBack() ?? false) {
      await _controller?.goBack();
      _updatePageTitle();
    } else {
      Get.back();
    }
  }

  Future<void> _goForward() async {
    if (await _controller?.canGoForward() ?? false) {
      await _controller?.goForward();
      _updatePageTitle();
    }
  }

  Future<void> _reload() async {
    await _controller?.reload();
  }

  Future<void> _checkIfFavorite(String url) async {
    final favoriteService = Get.find<FavoriteService>();
    final isAdded = await favoriteService.isFavorite(url);
    if (!mounted) return;
    setState(() {
      isFavorite = isAdded;
    });
  }

  Future<void> _handleCollect() async {
    final favoriteService = Get.find<FavoriteService>();

    // 获取当前网页的 URL
    final currentUrl = (await _controller!.getUrl())?.toString();

    if (currentUrl == null || currentUrl.isEmpty) {
      Get.snackbar('收藏操作失败', '无法获取当前网页地址');
      return;
    }

    // 判断当前 URL 是否已收藏
    final bool isFavorite = await favoriteService.isFavorite(currentUrl);

    bool success = false;
    if (isFavorite) {
      // 已收藏，则取消收藏
      success = await favoriteService.removeFavoriteUrl(currentUrl);
      Get.snackbar('取消收藏', success ? '已成功取消收藏' : '取消收藏失败');
    } else {
      // 未收藏，添加收藏
      success = await favoriteService.addFavorite(
        Favorite(url: currentUrl, title: _pageTitle),
      );
      Get.snackbar('添加到收藏', success ? '已成功添加到收藏' : '添加收藏失败');
      _checkIfFavorite(currentUrl);
    }
  }

  String? _filterTitle(String title) {
    final reg = RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]');
    final cleaned = title.replaceAll(reg, '').trim();
    if (cleaned.isEmpty) return null;
    final maxLength = 10;
    return cleaned.length > maxLength
        ? cleaned.substring(0, maxLength)
        : cleaned;
  }

  Future<void> _handleExtract() async {
    final downloadService = Get.find<DownloadService>();

    if (_controller == null) {
      Get.snackbar('视频链接提取', '未找到视频链接');
      return;
    }

    // ✅ 获取当前网页的 URL
    final currentUrl = (await _controller!.getUrl())?.toString();

    if (currentUrl == null || currentUrl.isEmpty) {
      Get.snackbar('视频链接提取', '无法获取当前网页地址');
      return;
    }

    final executor = InAppWebViewScriptExecutor(_controller!);
    final urls = await VideoExtractor.extractVideoUrls(executor);

    if (urls.isNotEmpty) {
      int addedCount = 0;

      for (final url in urls) {
        final existed = downloadService.tasks.any((task) => task.url == url);
        if (!existed) {
          downloadService.addDownloadTask(
            url,
            currentUrl,
            fileName: _pageTitle, // ✅ 传入当前网页链接
          );
          addedCount++;
        }
      }

      Get.snackbar('视频链接提取成功', '共提取 ${urls.length} 个链接，已添加 $addedCount 个到下载列表');
    } else {
      Get.snackbar('视频链接提取', '未找到视频链接');
    }
  }

  void _handleGoToFavorites() {
    Get.to(() => const FavoriteListPage());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                AnimatedContainer(
                  height: _showAppBar ? kToolbarHeight : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: AppBar(
                    title: Text(_pageTitle.isEmpty ? '' : _pageTitle),
                    leading: ModalRoute.of(context)?.canPop ?? false
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Get.back(),
                          )
                        : null,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _reload,
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: _showChangeUrlDialog,
                        tooltip: '修改 URL',
                      ),
                      IconButton(
                        icon: Icon(isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border),
                        onPressed: _handleCollect,
                        tooltip: isFavorite ? '已收藏' : '添加到收藏',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InAppWebView(
                    initialUrlRequest:
                        URLRequest(url: WebUri(currentUrlNotifier.value)),
                    initialSettings: InAppWebViewSettings(
                      allowsBackForwardNavigationGestures: true,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                    },
                    onLoadStop: (controller, url) async {
                      // url 可能为 null，需要判断一下
                      if (url != null) {
                        final currentUrl = url.toString();
                        // 更新 currentUrlNotifier
                        currentUrlNotifier.value = currentUrl;
                      }
                    },
                    onScrollChanged: (controller, x, y) {
                      //_onScrollChanged(y.toDouble());
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton(
                onPressed: _handleExtract,
                child: const Icon(Icons.download),
                tooltip: '提取视频',
              ),
            )
          ],
        ),
      ),
    );
  }
}
