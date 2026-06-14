import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'routes/route_helper.dart';
import 'services/app_control_service.dart';
import 'services/download_service.dart';
import 'services/favorite_service.dart';
import 'services/playback_service.dart';
import 'utils/screen_info.dart';
import 'widgets/app_privacy_gate.dart';
import 'widgets/floating_ball.dart';
import 'widgets/playback_mini_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先同步注册实例
  final favoriteService = FavoriteService();
  Get.put<FavoriteService>(favoriteService);

  // 异步初始化，不阻塞启动
  favoriteService.init();

  await GetStorage.init();

  // 这里注入 DownloadService，整个应用都能用
  Get.put(DownloadService());
  Get.put(PlaybackService(), permanent: true);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '视频下载播放示例',
      navigatorKey: RouteHelper.navigatorKey,
      initialRoute: '/',
      getPages: RouteHelper.routes,
      builder: (context, child) {
        return ScreenInfoProvider(
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppPrivacyGate(
                child: PlaybackMiniPlayerHost(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
              FloatingBall(
                storageKeyPrefix: 'exitAppFloatingBall',
                initialAnchor: FloatingBallAnchor.leftBottom,
                child: Semantics(
                  label: '退出应用',
                  button: true,
                  child: FloatingActionButton(
                    heroTag: 'exitAppButton',
                    backgroundColor: Colors.redAccent,
                    onPressed: AppControlService.exitApp,
                    child: const Icon(Icons.power_settings_new),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
