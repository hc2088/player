import 'dart:io';

import 'package:blur/blur.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';

import '../models/download_task.dart';
import '../services/download_service.dart';
import '../services/playback_service.dart';
import '../routes/route_helper.dart';

class DownloadListPage extends StatefulWidget {
  const DownloadListPage({super.key});

  @override
  State<DownloadListPage> createState() => _DownloadListPageState();
}

class _DownloadListPageState extends State<DownloadListPage> {
  final DownloadService _downloadService = Get.find<DownloadService>();
  final PlaybackService _playbackService = Get.find<PlaybackService>();

  static const double _cardRadius = 8;

  String _sourceDomain(DownloadTask task) {
    final candidates = [
      task.originPageUrl,
      task.url,
    ];

    for (final candidate in candidates) {
      final host = _hostFromUrl(candidate);
      if (host != null) return host;
    }

    return '未知来源';
  }

  String? _hostFromUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.hasPort ? '${parsed.host}:${parsed.port}' : parsed.host;
    }

    final withScheme = Uri.tryParse('https://$trimmed');
    if (withScheme != null && withScheme.host.isNotEmpty) {
      return withScheme.hasPort
          ? '${withScheme.host}:${withScheme.port}'
          : withScheme.host;
    }

    return null;
  }

  Widget _buildSourceDomain(DownloadTask task) {
    return Row(
      children: [
        const Icon(
          Icons.public,
          size: 14,
          color: Colors.blueGrey,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _sourceDomain(task),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.blueGrey,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  int _columnCount(double width) {
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  List<MapEntry<int, DownloadTask>> _entriesForType(
    List<DownloadTask> tasks,
    DownloadMediaType mediaType,
  ) {
    return tasks
        .asMap()
        .entries
        .where((entry) => entry.value.mediaType == mediaType)
        .toList();
  }

  String _statusLabel(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return '等待';
      case DownloadStatus.downloading:
        return '下载中';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return '失败';
      case DownloadStatus.canceled:
        return '已取消';
    }
  }

  Color _statusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.downloading:
        return Colors.blueAccent;
      case DownloadStatus.failed:
        return Colors.redAccent;
      case DownloadStatus.canceled:
        return Colors.orange;
      case DownloadStatus.pending:
        return Colors.blueGrey;
    }
  }

  String _progressText(DownloadTask task) {
    final progress = task.status == DownloadStatus.completed
        ? 1.0
        : task.progress.clamp(0.0, 0.999);
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  void _openTask(DownloadTask task, int index) {
    if (task.mediaType == DownloadMediaType.video) {
      final filePath = task.filePath;
      if (filePath != null &&
          filePath.isNotEmpty &&
          _playbackService.isSameSession(filePath)) {
        _playbackService.openFullPlayer();
        return;
      }

      Get.toNamed(RouteHelper.videoSwiper, arguments: {'initialIndex': index});
      return;
    }

    if (task.status == DownloadStatus.completed && task.filePath != null) {
      Get.toNamed(
        RouteHelper.player,
        arguments: {
          'path': task.filePath,
          'title': task.fileName ?? '音频',
          'mediaType': DownloadMediaType.audio,
        },
      );
      return;
    }

    _showPageSnack('音频尚未下载完成，当前状态：${_statusLabel(task.status)}');
  }

  void _showPageSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }

  Widget _buildTaskCard(DownloadTask task, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAudio = task.mediaType == DownloadMediaType.audio;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(_cardRadius),
        onTap: () => _openTask(task, index),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isAudio) _buildAudioSummary(task) else _buildVideoPreview(task),
            if (!isAudio) _buildTitle(task),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: _buildSourceDomain(task),
            ),
            _buildStatusArea(task),
            _buildActions(task),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioSummary(DownloadTask task) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.audiotrack,
              color: colorScheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '音频',
                  style: TextStyle(
                    color: Colors.blueGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  task.fileName ?? task.url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview(DownloadTask task) {
    final hasThumbnail =
        task.thumbnailPath != null && File(task.thumbnailPath!).existsSync();

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.grey[300],
        child: hasThumbnail
            ? Image.file(
                File(task.thumbnailPath!),
                fit: BoxFit.cover,
              ).blurred(
                blur: 20,
                blurColor: Colors.black26,
                overlay: Container(
                  alignment: Alignment.center,
                  child: Image.file(
                    File(task.thumbnailPath!),
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              )
            : const Icon(
                Icons.videocam_off_outlined,
                size: 48,
                color: Colors.white54,
              ),
      ),
    );
  }

  Widget _buildTitle(DownloadTask task) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Text(
        task.fileName ?? task.url,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _buildStatusArea(DownloadTask task) {
    final statusColor = _statusColor(task.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  _statusLabel(task.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                task.mediaType == DownloadMediaType.audio ? '音频' : '视频',
                style: const TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(value: task.progress),
                ),
                const SizedBox(width: 8),
                Text(
                  _progressText(task),
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(DownloadTask task) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '打开原网页',
            icon: const Icon(Icons.language, color: Colors.blueAccent),
            onPressed: () {
              final url =
                  task.originPageUrl.isNotEmpty ? task.originPageUrl : task.url;
              Get.toNamed(RouteHelper.videoWebDetail, arguments: {'url': url});
            },
          ),
          const Spacer(),
          if (task.status != DownloadStatus.completed &&
              task.status != DownloadStatus.downloading)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '重新下载',
              icon: const Icon(Icons.refresh, color: Colors.orange),
              onPressed: () => _downloadService.retryDownload(task),
            ),
          if (task.status == DownloadStatus.downloading)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '强制重新下载',
              icon: const Icon(Icons.restart_alt, color: Colors.orange),
              onPressed: () => _downloadService.forceRetryDownload(task),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '取消/删除任务',
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed: () => _downloadService.removeTask(task),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskGrid({
    required List<MapEntry<int, DownloadTask>> entries,
    required String emptyText,
  }) {
    if (entries.isEmpty) {
      return Center(child: Text(emptyText));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return MasonryGridView.count(
          crossAxisCount: _columnCount(constraints.maxWidth),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          itemCount: entries.length,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _buildTaskCard(entry.value, entry.key);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('下载列表'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Obx(() {
              final tasks = _downloadService.tasks;
              final videoCount = tasks
                  .where((task) => task.mediaType == DownloadMediaType.video)
                  .length;
              final audioCount = tasks
                  .where((task) => task.mediaType == DownloadMediaType.audio)
                  .length;

              return TabBar(
                tabs: [
                  Tab(
                    icon: const Icon(Icons.movie_outlined),
                    text: '视频 $videoCount',
                  ),
                  Tab(
                    icon: const Icon(Icons.audiotrack),
                    text: '音频 $audioCount',
                  ),
                ],
              );
            }),
          ),
        ),
        body: Obx(() {
          final tasks = _downloadService.tasks.toList(growable: false);
          final videoEntries = _entriesForType(tasks, DownloadMediaType.video);
          final audioEntries = _entriesForType(tasks, DownloadMediaType.audio);

          return TabBarView(
            children: [
              _buildTaskGrid(
                entries: videoEntries,
                emptyText: '暂无视频下载任务',
              ),
              _buildTaskGrid(
                entries: audioEntries,
                emptyText: '暂无音频下载任务',
              ),
            ],
          );
        }),
      ),
    );
  }
}
