// lib/services/download_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../models/download_task.dart';
import '../utils/video_extractor.dart';
import 'download_manager.dart';

class DownloadService extends GetxController {
  static const String storageKey = 'download_tasks';
  static const Duration _downloadStallTimeout = Duration(minutes: 2);
  static const Duration _watchdogInterval = Duration(seconds: 15);
  final box = GetStorage();

  var tasks = <DownloadTask>[].obs;
  final Set<String> _creatingTaskKeys = {};
  final Map<String, Timer> _downloadWatchdogs = {};
  final Map<String, DateTime> _lastDownloadActivityAt = {};
  final Map<String, int> _lastObservedFileBytes = {};
  final Map<String, int> _downloadGenerations = {};

  @override
  void onInit() async {
    super.onInit();
    await loadTasksFromStorage();
    checkAndGenerateThumbnails(); // 只调用一次
  }

  @override
  void onClose() {
    for (final timer in _downloadWatchdogs.values) {
      timer.cancel();
    }
    _downloadWatchdogs.clear();
    super.onClose();
  }

  Future<bool> addDownloadTask(
    String url,
    String originPageUrl, {
    String? fileName,
    DownloadMediaType mediaType = DownloadMediaType.video,
    int? sourceAttachmentId,
  }) async {
    final trimmedUrl = url.trim();
    if (!DownloadManager.isDownloadableUrl(trimmedUrl)) {
      debugPrint('[Download] 跳过不可下载地址: $trimmedUrl');
      return false;
    }

    final taskKey = _taskKey(trimmedUrl, mediaType);
    if (_hasTask(taskKey) || !_creatingTaskKeys.add(taskKey)) {
      print('任务已存在: $url');
      return false;
    }

    try {
      final task = DownloadTask(
          url: trimmedUrl,
          fileName: fileName,
          mediaType: mediaType,
          sourceAttachmentId: sourceAttachmentId,
          originPageUrl: originPageUrl,
          status: DownloadStatus.pending);

      // 异步赋值路径
      await assignPaths(task);

      tasks.add(task);
      await saveTasksToStorage();
      _startDownload(task);
      return true;
    } finally {
      _creatingTaskKeys.remove(taskKey);
    }
  }

  static Future<void> assignPaths(DownloadTask task) async {
    final filePath = await DownloadManager.getFilePath(task);
    task.filePath = filePath;
  }

  void _startDownload(DownloadTask task) async {
    final generation = _nextDownloadGeneration(task);
    _cancelDownloadWatchdog(task);
    _recordDownloadActivity(task);
    task.status = DownloadStatus.downloading;
    print('[Download] 开始下载: ${task.url}');
    tasks.refresh();
    await saveTasksToStorage();
    _startDownloadWatchdog(task, generation);

    await DownloadManager.download(
      task,
      (progress) async {
        if (!_isCurrentDownload(task, generation)) return;
        if (task.status != DownloadStatus.downloading) return;

        print(
            '[Download] 进度回调: ${(progress * 100).toStringAsFixed(2)}%, status=${task.status}');

        if (progress < 0) {
          await _markTaskFailed(task, generation);
          print('[Download] 下载失败: ${task.url}');
          return;
        }

        _recordDownloadActivity(task);
        task.progress = progress.clamp(0.0, 1.0);

        if (task.progress >= 1.0 && task.status != DownloadStatus.completed) {
          await _completeTaskIfFileExists(task, generation);
          return;
        }

        tasks.refresh();
        print('[Download] 保存任务状态...');
        await saveTasksToStorage();
      },
      shouldContinue: () =>
          _isCurrentDownload(task, generation) &&
          task.status == DownloadStatus.downloading,
    );
  }

  /// 取消某个任务下载
  Future<void> cancelDownload(DownloadTask task) async {
    if (task.status != DownloadStatus.downloading) return;

    _invalidateDownload(task);
    _cancelDownloadWatchdog(task);
    await DownloadManager.cancel(task);

    // 标记为取消状态
    task.status = DownloadStatus.canceled;
    task.progress = 0.0;

    // 删除文件和封面（可选）
    await _deleteFile(task);

    tasks.refresh();
    await saveTasksToStorage();
  }

