import 'package:flutter/material.dart';

class SwipeToDismissContainer extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDismiss;
  final double dismissThreshold; // 滑动触发阈值（像素）
  final bool enableOpacity; // 是否启用渐变透明效果
  final Duration animationDuration;

  const SwipeToDismissContainer({
    Key? key,
    required this.child,
    this.onDismiss,
    this.dismissThreshold = 150,
    this.enableOpacity = true,
    this.animationDuration = const Duration(milliseconds: 250),
  }) : super(key: key);

  @override
  State<SwipeToDismissContainer> createState() =>
      _SwipeToDismissContainerState();
}

class _SwipeToDismissContainerState extends State<SwipeToDismissContainer>
    with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;
  late AnimationController _controller;
  Animation<Offset>? _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    // 只允许右下方向移动
    final dx = details.delta.dx;
    final dy = details.delta.dy;
    if (dx >= 0 && dy >= 0) {
      setState(() {
        _offset += details.delta;
      });
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final distance = _offset.distance;

    if (distance > widget.dismissThreshold) {
      widget.onDismiss?.call();
    } else {
      // 回弹
      _animation = Tween<Offset>(
        begin: _offset,
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      );

      _controller
        ..duration = widget.animationDuration
        ..forward(from: 0);

      _animation!.addListener(() {
        setState(() {
          _offset = _animation!.value;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double opacity = 1.0;
    if (widget.enableOpacity) {
      opacity = (1.0 - (_offset.distance / (widget.dismissThreshold * 2)))
          .clamp(0.5, 1.0);
    }

    return GestureDetector(
      onPanUpdate: _handleDragUpdate,
      onPanEnd: _handleDragEnd,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: _offset,
          child: widget.child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
