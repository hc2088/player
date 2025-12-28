import 'package:flutter/material.dart';
import 'package:player/utils/screen_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FloatingBall extends StatefulWidget {
  final Widget child;

  const FloatingBall({Key? key, required this.child}) : super(key: key);

  @override
  State<FloatingBall> createState() => _FloatingBallState();
}

class _FloatingBallState extends State<FloatingBall>
    with TickerProviderStateMixin {
  static const _prefKeyX = 'floatingBallX';
  static const _prefKeyY = 'floatingBallY';

  Offset _offset = Offset.zero;
  bool _initialized = false;

  late AnimationController _animController;
  late Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();

    _animController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 300))
          ..addListener(() {
            setState(() {
              _offset = _animation.value;
            });
          });

    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble(_prefKeyX);
    final dy = prefs.getDouble(_prefKeyY);

    if (dx != null && dy != null) {
      setState(() {
        _offset = Offset(dx, dy);
        _initialized = true;
      });
    } else {
      // 默认右下角，等组件build后取屏幕大小更新位置
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final width = context.screenInfo.width;
        final height = context.screenInfo.usableHeight;
        const fabSize = 56.0;
        const margin = 16.0;
        setState(() {
          _offset = Offset(width - fabSize - margin, height - fabSize - margin);
          _initialized = true;
        });
      });
    }
  }

  Future<void> _savePosition(Offset offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKeyX, offset.dx);
    await prefs.setDouble(_prefKeyY, offset.dy);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _offset += details.delta;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final width = context.screenInfo.width;
    final height = context.screenInfo.usableHeight;
    const fabSize = 56.0;
    const margin = 16.0;

    double dx = _offset.dx;
    double dy = _offset.dy;

    // 边界限制
    dx = dx.clamp(margin, width - fabSize - margin);
    dy = dy.clamp(margin, height - fabSize - margin);

    // 吸边逻辑（左右吸边）
    if (dx + fabSize / 2 < width / 2) {
      dx = margin;
    } else {
      dx = width - fabSize - margin;
    }

    final target = Offset(dx, dy);

    _animation = Tween<Offset>(begin: _offset, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _animController.forward(from: 0);

    _savePosition(target);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      // 等待初始化位置，不然会闪烁或者没位置
      return SizedBox.shrink();
    }

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: _onDragUpdate,
        onPanEnd: _onDragEnd,
        child: widget.child,
      ),
    );
  }
}
