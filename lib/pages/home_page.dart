// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../controllers/home_page_controller.dart';
import '../routes/route_helper.dart';
import 'video_inapp_web_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final HomePageController controller = Get.put(HomePageController());

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _pages = [
      FutureBuilder<String>(
        future: AppConfig.getDefaultVideoUrl(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return VideoInAppWebDetailPage(defaultUrl: snapshot.data!);
        },
      ),
      RouteHelper.routes
          .firstWhere((element) => element.name == RouteHelper.downloadList)
          .page(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => Scaffold(
          body: IndexedStack(
            index: controller.currentTabIndex.value,
            children: _pages,
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: controller.currentTabIndex.value,
            onTap: controller.switchToTab,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.web), label: '网页'),
              BottomNavigationBarItem(icon: Icon(Icons.download), label: '下载'),
            ],
          ),
        ));
  }
}
