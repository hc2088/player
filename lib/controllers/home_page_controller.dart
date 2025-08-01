import 'package:get/get.dart';

class HomePageController extends GetxController {
  /// 当前底部导航栏 tab 索引
  RxInt currentTabIndex = 0.obs;

  /// 切换 tab
  void switchToTab(int index) {
    currentTabIndex.value = index;
  }
}
