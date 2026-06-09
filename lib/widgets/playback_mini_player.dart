import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/download_task.dart';
import '../routes/route_helper.dart';
import '../services/playback_service.dart';

/// 监听播放状态，将迷你条放在根页面 Stack 顶层。
class PlaybackMiniPlayerHost extends StatefulWidget {
  const PlaybackMiniPlayerHost({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<PlaybackMiniPlayerHost> createState() => _PlaybackMiniPlayerHostState();
}

class _PlaybackMiniPlayerHostState extends State<PlaybackMiniPlayerHost> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        const _PlaybackMiniPlayerBar(),
      ],
    );
  }
}

class _PlaybackMiniPlayerBar extends StatefulWidget {
  const _PlaybackMiniPlayerBar();

  @override
  State<_PlaybackMiniPlayerBar> createState() => _PlaybackMiniPlayerBarState();
}

class _PlaybackMiniPlayerBarState extends State<_PlaybackMiniPlayerBar> {
  static const double _margin = 12;
  static const double _collapsedSize = 56;
  static const double _expandedHeight = 64;
  static const double _maxExpandedWidth = 420;
  static const Duration _animationDuration = Duration(milliseconds: 260);

  Offset? _collapsedOffset;
  bool _expanded = false;
  bool _dragging = false;

  double _bottomOffset(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final onHome = Get.currentRoute == RouteHelper.home;
    final navHeight = onHome ? kBottomNavigationBarHeight : 0.0;
    return safeBottom + navHeight + 8;
  }

  double _topLimit(BuildContext context) {
    return MediaQuery.paddingOf(context).top + 8;
  }

  double _maxTop(
    BuildContext context,
    BoxConstraints constraints,
    double height,
  ) {
    return math.max(
      _topLimit(context),
      constraints.maxHeight - _bottomOffset(context) - height,
    );
  }

  double _clampDouble(double value, double min, double max) {
    if (max < min) return min;
    return value.clamp(min, max).toDouble();
  }

  Offset _defaultCollapsedOffset(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final x = constraints.maxWidth - _margin - _collapsedSize;
    final y = constraints.maxHeight - _bottomOffset(context) - _collapsedSize;
    return Offset(
      _clampDouble(x, _margin, constraints.maxWidth - _margin - _collapsedSize),
      _clampDouble(
          y, _topLimit(context), _maxTop(context, constraints, _collapsedSize)),
    );
  }

  Offset _currentCollapsedOffset(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    return _clampCollapsedOffset(
      context,
      constraints,
      _collapsedOffset ?? _defaultCollapsedOffset(context, constraints),
    );
  }

  Offset _clampCollapsedOffset(
    BuildContext context,
    BoxConstraints constraints,
    Offset offset,
  ) {
    return Offset(
      _clampDouble(
        offset.dx,
        _margin,
        constraints.maxWidth - _margin - _collapsedSize,
      ),
      _clampDouble(
        offset.dy,
        _topLimit(context),
        _maxTop(context, constraints, _collapsedSize),
      ),
    );
  }

  Offset _snapOffsetToEdge(
    BuildContext context,
    BoxConstraints constraints,
    Offset offset,
  ) {
    final clamped = _clampCollapsedOffset(context, constraints, offset);
    final snapRight =
        clamped.dx + _collapsedSize / 2 >= constraints.maxWidth / 2;
    final x =
        snapRight ? constraints.maxWidth - _margin - _collapsedSize : _margin;
    return Offset(x, clamped.dy);
  }

  bool _isRightEdge(Offset offset, BoxConstraints constraints) {
    return offset.dx + _collapsedSize / 2 >= constraints.maxWidth / 2;
  }

  Rect _playerRect(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final collapsed = _currentCollapsedOffset(context, constraints);
    if (!_expanded) {
      return Rect.fromLTWH(
        collapsed.dx,
        collapsed.dy,
        _collapsedSize,
        _collapsedSize,
      );
    }

    final width = math.min(
      _maxExpandedWidth,
      math.max(_collapsedSize, constraints.maxWidth - _margin * 2),
    );
    final rightEdge = _isRightEdge(collapsed, constraints);
    final x = rightEdge ? constraints.maxWidth - _margin - width : _margin;
    final y = _clampDouble(
      collapsed.dy - (_expandedHeight - _collapsedSize) / 2,
      _topLimit(context),
      _maxTop(context, constraints, _expandedHeight),
    );

    return Rect.fromLTWH(x, y, width, _expandedHeight);
  }

  void _collapse() {
    if (!_expanded) return;
    setState(() {
      _expanded = false;
    });
  }

