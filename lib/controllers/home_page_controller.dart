import 'package:get/get.dart';

class HomePageController extends GetxController {
  var currentTabIndex = 0.obs;

  // 用RxBool做事件开关
  var webReloadEvent = false.obs;

  var canGoBack = true.obs;

  // 保存上次点击时间和索引
  int? _lastTapIndex;
  DateTime? _lastTapTime;

  void switchToTab(int index) {
    final now = DateTime.now();

    if (_lastTapIndex == index &&
        now.difference(_lastTapTime ?? DateTime(0)) <
            Duration(milliseconds: 300)) {
      // 双击同一个tab
      if (index == 0) {
        // 发送刷新首页通知
        refreshWebHome(tips: "网页 Tab 被双击，已返回默认首页");
      }
    } else {
      currentTabIndex.value = index;
    }

    _lastTapIndex = index;
    _lastTapTime = now;
  }

  void refreshWebHome({String? tips}) {
    if (tips?.isNotEmpty == true) {
      Get.snackbar('提示', tips!);
    }
    Get.find<HomePageController>().webReloadEvent.value = !webReloadEvent.value;
  }
}
