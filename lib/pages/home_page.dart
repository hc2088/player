// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../controllers/home_page_controller.dart';
import '../routes/route_helper.dart';
import 'favorite_list_page.dart';
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

  @override
  void initState() {
    super.initState();

    // 初始化当前 URL
    _initUrlFuture = _initCurrentUrl();
  }

  Future<void> _initCurrentUrl() async {
    _currentUrl = await AppConfig.getDefaultVideoUrl();
    _initPages();
    setState(() {});
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
    ];
  }

  void _onFavoriteItemTap(String url) async {
    Navigator.of(context).pop();

    // 更新当前URL，刷新WebView
    setState(() {
      _currentUrl = url;
      _initPages();
    });

    await AppConfig.setCustomHomePageUrl(url);

    final state = _videoPageKey.currentState;
    if (state != null) {
      state.reloadWebViewWithUrl(url);
    }
  }

  void _updateDrawerGesture() async {
    if (controller.currentTabIndex.value == 0) {
      // Web 页
      final state = _videoPageKey.currentState;
      if (state != null) {
        final canGoBack = await state.canGoBack();
        setState(() {
          _enableDrawerGesture = !canGoBack;
        });
      }
    } else {
      // 下载页，允许侧滑
      setState(() {
        _enableDrawerGesture = true;
      });
    }
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

        return Obx(() {
          // 每次 tab 切换都触发手势更新
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateDrawerGesture();
          });
          return Scaffold(
            key: _scaffoldKey,
            drawerEnableOpenDragGesture: _enableDrawerGesture,
            // 动态控制侧滑手势
            drawer: SizedBox(
              width: 200,
              child: Drawer(
                child: FavoriteListPage(
                  selectedUrl: _currentUrl,
                  onItemTap: _onFavoriteItemTap,
                  isDrawerMode: true,
                ),
              ),
            ),
            body: IndexedStack(
              index: controller.currentTabIndex.value,
              children: _pages,
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: controller.currentTabIndex.value,
              onTap: controller.switchToTab,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.web), label: '网页'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.download), label: '下载'),
              ],
            ),
          );
        });
      },
    );
  }
}
