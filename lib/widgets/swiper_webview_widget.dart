import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SwiperWebViewWidget extends StatefulWidget {
  final WebViewController controller;

  const SwiperWebViewWidget({super.key, required this.controller});

  @override
  State<SwiperWebViewWidget> createState() => _SwiperWebViewWidgetState();
}

class _SwiperWebViewWidgetState extends State<SwiperWebViewWidget> {
  double _startX = 0;
  bool _maybeBackSwipe = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _startX = event.position.dx;
        _maybeBackSwipe = _startX < 50; // 仅在左边缘检测
      },
      onPointerMove: (event) async {
        if (!_maybeBackSwipe) return;
        final deltaX = event.position.dx - _startX;
        if (deltaX > 30) {
          if (await widget.controller.canGoBack()) {
            widget.controller.goBack();
            _maybeBackSwipe = false;
          }
        }
      },
      child: WebViewWidget(controller: widget.controller),
    );
  }
}