  void _expand() {
    if (_expanded) return;
    setState(() {
      _expanded = true;
    });
  }

  void _collapseWhenHidden() {
    if (!_expanded) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_expanded) return;
      setState(() {
        _expanded = false;
      });
    });
  }

  void _onPanStart() {
    setState(() {
      _dragging = true;
      _expanded = false;
    });
  }

  void _onPanUpdate(
    BuildContext context,
    BoxConstraints constraints,
    DragUpdateDetails details,
  ) {
    final current = _currentCollapsedOffset(context, constraints);
    setState(() {
      _collapsedOffset = _clampCollapsedOffset(
        context,
        constraints,
        current + details.delta,
      );
    });
  }

  void _onPanEnd(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final current = _currentCollapsedOffset(context, constraints);
    setState(() {
      _dragging = false;
      _collapsedOffset = _snapOffsetToEdge(context, constraints, current);
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = Get.find<PlaybackService>();

    return Obx(() {
      if (!service.showMiniPlayer.value || !service.hasSession.value) {
        _collapseWhenHidden();
        return const SizedBox.shrink();
      }

      final isAudio = service.mediaType.value == DownloadMediaType.audio;
      final playing = service.isPlaying.value;
      final title = service.title.value;

      return Positioned.fill(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rect = _playerRect(context, constraints);

            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_expanded,
                    child: AnimatedOpacity(
                      duration: _animationDuration,
                      curve: Curves.easeOut,
                      opacity: _expanded ? 1 : 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _collapse,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.34),
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: _dragging ? Duration.zero : _animationDuration,
                  curve: Curves.easeOutBack,
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _expanded ? null : _expand,
                    onPanStart: (_) => _onPanStart(),
                    onPanUpdate: (details) =>
                        _onPanUpdate(context, constraints, details),
                    onPanEnd: (_) => _onPanEnd(context, constraints),
                    onPanCancel: () => _onPanEnd(context, constraints),
                    child: AnimatedScale(
                      duration: _animationDuration,
                      curve: Curves.easeOut,
                      scale: _dragging ? 1.06 : 1,
                      child: _MiniPlayerSurface(
                        expanded: _expanded,
                        isAudio: isAudio,
                        playing: playing,
                        title: title,
                        onOpenFullPlayer: service.openFullPlayer,
                        onToggle: service.toggle,
                        onStop: service.stop,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    });
  }
}

class _MiniPlayerSurface extends StatelessWidget {
  const _MiniPlayerSurface({
    required this.expanded,
    required this.isAudio,
    required this.playing,
    required this.title,
    required this.onOpenFullPlayer,
    required this.onToggle,
    required this.onStop,
  });

  final bool expanded;
  final bool isAudio;
  final bool playing;
  final String title;
  final VoidCallback onOpenFullPlayer;
  final VoidCallback onToggle;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      elevation: expanded ? 12 : 8,
      color: expanded
          ? colorScheme.surfaceContainerHighest
          : colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(expanded ? 16 : 18),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: expanded,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              opacity: expanded ? 0 : 1,
              child: _CollapsedMiniPlayerIcon(isAudio: isAudio),
            ),
          ),
          IgnorePointer(
            ignoring: !expanded,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              opacity: expanded ? 1 : 0,
              child: ClipRect(
                child: _ExpandedMiniPlayerContent(
                  isAudio: isAudio,
                  playing: playing,
                  title: title,
                  onOpenFullPlayer: onOpenFullPlayer,
                  onToggle: onToggle,
                  onStop: onStop,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedMiniPlayerIcon extends StatelessWidget {
  const _CollapsedMiniPlayerIcon({
    required this.isAudio,
  });

  final bool isAudio;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        isAudio ? Icons.audiotrack : Icons.play_circle_outline,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        size: 28,
      ),
    );
  }
}

class _ExpandedMiniPlayerContent extends StatelessWidget {
  const _ExpandedMiniPlayerContent({
    required this.isAudio,
    required this.playing,
    required this.title,
    required this.onOpenFullPlayer,
    required this.onToggle,
    required this.onStop,
  });

  final bool isAudio;
  final bool playing;
  final String title;
  final VoidCallback onOpenFullPlayer;
  final VoidCallback onToggle;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 220) {
          return _CollapsedMiniPlayerIcon(isAudio: isAudio);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isAudio ? Icons.audiotrack : Icons.play_circle_outline,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onOpenFullPlayer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAudio ? '音频播放中' : '视频播放中',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                onPressed: onToggle,
                icon: Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  semanticLabel: playing ? '暂停' : '播放',
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                onPressed: onStop,
                icon: const Icon(
                  Icons.close,
                  semanticLabel: '停止',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
