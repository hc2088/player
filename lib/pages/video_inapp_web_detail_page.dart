import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

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
  String? url;
  String _pageTitle = '';
  bool _showAppBar = true;
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

  Future<void> reloadWebViewWithUrl(String newUrl) async {
    if (_controller != null && newUrl.isNotEmpty) {
      setState(() {
        url = newUrl;
        _isLoading = true;
        _progress = 0;
      });
      await _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(newUrl)));
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final screenSize = MediaQuery.of(context).size;
      final safeBottom = MediaQuery.of(context).padding.bottom;

      // 初始化位置为右下角，距离右边16，底部距离TabBar（56）+安全区域
      setState(() {
        _fabOffset = Offset(
          screenSize.width - 56 - 16,
          screenSize.height - 56 - safeBottom - 16 - 156, // 56 是 TabBar 高度
        );
      });
    });

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
      if (_controller != null) {
        _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      }
    });
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
              final newUrl = urlController.text.trim();
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
    setState(() {
      _allowPop = !canGoBack1; // 如果 WebView 可以回退，则禁止侧滑返回
    });
  }

  Future<bool> canGoBack() async {
    if (_controller == null) return false;
    return await _controller?.canGoBack() ?? false; // 或者你已有 controller
  }

  Widget _buildDraggableFab() {
    final screenSize = MediaQuery.of(context).size;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: _fabOffset.dx,
      top: _fabOffset.dy,
      child: Listener(
        onPointerDown: (event) {
          // 记录点击时与 FAB 左上角的偏移，用于拖拽后修正落点
          _dragOffsetFromOrigin = event.localPosition;
        },
        child: Draggable(
          feedback: _buildFab(),
          childWhenDragging: Opacity(opacity: 0.5, child: _buildFab()),
          onDragEnd: (details) {
            final renderBox = context.findRenderObject() as RenderBox;
            final offset = renderBox.globalToLocal(details.offset);

            // 修正落点，让 FAB 中心落在鼠标点
            double newX = (offset.dx - _dragOffsetFromOrigin.dx)
                .clamp(0.0, screenSize.width - 56);
            double newY = (offset.dy - _dragOffsetFromOrigin.dy)
                .clamp(0.0, screenSize.height - 56 - safeBottom - 156);

            setState(() {
              _fabOffset = Offset(newX, newY);
            });
          },
          child: _buildFab(),
        ),
      ),
    );
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
                    height: _showAppBar ? kToolbarHeight : 0,
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
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(url ?? "")),
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
                        Future.delayed(const Duration(milliseconds: 300),
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
                  ),
                ],
              ),
              // Positioned(
              //   bottom: 16,
              //   right: 16,
              //   child: FloatingActionButton(
              //     onPressed: _handleExtract,
              //     child: const Icon(Icons.download),
              //     tooltip: '提取视频',
              //   ),
              // )
              // 在 build 方法中替换原来的 Positioned
              _buildDraggableFab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: _handleExtract,
      child: const Icon(Icons.download),
      tooltip: '提取视频',
    );
  }
}
