import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:player/utils/screen_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../config/event_names.dart';
import '../controllers/home_page_controller.dart';
import '../models/favorite.dart';
import '../routes/route_helper.dart';
import '../services/download_service.dart';
import '../services/favorite_service.dart';
import '../utils/event_bus_helper.dart';
import '../utils/video_extractor.dart';

class VideoInAppWebDetailPage extends StatefulWidget {
  final String? defaultUrl;
  final VoidCallback? onOpenDrawer;

  const VideoInAppWebDetailPage(
      {super.key, this.defaultUrl, this.onOpenDrawer});

  @override
  State<VideoInAppWebDetailPage> createState() =>
      VideoInAppWebDetailPageState();
}

class VideoInAppWebDetailPageState extends State<VideoInAppWebDetailPage> {
  InAppWebViewController? _controller;
  UniqueKey _webViewKey = UniqueKey();

  String? url;
  String _pageTitle = '';
  bool isFavorite = false;

  StreamSubscription? _favoriteChangedSub;
  final HomePageController homeController = Get.find();
  late final Worker _webReloadWorker;

  bool _allowPop = true; // 初始值为 true，允许返回
  double _progress = 0;
  bool _isLoading = true;

  // 拖动按钮的位置状态
  Offset _fabOffset = Offset.zero;
  late Offset _dragOffsetFromOrigin;
  static const _fabOffsetXKey = 'fabOffsetX';
  static const _fabOffsetYKey = 'fabOffsetY';
  bool _fabReady = false;

