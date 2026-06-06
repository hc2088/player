import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:player/widgets/floating_ball.dart';

import '../config/app_config.dart';
import '../config/event_names.dart';
import '../controllers/home_page_controller.dart';
import '../models/download_task.dart';
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
  bool _isExtractingMedia = false;
  String _extractStatusText = '';
  int _extractRunId = 0;

  Future<void> reloadWebViewWithUrl(String newUrl) async {
    if (_controller != null && newUrl.isNotEmpty) {
      _cancelExtractFeedback();
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

    // _initFabOffset();
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
                  _cancelExtractFeedback();
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
    _cancelExtractFeedback();
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

  String _generateFileName(
    String title,
    int index,
    String url,
    ExtractedMediaType type,
  ) {
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'); // 清理非法字符
    final shortHash = url.hashCode.toRadixString(16);
    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMddHHmmss').format(now);
    final suffix = type == ExtractedMediaType.audio ? 'mp3' : 'mp4';
    return "$safeTitle-$shortHash-$timeStr-$index.$suffix";
  }

  DownloadMediaType _toDownloadMediaType(ExtractedMediaType type) {
    return type == ExtractedMediaType.audio
        ? DownloadMediaType.audio
        : DownloadMediaType.video;
  }

  void _cancelExtractFeedback() {
    _extractRunId++;
    if (!mounted) return;
    if (!_isExtractingMedia && _extractStatusText.isEmpty) return;

    setState(() {
      _isExtractingMedia = false;
      _extractStatusText = '';
    });
  }

  bool _isCurrentExtractRun(int extractRunId) {
    return mounted && extractRunId == _extractRunId;
  }

  void _updateExtractStatus(int extractRunId, String text) {
    if (!_isCurrentExtractRun(extractRunId)) return;

    if (!mounted) return;
    setState(() {
      _extractStatusText = text;
    });
  }

  Future<void> _handleExtract() async {
    if (_isExtractingMedia) {
      Get.snackbar('媒体链接提取', '正在提取中，请稍候');
      return;
    }

    setState(() {
      _isExtractingMedia = true;
      _extractStatusText = '正在分析页面媒体链接...';
    });

    final extractRunId = ++_extractRunId;
    final downloadService = Get.find<DownloadService>();

    try {
      if (_controller == null) {
        Get.snackbar('媒体链接提取', '未找到可用页面');
        return;
      }

      Get.snackbar(
        '媒体链接提取',
        '正在分析当前页面，请稍候...',
        duration: const Duration(seconds: 2),
        showProgressIndicator: true,
      );

      _updateExtractStatus(extractRunId, '正在获取当前网页地址...');

      // 获取当前网页的 URL
      final currentUrl = (await _controller!.getUrl())?.toString();
      if (!_isCurrentExtractRun(extractRunId)) return;

      if (currentUrl == null || currentUrl.isEmpty) {
        Get.snackbar('媒体链接提取', '无法获取当前网页地址');
        return;
      }

      String? pageTitle;
      try {
        pageTitle = await _controller!.getTitle();
      } catch (_) {
        pageTitle = _pageTitle; // fallback
      }
      if (!_isCurrentExtractRun(extractRunId)) return;

      pageTitle = (pageTitle != null && pageTitle.trim().isNotEmpty)
          ? pageTitle.trim()
          : "media_${DateTime.now().millisecondsSinceEpoch}";

      _updateExtractStatus(extractRunId, '正在识别音频和视频链接...');

      final executor = InAppWebViewScriptExecutor(_controller!);
      final mediaItems = await VideoExtractor.extractMediaUrls(
        executor,
        pageUrl: currentUrl,
        pageTitle: pageTitle,
      );
      if (!_isCurrentExtractRun(extractRunId)) return;

      if (mediaItems.isNotEmpty) {
        int addedCount = 0;
        int existedCount = 0;

        _updateExtractStatus(
          extractRunId,
          '已找到 ${mediaItems.length} 个媒体，正在加入下载任务...',
        );

        for (final entry in mediaItems.asMap().entries) {
          if (!_isCurrentExtractRun(extractRunId)) return;

          final index = entry.key;
          final media = entry.value;
          final mediaType = _toDownloadMediaType(media.type);
          final existed = downloadService.tasks.any(
            (task) => task.url == media.url && task.mediaType == mediaType,
          );

          if (existed) {
            existedCount++;
            continue;
          }

          _updateExtractStatus(
            extractRunId,
            '正在添加下载任务 ${addedCount + 1}/${mediaItems.length}...',
          );

          final uniqueFileName = media.name?.trim().isNotEmpty == true
              ? media.name!.trim()
              : _generateFileName(pageTitle, index, media.url, media.type);
          await downloadService.addDownloadTask(
            media.url,
            currentUrl,
            fileName: uniqueFileName,
            mediaType: mediaType,
          );
          if (!_isCurrentExtractRun(extractRunId)) return;
          addedCount++;
        }

        final audioCount = mediaItems
            .where((item) => item.type == ExtractedMediaType.audio)
            .length;
        final videoCount = mediaItems
            .where((item) => item.type == ExtractedMediaType.video)
            .length;
        final resultText = addedCount > 0
            ? '音频 $audioCount 个，视频 $videoCount 个，已添加 $addedCount 个下载任务并开始下载'
            : '音频 $audioCount 个，视频 $videoCount 个，都已在下载列表中';
        final existedText = existedCount > 0 ? '，跳过 $existedCount 个已存在任务' : '';

        Get.snackbar(
          '媒体链接提取成功',
          '$resultText$existedText',
          mainButton: TextButton(
            onPressed: () {
              _backToHomeAndSwitchTab(1);
            },
            child: const Text('前往下载页'),
          ),
        );
      } else {
        Get.snackbar('媒体链接提取', '未找到可下载的音频或视频链接');
      }
    } catch (e) {
      if (_isCurrentExtractRun(extractRunId)) {
        Get.snackbar('媒体链接提取失败', e.toString());
      }
    } finally {
      if (_isCurrentExtractRun(extractRunId)) {
        setState(() {
          _isExtractingMedia = false;
          _extractStatusText = '';
        });
      }
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

  void _handlePageUrlChanged(String? newUrl) {
    if (newUrl == null || newUrl.isEmpty || newUrl == url) return;
    url = newUrl;
    _cancelExtractFeedback();
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
                      child: Stack(
                    children: [
                      InAppWebView(
                        key: _webViewKey,
                        initialUrlRequest: URLRequest(url: WebUri(url ?? "")),
                        initialSettings: InAppWebViewSettings(
                          allowsBackForwardNavigationGestures: true,
                        ),
                        onWebViewCreated: (controller) {
                          _controller = controller;
                          _updateCanPop();
                        },
                        onLoadStop: (controller, url) async {
                          _handlePageUrlChanged(url?.toString());
                          // 更新标题（即使 URL 不变，也要更新 title）
                          _checkIfFavorite(url?.toString());
                          _updateCanPop();
                          _updatePageTitle();
                        },
                        onUpdateVisitedHistory:
                            (controller, url, androidIsReload) async {
                          _handlePageUrlChanged(url.toString());
                          _checkIfFavorite(url.toString());
                          // 延迟确保 controller 状态更新完成
                          Future.delayed(const Duration(milliseconds: 300),
                              () async {
                            _updateCanPop();
                            _updatePageTitle();
                          });
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
                      _buildExtractStatus(),
                      FloatingBall(
                        child: _buildFab(),
                      ),
                    ],
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建浮标
  Widget _buildFab() {
    return FloatingActionButton(
      onPressed: _handleExtract,
      tooltip: _isExtractingMedia ? '正在提取媒体' : '提取媒体',
      child: _isExtractingMedia
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.4,
              ),
            )
          : const Icon(Icons.download),
    );
  }

  Widget _buildExtractStatus() {
    if (!_isExtractingMedia || _extractStatusText.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      left: 16,
      right: 16,
      top: 16,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _extractStatusText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
