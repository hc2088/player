import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../pages/download_list_page.dart';
import '../pages/favorite_list_page.dart';
import '../pages/home_page.dart';
import '../pages/video_inapp_web_detail_page.dart';
import '../pages/video_player_page.dart';
import '../pages/video_swiper_page.dart';

// 跳转到web页面，保留/home页面，避免重复web页面
// RouteHelper.toUnique('/web', arguments: {'url': fav.url}, untilRouteNames: ['/home']);
//
// // 跳转到下载页面，不保留任何页面（清空栈）
// RouteHelper.toAndRemoveAll('/downloadList');
//
// // 普通跳转，不处理路由栈
// RouteHelper.to('/favoriteList');
//
// // 返回
// RouteHelper.back();

class RouteHelper {
  static const String videoWebDetail = '/videoWebDetail';
  static const String downloadList = '/downloadList';
  static const String player = '/player';
  static const String favorite = '/favorite';
  static const String home = '/';
  static const String videoSwiper = '/video-swiper';

  static List<GetPage> routes = [
    GetPage(name: home, page: () => const HomePage()),
    GetPage(name: downloadList, page: () => const DownloadListPage()),
    GetPage(
      name: RouteHelper.videoWebDetail,
      page: () {
        final args = Get.arguments;
        final url =
            (args is Map && args['url'] != null) ? args['url'] as String : null;
        return VideoInAppWebDetailPage(defaultUrl: url);
      },
    ),
    GetPage(name: player, page: () => const VideoPlayerPage()),
    GetPage(name: favorite, page: () => const FavoriteListPage()),
    GetPage(name: videoSwiper, page: () => const VideoSwiperPage()),
  ];
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// 跳转到指定路径，并清除历史路由直到指定的某个页面为止（或保留第一个页面）。
  ///
  /// [path] 要跳转的路由路径。
  /// [arguments] 传递给目标页面的参数。
  /// [untilRouteNames] 指定允许保留的页面名称列表，
  /// 如果为空则默认保留第一个页面。
  static Future<void> toUnique(
    String path, {
    Map<String, dynamic>? arguments,
    List<String>? untilRouteNames,
  }) async {
    // 定义路由保留条件
    final predicate = (Route<dynamic> route) {
      // 如果提供了 untilRouteNames，则判断当前 route 是否在其中
      if (untilRouteNames != null && untilRouteNames.isNotEmpty) {
        return untilRouteNames.contains(route.settings.name);
      }
      // 否则，只保留第一个页面（即首页）
      return route.isFirst;
    };

    // 跳转到目标页面，并清除不满足 predicate 的所有路由
    await Get.offNamedUntil(path, predicate, arguments: arguments);
  }

  static Future<void> toAndRemoveAll(
    String path, {
    Map<String, dynamic>? arguments,
  }) async {
    await Get.offAllNamed(path, arguments: arguments);
  }

  static Future<void> to(
    String path, {
    Map<String, dynamic>? arguments,
  }) async {
    await Get.toNamed(path, arguments: arguments);
  }

  static void back() {
    if (navigatorKey.currentState?.canPop() ?? false) {
      navigatorKey.currentState?.pop();
    }
  }
}