  Future<void> reloadWebViewWithUrl(String newUrl) async {
    if (_controller != null && newUrl.isNotEmpty) {
      setState(() {
        url = newUrl;
        _isLoading = true;
        _progress = 0;
        _webViewKey = UniqueKey(); // 重建 key
      });
      await _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(newUrl)));
    }
  }

  @override
  void initState() {
    super.initState();

    url = widget.defaultUrl ?? '';

    _favoriteChangedSub = listenNamedEvent<FavoriteChangedEvent>(
      name: EventNames.favoriteChanged,
      onData: (event) {
        // 只会响应 name 为 'favorite' 的事件
        _checkIfFavorite(url);
      },
    );

    // 监听双击事件
    _webReloadWorker = ever(homeController.webReloadEvent, (_) async {
      final url = await AppConfig.getDefaultVideoUrl();
      reloadWebViewWithUrl(url);
    });

    _initFabOffset();
  }

  Future<void> _initFabOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble(_fabOffsetXKey);
    final dy = prefs.getDouble(_fabOffsetYKey);

    Offset saved = Offset(dx ?? 0, dy ?? 0);
    if (saved == Offset.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final defaultOffset = Offset(
          context.screenInfo.width - 56 - 16,
          context.screenInfo.usableHeight - 56 - 16,
        );
        setState(() {
          _fabOffset = defaultOffset;
          _fabReady = true;
        });
      });
    } else {
      setState(() {
        _fabOffset = saved;
        _fabReady = true;
      });
    }
  }

  @override
  void didChangeDependencies() {
    // TODO: implement didChangeDependencies
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _webReloadWorker.dispose();
    _controller?.dispose();
    _favoriteChangedSub?.cancel();
    super.dispose();
  }

  Future<void> _updatePageTitle() async {
    String? title = await _controller?.getTitle();
    print("_updatePageTitle=$title");
    setState(() {
      _pageTitle = title ?? '';
    });
  }

  void _showChangeUrlDialog() {
    final TextEditingController urlController =
        TextEditingController(text: url);
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
              var newUrl = urlController.text.trim();
              // 如果没有以 http/https 开头，默认加上 https://
              if (newUrl.isNotEmpty &&
                  !newUrl.toLowerCase().startsWith('http://') &&
                  !newUrl.toLowerCase().startsWith('https://')) {
                newUrl = 'https://$newUrl';
              }
              if (newUrl.isNotEmpty) {
                if (_controller != null) {
                  _controller!
                      .loadUrl(urlRequest: URLRequest(url: WebUri(newUrl)));
                }
              }
              AppConfig.setCustomHomePageUrl(newUrl);
              // 显示提示
              Get.snackbar('提示', '默认首页已修改为：$newUrl');
              Navigator.of(context).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    await _controller?.reload();
  }

  Future<void> _checkIfFavorite(String? url) async {
    var isAdded = false;
    if (url != null) {
      final favoriteService = Get.find<FavoriteService>();
      isAdded = await favoriteService.isFavorite(url);
    }
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
      Get.snackbar(
        '添加到收藏',
        success ? '已成功添加到收藏' : '添加收藏失败',
        mainButton: TextButton(
          onPressed: () {
            RouteHelper.toUnique(RouteHelper.favorite);
          },
          child: const Text('前往收藏页'),
        ),
      );
      _checkIfFavorite(currentUrl);
    }
  }

  String _generateFileName(String title, int index, String url) {
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'); // 清理非法字符
    final shortHash = url.hashCode.toRadixString(16);
    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMddHHmmss').format(now);
    return "$safeTitle-$shortHash-$timeStr-$index.mp4";
  }

  Future<void> _handleExtract() async {
    final downloadService = Get.find<DownloadService>();

    if (_controller == null) {
      Get.snackbar('视频链接提取', '未找到视频链接');
      return;
    }

    // 获取当前网页的 URL
    final currentUrl = (await _controller!.getUrl())?.toString();

    if (currentUrl == null || currentUrl.isEmpty) {
      Get.snackbar('视频链接提取', '无法获取当前网页地址');
      return;
    }

    String? pageTitle;
    try {
      pageTitle = await _controller!.getTitle();
    } catch (_) {
      pageTitle = _pageTitle; // fallback
    }

    pageTitle = (pageTitle != null && pageTitle.trim().isNotEmpty)
        ? pageTitle.trim()
        : "video_${DateTime.now().millisecondsSinceEpoch}";

    final executor = InAppWebViewScriptExecutor(_controller!);
    final urls = await VideoExtractor.extractVideoUrls(executor);

    if (urls.isNotEmpty) {
      int addedCount = 0;

      for (final entry in urls.asMap().entries) {
        final index = entry.key;
        final url = entry.value;
        final existed = downloadService.tasks.any((task) => task.url == url);

        if (!existed) {
          final uniqueFileName = _generateFileName(pageTitle, index, url);
          downloadService.addDownloadTask(
            url,
            currentUrl,
            fileName: uniqueFileName, // ✅ 传入当前网页链接
          );
          addedCount++;
        }
      }

      Get.snackbar(
        '视频链接提取成功',
        '共提取 ${urls.length} 个链接，已添加 $addedCount 个到下载列表',
        mainButton: TextButton(
          onPressed: () {
            bool foundHome = false;
            _backToHomeAndSwitchTab(1);
          },
          child: const Text('前往下载页'),
        ),
      );
    } else {
      Get.snackbar('视频链接提取', '未找到视频链接');
    }
  }

  void _backToHomeAndSwitchTab(int index) {
    bool found = false;
    Get.until((route) {
      if (route.settings.name == RouteHelper.home) {
        found = true;
        return true;
      }
      return false;
    });

    if (!found) {
      Get.offAllNamed(RouteHelper.home);
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      Get.find<HomePageController>().switchToTab(index);
    });
  }

  Future<void> _updateCanPop() async {
    if (_controller == null) return;

    final canGoBack1 = await canGoBack();
    Get.find<HomePageController>().canGoBack.value = canGoBack1;
    setState(() {
      _allowPop = !canGoBack1; // 如果 WebView 可以回退，则禁止侧滑返回
    });
  }

  Future<bool> canGoBack() async {
    if (_controller == null) return false;
    return await _controller?.canGoBack() ?? false; // 或者你已有 controller
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  AnimatedContainer(
                    height: kToolbarHeight,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: AppBar(
                      title: Text(_pageTitle.isEmpty ? '' : _pageTitle),
                      leading: widget.onOpenDrawer != null
                          ? IconButton(
                              icon: const Icon(Icons.menu),
                              onPressed: widget.onOpenDrawer,
                            )
                          : (ModalRoute.of(context)?.canPop ?? false
                              ? IconButton(
                                  icon: const Icon(Icons.arrow_back),
                                  onPressed: () => Get.back(),
                                )
                              : null),
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
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(3.0),
                        child: Visibility(
                          visible: _isLoading,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: LinearProgressIndicator(value: _progress),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxWidth = constraints.maxWidth;
                        final maxHeight = constraints.maxHeight;
                        return Stack(
                          children: [
                            InAppWebView(
                              key: _webViewKey,
                              initialUrlRequest:
                                  URLRequest(url: WebUri(url ?? "")),
                              initialSettings: InAppWebViewSettings(
                                allowsBackForwardNavigationGestures: true,
                              ),
                              onWebViewCreated: (controller) {
                                _controller = controller;
                                _updateCanPop();
                              },
                              onLoadStop: (controller, url) async {
                                // 更新标题（即使 URL 不变，也要更新 title）
                                _checkIfFavorite(url?.toString());
                                _updateCanPop();
                                _updatePageTitle();
                              },
                              onUpdateVisitedHistory:
                                  (controller, url, androidIsReload) async {
                                _checkIfFavorite(url.toString());
                                // 延迟确保 controller 状态更新完成
                                Future.delayed(
                                    const Duration(milliseconds: 300),
                                    () async {
                                  _updateCanPop();
                                  _updatePageTitle();
                                });
                              },
                              onScrollChanged: (controller, x, y) {
                                //_onScrollChanged(y.toDouble());
                              },
                              onProgressChanged: (controller, progress) {
                                setState(() {
                                  _progress = progress / 100;
                                  if (_progress == 1.0) {
                                    _isLoading = false; // 加载完成，隐藏进度条
                                  } else {
                                    _isLoading = true; // 继续显示进度条
                                  }
                                });
                              },
                              onReceivedError: (controller, request, error) {
                                setState(() {
                                  _isLoading = false; // 加载出错，隐藏进度条
                                });
                              },
                            ),
                            Visibility(
                              visible: _fabReady,
                              child: Positioned(
                                left: _fabOffset.dx,
                                top: _fabOffset.dy,
                                child: Listener(
                                  onPointerDown: (event) {
                                    _dragOffsetFromOrigin = event.localPosition;
                                  },
                                  child: Draggable(
                                    feedback: _buildFab(),
                                    childWhenDragging: const SizedBox.shrink(),
                                    onDragEnd: _onDragEnd,
                                    child: _buildFab(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveFabOffset(Offset offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fabOffsetXKey, offset.dx);
    await prefs.setDouble(_fabOffsetYKey, offset.dy);
  }

// 拖拽结束回调里，调用保存方法
  void _onDragEnd(DraggableDetails details) {
    final renderBox = context.findRenderObject() as RenderBox;
    final localOffset = renderBox.globalToLocal(details.offset);
    final maxWidth = renderBox.size.width;
    final fabWidth = 56.0;
    final fabHeight = 56.0;
    const margin = 16.0;

    // 安全高度
    final screenHeight = context.screenInfo.usableHeight;

    double dx = localOffset.dx - _dragOffsetFromOrigin.dx;
    double dy = localOffset.dy - _dragOffsetFromOrigin.dy;

    // 上下边界约束
    dy = dy.clamp(margin, screenHeight - fabHeight - margin);

    // 左右吸附
    if (dx < maxWidth / 2) {
      dx = margin;
    } else {
      dx = maxWidth - fabWidth - margin;
    }

    final newOffset = Offset(dx, dy);

    setState(() {
      _fabOffset = newOffset;
    });

    _saveFabOffset(newOffset);
  }

  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: _handleExtract,
      child: const Icon(Icons.download),
      tooltip: '提取视频',
    );
  }
}