  Future<void> _deleteFile(DownloadTask task) async {
    if (task.filePath == null) return;
    final file = File(task.filePath!);
    if (await file.exists()) {
      try {
        await file.delete();
        print('已删除本地文件: ${task.filePath}');
      } catch (e) {
        print('删除文件失败: $e');
      }
    }

    if (task.thumbnailPath != null) {
      final thumbFile = File(task.thumbnailPath!);
      if (await thumbFile.exists()) {
        try {
          await thumbFile.delete();
          print('已删除封面文件: ${task.thumbnailPath}');
        } catch (e) {
          print('删除封面文件失败: $e');
        }
      }
    }
  }

  Future<void> removeTask(DownloadTask task) async {
    _invalidateDownload(task);
    _cancelDownloadWatchdog(task);
    await DownloadManager.cancel(task);

    await _deleteFile(task);

    tasks.remove(task);
    await saveTasksToStorage();
  }

  Future<void> clearAllTasks() async {
    for (var task in tasks) {
      _invalidateDownload(task);
      _cancelDownloadWatchdog(task);
      await DownloadManager.cancel(task);
      await _deleteFile(task);
    }
    tasks.clear();
    await saveTasksToStorage();
  }

  Future<void> retryDownload(DownloadTask task, {bool force = false}) async {
    if (task.status == DownloadStatus.downloading) {
      if (!force) return;
      _invalidateDownload(task);
      _cancelDownloadWatchdog(task);
      await DownloadManager.cancel(task);
    }

    task.progress = 0.0;
    task.status = DownloadStatus.pending;
    await _refreshResolvedUrlIfNeeded(task);

    if (!DownloadManager.isDownloadableUrl(task.url)) {
      task.status = DownloadStatus.failed;
      debugPrint('[Download] 重新下载失败，不支持页面内临时地址: ${task.url}');
      tasks.refresh();
      await saveTasksToStorage();
      return;
    }

    await _deleteFile(task);
    tasks.refresh();
    await saveTasksToStorage();
    _startDownload(task);
  }

  Future<void> forceRetryDownload(DownloadTask task) {
    return retryDownload(task, force: true);
  }

  Future<void> loadTasksFromStorage() async {
    final stored = box.read(storageKey);
    if (stored != null) {
      final List<dynamic> jsonList = stored;
      final loaded = DownloadTask.fromJsonList(jsonList);
      // 修复路径
      await DownloadManager.fixDownloadTaskPaths(loaded);
      // 设置未完成任务为失败
      for (var task in loaded) {
        if (task.status == DownloadStatus.completed) {
          if (!await _downloadedFileExists(task)) {
            task.status = DownloadStatus.failed;
            task.progress = 0.0;
          }
        } else {
          task.status = DownloadStatus.failed;
        }
      }
      tasks.assignAll(loaded);
    }
    tasks.refresh();
  }

  Future<void> saveTasksToStorage() async {
    final jsonList = DownloadTask.toJsonList(tasks);
    await box.write(storageKey, jsonList);
  }

  int _nextDownloadGeneration(DownloadTask task) {
    final next = (_downloadGenerations[task.id] ?? 0) + 1;
    _downloadGenerations[task.id] = next;
    return next;
  }

  void _invalidateDownload(DownloadTask task) {
    _downloadGenerations[task.id] = (_downloadGenerations[task.id] ?? 0) + 1;
  }

  bool _isCurrentDownload(DownloadTask task, int generation) {
    return _downloadGenerations[task.id] == generation;
  }

  void _recordDownloadActivity(DownloadTask task) {
    _lastDownloadActivityAt[task.id] = DateTime.now();
  }

  void _cancelDownloadWatchdog(DownloadTask task) {
    _downloadWatchdogs.remove(task.id)?.cancel();
    _lastDownloadActivityAt.remove(task.id);
    _lastObservedFileBytes.remove(task.id);
  }

  void _startDownloadWatchdog(DownloadTask task, int generation) {
    _downloadWatchdogs[task.id]?.cancel();
    _downloadWatchdogs[task.id] = Timer.periodic(_watchdogInterval, (_) async {
      if (!_isCurrentDownload(task, generation) ||
          task.status != DownloadStatus.downloading) {
        _cancelDownloadWatchdog(task);
        return;
      }

      if (await _downloadedFileGrew(task)) {
        _recordDownloadActivity(task);
        return;
      }

      final lastActivity = _lastDownloadActivityAt[task.id];
      if (lastActivity == null) {
        _recordDownloadActivity(task);
        return;
      }

      if (DateTime.now().difference(lastActivity) < _downloadStallTimeout) {
        return;
      }

      debugPrint('[Download] 下载长时间无进度，标记失败: ${task.url}');
      await DownloadManager.cancel(task);
      await _markTaskFailed(task, generation);
    });
  }

