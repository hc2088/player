import 'package:flutter/material.dart';

/// 屏幕信息模型
class ScreenInfo {
  final Size screenSize;
  final Orientation orientation;
  final double statusBarHeight;
  final double appBarHeight;
  final double bottomBarHeight;
  final double bottomSafeArea;

  const ScreenInfo({
    required this.screenSize,
    required this.orientation,
    required this.statusBarHeight,
    this.appBarHeight = kToolbarHeight,
    this.bottomBarHeight = kBottomNavigationBarHeight,
    required this.bottomSafeArea,
  });

  double get width => screenSize.width;

  double get height => screenSize.height;

  bool get isPortrait => orientation == Orientation.portrait;

  double get usableHeight =>
      height -
      statusBarHeight -
      appBarHeight -
      bottomBarHeight -
      bottomSafeArea;
}

/// 全局服务：无 context 场景下访问屏幕信息
class ScreenInfoService {
  static final ScreenInfoService _instance = ScreenInfoService._internal();

  factory ScreenInfoService() => _instance;

  ScreenInfoService._internal();

  ScreenInfo? _info;

  void update(ScreenInfo info) {
    _info = info;
  }

  ScreenInfo get info {
    if (_info == null) {
      throw Exception(
        "ScreenInfoService 未初始化。请确保 ScreenInfoProvider 已包裹在 Widget 树中。",
      );
    }
    return _info!;
  }

  bool get isInitialized => _info != null;
}

/// Provider：监听屏幕变化并分发更新
class ScreenInfoProvider extends StatefulWidget {
  final Widget child;

  const ScreenInfoProvider({super.key, required this.child});

  @override
  State<ScreenInfoProvider> createState() => _ScreenInfoProviderState();

  /// context 下获取屏幕信息
  static ScreenInfo of(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<_ScreenInfoInherited>();
    assert(inherited != null, 'No ScreenInfoProvider found in context');
    return inherited!.data;
  }
}

class _ScreenInfoProviderState extends State<ScreenInfoProvider>
    with WidgetsBindingObserver {
  ScreenInfo? _info;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    //  构建完成后手动初始化一次
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateScreenInfo();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _updateScreenInfo();
  }

  void _updateScreenInfo() {
    final mq = MediaQuery.of(context);

    final info = ScreenInfo(
      screenSize: mq.size,
      orientation: mq.orientation,
      statusBarHeight: mq.padding.top,
      bottomSafeArea: mq.padding.bottom,
    );

    ScreenInfoService().update(info);

    if (!mounted) return;
    setState(() => _info = info);
  }

  @override
  Widget build(BuildContext context) {
    //  处理首次构建时 _info 为空
    if (_info == null) {
      final mq = MediaQuery.of(context);
      _info = ScreenInfo(
        screenSize: mq.size,
        orientation: mq.orientation,
        statusBarHeight: mq.padding.top,
        bottomSafeArea: mq.padding.bottom,
      );
      ScreenInfoService().update(_info!);
    }

    return _ScreenInfoInherited(
      data: _info!,
      child: widget.child,
    );
  }
}

class _ScreenInfoInherited extends InheritedWidget {
  final ScreenInfo data;

  const _ScreenInfoInherited({
    required Widget child,
    required this.data,
  }) : super(child: child);

  @override
  bool updateShouldNotify(covariant _ScreenInfoInherited oldWidget) =>
      data != oldWidget.data;
}

/// 扩展：在任意 BuildContext 中快速访问
extension ScreenInfoExtension on BuildContext {
  ScreenInfo get screenInfo => ScreenInfoProvider.of(this);
}
