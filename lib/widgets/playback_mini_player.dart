import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/download_task.dart';
import '../routes/route_helper.dart';
import '../services/playback_service.dart';

/// 监听播放状态，将迷你条插入根 Navigator 的 Overlay（Tooltip 等需要 Overlay）。
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
  OverlayEntry? _overlayEntry;
  Worker? _visibilityWorker;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<PlaybackService>()) return;

    final service = Get.find<PlaybackService>();
    _visibilityWorker = everAll(
      [service.showMiniPlayer, service.hasSession],
      (_) => _syncMiniPlayerOverlay(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncMiniPlayerOverlay();
    });
  }

  @override
  void dispose() {
    _visibilityWorker?.dispose();
    _removeOverlayEntry();
    super.dispose();
  }

  void _syncMiniPlayerOverlay() {
    if (!Get.isRegistered<PlaybackService>()) return;

    final service = Get.find<PlaybackService>();
    final visible =
        service.showMiniPlayer.value && service.hasSession.value;

    if (visible) {
      _insertOverlayEntry();
    } else {
      _removeOverlayEntry();
    }
  }

  void _insertOverlayEntry() {
    final overlay = RouteHelper.navigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _insertOverlayEntry();
      });
      return;
    }

    _overlayEntry ??= OverlayEntry(
      builder: (context) => const _PlaybackMiniPlayerBar(),
    );

    if (_overlayEntry!.mounted) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    overlay.insert(_overlayEntry!);
  }

  void _removeOverlayEntry() {
    if (_overlayEntry?.mounted ?? false) {
      _overlayEntry!.remove();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PlaybackMiniPlayerBar extends StatelessWidget {
  const _PlaybackMiniPlayerBar();

  double _bottomOffset(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final onHome = Get.currentRoute == RouteHelper.home;
    final navHeight = onHome ? kBottomNavigationBarHeight : 0.0;
    return safeBottom + navHeight + 8;
  }

  @override
  Widget build(BuildContext context) {
    final service = Get.find<PlaybackService>();

    return Obx(() {
      if (!service.showMiniPlayer.value || !service.hasSession.value) {
        return const SizedBox.shrink();
      }

      final isAudio = service.mediaType.value == DownloadMediaType.audio;
      final playing = service.isPlaying.value;
      final title = service.title.value;

      return Positioned(
        left: 12,
        right: 12,
        bottom: _bottomOffset(context),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: service.openFullPlayer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isAudio ? Icons.audiotrack : Icons.play_circle_outline,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: playing ? '暂停' : '播放',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    onPressed: service.toggle,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    tooltip: '停止',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    onPressed: service.stop,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