  Future<bool> _downloadedFileGrew(DownloadTask task) async {
    final filePath = task.filePath;
    if (filePath == null || filePath.isEmpty) return false;

    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final length = await file.length();
      final previousLength = _lastObservedFileBytes[task.id];
      _lastObservedFileBytes[task.id] = length;
      return previousLength != null && length > previousLength;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markTaskFailed(
    DownloadTask task,
    int generation, {
    bool resetProgress = false,
  }) async {
    if (!_isCurrentDownload(task, generation)) return;

    _cancelDownloadWatchdog(task);
    task.status = DownloadStatus.failed;
    if (resetProgress) {
      task.progress = 0.0;
    }
    tasks.refresh();
    await saveTasksToStorage();
  }

  Future<void> _completeTaskIfFileExists(
    DownloadTask task,
    int generation,
  ) async {
    if (!_isCurrentDownload(task, generation)) return;

    if (!await _downloadedFileExists(task)) {
      task.progress = 0.0;
      print('[Download] 进度达到100%，但文件不存在: ${task.filePath}');
      await _markTaskFailed(task, generation, resetProgress: true);
      return;
    }

    _cancelDownloadWatchdog(task);
    print('[Download] 进度达到100%，文件存在，准备设置为 completed');
    task.progress = 1.0;
    task.status = DownloadStatus.completed;

    if (task.mediaType == DownloadMediaType.video) {
      print('[Download] 开始生成封面...');
      bool success = await DownloadManager.generateThumbnail(task);
      if (success) {
        print('[Download] 封面生成成功: ${task.thumbnailPath}');
      } else {
        print('[Download] 封面生成失败');
      }
    }

    tasks.refresh();
    debugPrint('[Download] 保存任务状态...');
    await saveTasksToStorage();
  }

  bool _hasTask(String taskKey) {
    return tasks.any((task) => _taskKey(task.url, task.mediaType) == taskKey);
  }

  String _taskKey(String url, DownloadMediaType mediaType) {
    final trimmedUrl = url.trim();
    final uri = Uri.tryParse(trimmedUrl);
    final normalizedUrl = uri == null
        ? trimmedUrl
        : uri.removeFragment().normalizePath().toString();
    return '${mediaType.name}:$normalizedUrl';
  }

  Future<bool> _downloadedFileExists(DownloadTask task) async {
    final filePath = task.filePath;
    if (filePath == null || filePath.isEmpty) return false;

    final file = File(filePath);
    try {
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshResolvedUrlIfNeeded(DownloadTask task) async {
    final attachmentId = task.sourceAttachmentId;
    if (attachmentId == null || task.originPageUrl.trim().isEmpty) return;

    final type = task.mediaType == DownloadMediaType.audio
        ? ExtractedMediaType.audio
        : ExtractedMediaType.video;
    final resolvedUrl = await VideoExtractor.refreshTargetSiteMediaUrl(
      pageUrl: task.originPageUrl,
      attachmentId: attachmentId,
      type: type,
    );

    if (resolvedUrl == null || resolvedUrl.trim().isEmpty) return;

    final trimmedUrl = resolvedUrl.trim();
    if (trimmedUrl != task.url) {
      task.url = trimmedUrl;
    }
  }

  /// 异步批量补生成历史任务封面（启动时调用）
  Future<void> checkAndGenerateThumbnails() async {
    for (var task in tasks) {
      if (task.status == DownloadStatus.completed) {
        if (task.mediaType != DownloadMediaType.video) continue;

        bool needGenerate = false;
        if (task.thumbnailPath == null) {
          needGenerate = true;
        } else {
          final file = File(task.thumbnailPath!);
          if (!file.existsSync()) needGenerate = true;
        }
        if (needGenerate) {
          print('补生成封面，任务: ${task.fileName}');
          final success = await DownloadManager.generateThumbnail(task);
          if (success) {
            // 生成成功后刷新和存储
            tasks.refresh();
            saveTasksToStorage();
          }
        }
      }
    }
  }
}
