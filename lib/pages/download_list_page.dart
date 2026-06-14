import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

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

  Future<void> _openTask(DownloadTask task, int index) async {
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

    if (task.mediaType == DownloadMediaType.audio &&
        task.status == DownloadStatus.completed &&
        task.filePath != null) {
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

    if (task.mediaType == DownloadMediaType.image) {
      if (task.status != DownloadStatus.completed || task.filePath == null) {
        _showPageSnack('图片尚未下载完成，当前状态：${_statusLabel(task.status)}');
        return;
      }

      final repaired = await _downloadService.repairCompletedImageTask(task);
      if (!mounted) return;
      if (!repaired) {
        _showPageSnack('图片文件损坏，请重新下载');
        return;
      }

      final imageTasks = _downloadService.tasks
          .where((item) =>
              item.mediaType == DownloadMediaType.image &&
              item.status == DownloadStatus.completed &&
              item.filePath != null &&
              item.filePath!.isNotEmpty)
          .toList(growable: false);
      final imageIndex = imageTasks.indexWhere((item) => item.id == task.id);

      Get.toNamed(
        RouteHelper.localImageViewer,
        arguments: {
          'initialIndex': imageIndex < 0 ? 0 : imageIndex,
          'items': imageTasks
              .map((item) => {
                    'path': item.filePath,
                    'title': item.fileName ?? '图片',
                  })
              .toList(growable: false),
        },
      );
      return;
    }

    _showPageSnack('文件尚未下载完成，当前状态：${_statusLabel(task.status)}');
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

  String _taskDisplayName(DownloadTask task) {
    final fileName = task.fileName?.trim();
    if (fileName != null && fileName.isNotEmpty) return fileName;

    final filePath = task.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      return p.basename(filePath);
    }

    return task.url;
  }

  Future<void> _showRenameDialog(DownloadTask task) async {
    if (task.status != DownloadStatus.completed) {
      _showPageSnack('下载完成后才能修改文件名');
      return;
    }

    final currentName = _taskDisplayName(task);
    final extension = p.extension(currentName);
    final initialName = p.basenameWithoutExtension(currentName);
    var draftName = initialName;

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改文件名'),
          content: TextFormField(
            initialValue: initialName,
            autofocus: true,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: '文件名',
              suffixText: extension.isEmpty ? null : extension,
            ),
            onChanged: (value) => draftName = value,
            onFieldSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(draftName),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (newName == null) return;

    final oldPath = task.filePath;
    try {
      await _downloadService.renameCompletedTask(task, newName);
      if (oldPath != null && task.filePath != null) {
        _playbackService.updateSessionFile(
          oldPath: oldPath,
          newPath: task.filePath!,
          title: task.fileName ?? _taskDisplayName(task),
        );
      }
      _showPageSnack('文件名已修改');
    } catch (e) {
      _showPageSnack('修改失败：$e');
    }
  }

  Widget _buildTaskCard(DownloadTask task, int index) {
    final colorScheme = Theme.of(context).colorScheme;

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
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTaskPreview(task),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTaskInfo(task),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskPreview(DownloadTask task) {
    switch (task.mediaType) {
      case DownloadMediaType.audio:
        return _buildAudioThumb();
      case DownloadMediaType.image:
        return _buildImagePreview(task);
      case DownloadMediaType.video:
        return _buildVideoPreview(task);
    }
  }

  Widget _buildTaskInfo(DownloadTask task) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 78),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitle(task),
          const SizedBox(height: 5),
          _buildSourceDomain(task),
          const SizedBox(height: 6),
          _buildStatusAndActions(task),
          if (task.status == DownloadStatus.failed &&
              task.failureReason?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            _buildFailureReason(task.failureReason!.trim()),
          ],
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 6),
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

  Widget _buildFailureReason(String reason) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline,
          size: 15,
          color: Colors.redAccent,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            reason,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioThumb() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 84,
      height: 62,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.audiotrack,
        color: colorScheme.onPrimaryContainer,
        size: 28,
      ),
    );
  }

  Widget _buildVideoPreview(DownloadTask task) {
    final hasThumbnail =
        task.thumbnailPath != null && File(task.thumbnailPath!).existsSync();

    return Container(
      width: 84,
      height: 62,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: hasThumbnail
          ? Image.file(
              File(task.thumbnailPath!),
              fit: BoxFit.cover,
            )
          : const Icon(
              Icons.videocam_off_outlined,
              size: 30,
              color: Colors.white70,
            ),
    );
  }

  Widget _buildImagePreview(DownloadTask task) {
    final filePath = task.filePath;
    final fileExists = filePath != null && File(filePath).existsSync();

    return Container(
      width: 84,
      height: 62,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: fileExists
          ? Image.file(
              File(filePath),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.broken_image_outlined,
                  size: 30,
                  color: Colors.white70,
                );
              },
            )
          : const Icon(
              Icons.image_outlined,
              size: 30,
              color: Colors.white70,
            ),
    );
  }

  Widget _buildTitle(DownloadTask task) {
    return Text(
      _taskDisplayName(task),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.18,
      ),
    );
  }

  Widget _buildStatusAndActions(DownloadTask task) {
    final statusColor = _statusColor(task.status);

    return Row(
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
          _mediaTypeLabel(task.mediaType),
          style: const TextStyle(
            color: Colors.blueGrey,
            fontSize: 12,
          ),
        ),
        const Spacer(),
        _buildActions(task),
      ],
    );
  }

  String _mediaTypeLabel(DownloadMediaType mediaType) {
    switch (mediaType) {
      case DownloadMediaType.audio:
        return '音频';
      case DownloadMediaType.image:
        return '图片';
      case DownloadMediaType.video:
        return '视频';
    }
  }

  Widget _buildActions(DownloadTask task) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _compactIconButton(
          tooltip: '打开原网页',
          icon: Icons.language,
          color: Colors.blueAccent,
          onPressed: () {
            final url =
                task.originPageUrl.isNotEmpty ? task.originPageUrl : task.url;
            Get.toNamed(RouteHelper.videoWebDetail, arguments: {'url': url});
          },
        ),
        if (task.status == DownloadStatus.completed)
          _compactIconButton(
            tooltip: '修改文件名',
            icon: Icons.drive_file_rename_outline,
            color: Colors.blueGrey,
            onPressed: () => _showRenameDialog(task),
          ),
        if (task.status != DownloadStatus.completed &&
            task.status != DownloadStatus.downloading)
          _compactIconButton(
            tooltip: '重新下载',
            icon: Icons.refresh,
            color: Colors.orange,
            onPressed: () => _downloadService.retryDownload(task),
          ),
        if (task.status == DownloadStatus.downloading)
          _compactIconButton(
            tooltip: '强制重新下载',
            icon: Icons.restart_alt,
            color: Colors.orange,
            onPressed: () => _downloadService.forceRetryDownload(task),
          ),
        _compactIconButton(
          tooltip: '取消/删除任务',
          icon: Icons.delete,
          color: Colors.redAccent,
          onPressed: () => _downloadService.removeTask(task),
        ),
      ],
    );
  }

  Widget _compactIconButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      icon: Icon(icon, color: color, size: 20),
      onPressed: onPressed,
    );
  }

  Widget _buildTaskList({
    required List<MapEntry<int, DownloadTask>> entries,
    required String emptyText,
  }) {
    if (entries.isEmpty) {
      return Center(child: Text(emptyText));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
      itemCount: entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _buildTaskCard(entry.value, entry.key);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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
              final imageCount = tasks
                  .where((task) => task.mediaType == DownloadMediaType.image)
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
                  Tab(
                    icon: const Icon(Icons.image_outlined),
                    text: '图片 $imageCount',
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
          final imageEntries = _entriesForType(tasks, DownloadMediaType.image);

          return TabBarView(
            children: [
              _buildTaskList(
                entries: videoEntries,
                emptyText: '暂无视频下载任务',
              ),
              _buildTaskList(
                entries: audioEntries,
                emptyText: '暂无音频下载任务',
              ),
              _buildTaskList(
                entries: imageEntries,
                emptyText: '暂无图片下载任务',
              ),
            ],
          );
        }),
      ),
    );
  }
}
