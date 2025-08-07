import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EdgeDraggableFloatingActionButton extends StatefulWidget {
  final Widget child;
  final String tag;

  const EdgeDraggableFloatingActionButton({
    Key? key,
    required this.child,
    required this.tag,
  }) : super(key: key);

  @override
  State<EdgeDraggableFloatingActionButton> createState() =>
      _EdgeDraggableFloatingActionButtonState();
}

class _EdgeDraggableFloatingActionButtonState
    extends State<EdgeDraggableFloatingActionButton> {
  Offset _offset = const Offset(100, 500);
  Offset _dragOffsetFromOrigin = Offset.zero;
  bool _loaded = false;

  static const _margin = 16.0;
  static const _fabSize = 56.0;

  final GlobalKey _containerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble('${widget.tag}_dx');
    final dy = prefs.getDouble('${widget.tag}_dy');

    if (dx != null && dy != null) {
      setState(() {
        _offset = Offset(dx, dy);
      });
    }

    setState(() {
      _loaded = true;
    });
  }

  Future<void> _savePosition(Offset offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${widget.tag}_dx', offset.dx);
    await prefs.setDouble('${widget.tag}_dy', offset.dy);
  }

  void _handleDragEnd(DraggableDetails details) {
    final renderBox =
    _containerKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox == null) return;

    final localOffset = renderBox.globalToLocal(details.offset);

    double dx = localOffset.dx - _dragOffsetFromOrigin.dx;
    double dy = localOffset.dy - _dragOffsetFromOrigin.dy;

    final maxWidth = renderBox.size.width;
    final maxHeight = renderBox.size.height;

    dy = dy.clamp(_margin, maxHeight - _fabSize - _margin);
    dx = dx < maxWidth / 2 ? _margin : maxWidth - _fabSize - _margin;

    final newOffset = Offset(dx, dy);

    setState(() {
      _offset = newOffset;
    });

    _savePosition(newOffset);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: Listener(
        onPointerDown: (event) {
          _dragOffsetFromOrigin = event.localPosition;
        },
        child: Container(
          key: _containerKey,
          child: Draggable(
            feedback: widget.child,
            childWhenDragging: const SizedBox.shrink(),
            onDragEnd: _handleDragEnd,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
