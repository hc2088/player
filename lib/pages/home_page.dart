// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../controllers/home_page_controller.dart';
import '../routes/route_helper.dart';
import '../services/local_media_service.dart';
import '../widgets/password_input_dialog.dart';
import 'favorite_list_page.dart';
import 'local_media_list_page.dart';
import 'video_inapp_web_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final HomePageController controller = Get.put(HomePageController());
  final GlobalKey<VideoInAppWebDetailPageState> _videoPageKey =
      GlobalKey<VideoInAppWebDetailPageState>();

  bool _enableDrawerGesture = true;

  String? _currentUrl;
  late Future<void> _initUrlFuture;

  late List<Widget> _pages;
  bool _localEntryVisible = false;
  String? _localUnlockPassword;
  int _hiddenTapCount = 0;
  DateTime? _lastHiddenTapAt;
  bool _unlockDialogShowing = false;

  @override
  void initState() {
    super.initState();

    // 初始化当前 URL
    _initUrlFuture = _initCurrentUrl();

    ever(controller.canGoBack, (bool value) {
      if (controller.currentTabIndex.value == 0) {
        setState(() {
          _enableDrawerGesture = !value;
        });
      } else {
        setState(() {
          _enableDrawerGesture = true;
        });
      }
    });

    ever(controller.currentTabIndex, (int value) {
      if (controller.currentTabIndex.value == 0) {
        setState(() {
          _enableDrawerGesture = !controller.canGoBack.value;
        });
      } else {
        setState(() {
          _enableDrawerGesture = true;
        });
      }
    });
  }

  Future<void> _initCurrentUrl() async {
    _currentUrl = await AppConfig.getDefaultVideoUrl();
    _initPages();
  }

  void _initPages() {
    _pages = [
      // 这里不使用 FutureBuilder，而是确保 _currentUrl 已准备好
      if (_currentUrl != null)
        VideoInAppWebDetailPage(
          key: _videoPageKey,
          defaultUrl: _currentUrl!,
          onOpenDrawer: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        )
      else
        const Center(child: CircularProgressIndicator()),
      RouteHelper.routes
          .firstWhere((element) => element.name == RouteHelper.downloadList)
          .page(),
      if (_localEntryVisible)
        LocalMediaListPage(
          initialPassword: _localUnlockPassword,
          onHideEntry: _hideLocalEntry,
        ),
    ];
  }

  void _onFavoriteItemTap(String url) async {
    final targetUrl = AppConfig.normalizeWebUrl(url);
    if (targetUrl.isEmpty) {
      _showMessage('收藏地址为空');
      return;
    }

    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    await AppConfig.setCustomHomePageUrl(targetUrl);
    if (!mounted) return;

    // 更新当前 URL，刷新 WebView。这里直接切换 Tab，避免触发双击 Tab 的默认首页刷新逻辑。
    setState(() {
      _currentUrl = targetUrl;
      _initPages();
    });

    controller.currentTabIndex.value = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _videoPageKey.currentState?.reloadWebViewWithUrl(targetUrl);
    });
  }

  void _handleNavigationTap(int index) {
    if (index == 1) {
      _recordHiddenTap();
    }

    controller.switchToTab(index);
  }

  void _recordHiddenTap() {
    final now = DateTime.now();
    if (_lastHiddenTapAt == null ||
        now.difference(_lastHiddenTapAt!) > const Duration(seconds: 4)) {
      _hiddenTapCount = 0;
    }

    _lastHiddenTapAt = now;
    _hiddenTapCount++;

    if (_hiddenTapCount >= 10) {
      _hiddenTapCount = 0;
      if (_localEntryVisible) {
        _hideLocalEntry();
      } else {
        _showUnlockDialog();
      }
    }
  }

  void _hideLocalEntry() {
    setState(() {
      _localEntryVisible = false;
      _localUnlockPassword = null;
      _hiddenTapCount = 0;
      _lastHiddenTapAt = null;
      _initPages();
    });

    controller.switchToTab(1);
    _showMessage('本地入口已隐藏');
  }

  Future<void> _showUnlockDialog() async {
    if (_unlockDialogShowing || _localEntryVisible) return;

    _unlockDialogShowing = true;
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PasswordInputDialog(title: '访问验证'),
    );
    _unlockDialogShowing = false;

    if (password == null || !mounted) return;

    if (!LocalMediaService.isUnlockPassword(password)) {
      _showMessage('密码有误');
      return;
    }

    setState(() {
      _localEntryVisible = true;
      _localUnlockPassword = LocalMediaService.normalizePassword(password);
      _initPages();
    });

    _showMessage('本地入口已显示');
  }

  void _showMessage(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initUrlFuture,
      builder: (context, snapshot) {
        // 等待初始化完成
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final drawerWidth = constraints.maxWidth * 2 / 3;
            return Obx(() {
              final currentIndex = controller.currentTabIndex.value;
              final safeIndex =
                  currentIndex >= _pages.length ? 0 : currentIndex;
              final navigationItems = [
                const BottomNavigationBarItem(
                    icon: Icon(Icons.web), label: '网页'),
                const BottomNavigationBarItem(
                    icon: Icon(Icons.download), label: '下载'),
                if (_localEntryVisible)
                  const BottomNavigationBarItem(
                      icon: Icon(Icons.folder), label: '本地'),
              ];

              return Scaffold(
                key: _scaffoldKey,
                drawerEnableOpenDragGesture: _enableDrawerGesture,
                // 动态控制侧滑手势
                drawer: SizedBox(
                  width: drawerWidth,
                  child: Drawer(
                    child: FavoriteListPage(
                      selectedUrl: _currentUrl,
                      onItemTap: _onFavoriteItemTap,
                      isDrawerMode: true,
                    ),
                  ),
                ),
                body: IndexedStack(
                  index: safeIndex,
                  children: _pages,
                ),
                bottomNavigationBar: BottomNavigationBar(
                  currentIndex: safeIndex,
                  onTap: _handleNavigationTap,
                  items: navigationItems,
                ),
              );
            });
          },
        );
      },
    );
  }
}
