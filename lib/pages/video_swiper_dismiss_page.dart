import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../widgets/swipe_to_dismiss_container.dart';
import 'video_swiper_page.dart'; // 如果你想直接用现成逻辑，也可以内嵌

class VideoSwiperDismissPage extends StatelessWidget {
  const VideoSwiperDismissPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true, // 允许物理返回键
      onPopInvokedWithResult: (didPop, result) {
        // didPop = 是否已弹出
        // result = Navigator.pop(result) 时传递的值
        if (!didPop) {
          // 页面还没关闭，这里可以做一些拦截或处理
        }
      },
      child: SwipeToDismissContainer(
        onDismiss: () => Get.back(),
        child: const VideoSwiperPage(),
      ),
    );
  }
}
