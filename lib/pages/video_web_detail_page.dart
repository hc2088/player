import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/favorite.dart';
import '../routes/route_helper.dart';
import '../services/download_service.dart';
import '../services/favorite_service.dart';
import '../utils/video_extractor.dart';
import 'download_list_page.dart';
import 'favorite_list_page.dart';

class VideoWebDetailPage extends StatefulWidget {
  final String defaultUrl;

  const VideoWebDetailPage({super.key, required this.defaultUrl});

  @override
  State<VideoWebDetailPage> createState() => _VideoWebDetailPageState();
}

class _VideoWebDetailPageState extends State<VideoWebDetailPage> {
  late final WebViewController _controller;
  String _currentUrl = '';
  String _pageTitle = '';
  bool _showAppBar = true;

  double _lastScrollY = 0;
  double _accumulatedScroll = 0;
  final double _threshold = 30; // 累积多少像素滑动才触发隐藏/显示

  void onScrollMessageReceived(String scrollMessage) {
    final scrollY = double.tryParse(scrollMessage) ?? 0;
    final delta = scrollY - _lastScrollY;

    // 忽略微小变化
    if (delta.abs() < 2) return;

    // 累积变化量，只有超过阈值才切换状态
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

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.defaultUrl;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 添加 JS 通道，接收滚动通知
      ..addJavaScriptChannel(
        'ScrollHandler',
        onMessageReceived: (message) {
          onScrollMessageReceived(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            if (!mounted) return;
            // 页面加载完成，更新标题
            _updatePageTitle();
            // 注入 JS，监听滚动事件，将 scrollY 发送给 Flutter
            await _controller.runJavaScript('''
              window.onscroll = function() {
                ScrollHandler.postMessage(window.scrollY.toString());
              };
            ''');
          },
          onNavigationRequest: (request) {
            setState(() {
              _currentUrl = request.url;
            });
            // 尝试异步更新标题（可选）
            Future.microtask(() => _updatePageTitle());
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_currentUrl));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = Get.arguments;
    if (args != null && args['url'] != null) {
      final newUrl = args['url'] as String;
      if (newUrl != _currentUrl) {
        _currentUrl = newUrl;
        _controller.loadRequest(Uri.parse(_currentUrl));
        setState(() {
          _pageTitle = '';
        });
      }
    }
  }

  void _updatePageTitle() async {
    final title = await _controller.getTitle();
    if (!mounted) return;
    setState(() {
      _pageTitle = title ?? '';
    });
  }

  void _showChangeUrlDialog() {
    final TextEditingController urlController =
        TextEditingController(text: _currentUrl);
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
          enableInteractiveSelection: true,
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
                setState(() => _currentUrl = newUrl);
                _controller.loadRequest(Uri.parse(newUrl));
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
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      // goBack之后主动更新标题
      _updatePageTitle();
    } else {
      Get.back();
    }
  }

  Future<void> _goForward() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
      // goForward之后主动更新标题
      _updatePageTitle();
    }
  }

  Future<void> _reload() async {
    _controller.reload();
  }

  Future<void> _handleCollect() async {
    final favoriteService = Get.find<FavoriteService>();
    bool added = await favoriteService
        .addFavorite(Favorite(url: _currentUrl, title: _pageTitle));
    Get.snackbar('添加到收藏', added ? '已成功添加到收藏' : '该页面已在收藏列表中');
  }

  Future<void> _handleExtract() async {
    final downloadService = Get.find<DownloadService>();
    final executor = WebViewScriptExecutor(_controller);
    final urls = await VideoExtractor.extractVideoUrls(executor);

    if (urls.isNotEmpty) {
      int addedCount = 0;
      for (final url in urls) {
        final existed = downloadService.tasks.any((task) => task.url == url);
        if (!existed) {
          downloadService.addDownloadTask(url);
          addedCount++;
        }
      }
      Get.snackbar('视频链接提取成功', '共提取 ${urls.length} 个链接，已添加 $addedCount 个到下载列表');
      if (addedCount > 0) {
        Get.to(() => const DownloadListPage());
      }
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
                // 导航栏高度动画切换
                AnimatedContainer(
                  height: _showAppBar ? kToolbarHeight : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: AppBar(
                    title: Text(_pageTitle.isEmpty ? '' : _pageTitle),
                    leading:
                        RouteHelper.navigatorKey.currentState?.canPop() ?? false
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Get.back(),
                              )
                            : null,
                    actions: [
                      IconButton(
                          icon: const Icon(Icons.refresh), onPressed: _reload),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: _showChangeUrlDialog,
                        tooltip: '修改 URL',
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) {
                          switch (value) {
                            case 'collect':
                              _handleCollect();
                              break;
                            case 'extract':
                              _handleExtract();
                              break;
                            case 'favorites':
                              _handleGoToFavorites();
                              break;
                          }
                        },
                        itemBuilder: (BuildContext context) => const [
                          PopupMenuItem<String>(
                            value: 'collect',
                            child: Text('添加到收藏'),
                          ),
                          PopupMenuItem<String>(
                            value: 'extract',
                            child: Text('智能下载'),
                          ),
                          PopupMenuItem<String>(
                            value: 'favorites',
                            child: Text('我的收藏'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // WebView 占满剩余空间
                Expanded(child: WebViewWidget(controller: _controller)),
              ],
            ),
            // 左下角浮动按钮
            Positioned(
              bottom: 16,
              left: 16,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'btn_back',
                    onPressed: _goBack,
                    tooltip: '后退',
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.small(
                    heroTag: 'btn_forward',
                    onPressed: _goForward,
                    tooltip: '前进',
                    child: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
