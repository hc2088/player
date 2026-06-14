// lib/services/download_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';
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
  bool _downloadWakelockEnabled = false;
  Future<void> _wakelockOperation = Future.value();

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
    _setDownloadWakelockEnabled(false);
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

  void _startDownload(
    DownloadTask task, {
    bool allowLinkRefreshRetry = true,
  }) async {
    final generation = _nextDownloadGeneration(task);
    _cancelDownloadWatchdog(task);
    _recordDownloadActivity(task);
    task.status = DownloadStatus.downloading;
    task.failureReason = null;
    print('[Download] 开始下载: ${task.url}');
    tasks.refresh();
    await saveTasksToStorage();
    _syncDownloadWakelock();
    _startDownloadWatchdog(task, generation);

    try {
      await DownloadManager.download(
        task,
        (update) async {
          if (!_isCurrentDownload(task, generation)) return;
          if (task.status != DownloadStatus.downloading) return;

          print(
              '[Download] 进度回调: ${(update.progress * 100).toStringAsFixed(2)}%, status=${task.status}');

          if (update.isFailure) {
            final failureReason = update.failureReason ?? '下载失败，未返回具体原因';
            if (allowLinkRefreshRetry &&
                await _refreshAndRestartAfterLinkFailure(
                  task,
                  generation,
                  failureReason,
                )) {
              return;
            }

            await _markTaskFailed(
              task,
              generation,
              reason: failureReason,
            );
            print('[Download] 下载失败: ${task.url}');
            return;
          }

          _recordDownloadActivity(task);
          task.progress = update.progress.clamp(0.0, 1.0);

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
    } catch (e) {
      await _markTaskFailed(task, generation, reason: e.toString());
    }
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
    task.failureReason = null;

    // 删除文件和封面（可选）
    await _deleteFile(task);

    tasks.refresh();
    await saveTasksToStorage();
    _syncDownloadWakelock();
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
    _syncDownloadWakelock();
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
    _syncDownloadWakelock();
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
    task.failureReason = null;
    await _refreshResolvedUrlIfNeeded(task);

    if (!DownloadManager.isDownloadableUrl(task.url)) {
      task.status = DownloadStatus.failed;
      task.failureReason = '重新下载失败，不支持页面内临时地址';
      debugPrint('[Download] 重新下载失败，不支持页面内临时地址: ${task.url}');
      tasks.refresh();
      await saveTasksToStorage();
      _syncDownloadWakelock();
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

  Future<bool> repairCompletedImageTask(DownloadTask task) async {
    if (task.mediaType != DownloadMediaType.image) return true;
    if (task.status != DownloadStatus.completed) return false;

    final repaired = await DownloadManager.repairDownloadedImageFile(task);
    if (!repaired) {
      task.status = DownloadStatus.failed;
      task.progress = 0.0;
      task.failureReason = '图片文件校验失败';
      tasks.refresh();
      await saveTasksToStorage();
      _syncDownloadWakelock();
    }
    return repaired;
  }

  Future<void> renameCompletedTask(
    DownloadTask task,
    String requestedName,
  ) async {
    if (task.status != DownloadStatus.completed) {
      throw StateError('下载完成后才能修改文件名');
    }

    final currentPath = task.filePath;
    if (currentPath == null || currentPath.isEmpty) {
      throw FileSystemException('文件路径为空');
    }

    final currentFile = File(currentPath);
    if (!await currentFile.exists()) {
      throw FileSystemException('文件不存在', currentPath);
    }

    final currentFileName = p.basename(currentPath);
    final extension = p.extension(currentFileName);
    final fallbackBaseName = p.basenameWithoutExtension(currentFileName);
    final baseName = _sanitizeRenameBaseName(
      requestedName,
      fallback: fallbackBaseName,
      extension: extension,
    );
    final targetPath = await _availableRenamePath(
      directoryPath: currentFile.parent.path,
      baseName: baseName,
      extension: extension,
      currentFileName: currentFileName,
    );

    if (p.normalize(targetPath) != p.normalize(currentPath)) {
      await currentFile.rename(targetPath);
    }

    task.filePath = targetPath;
    task.fileName = p.basename(targetPath);
    tasks.refresh();
    await saveTasksToStorage();
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
            task.failureReason = '已完成文件不存在或为空';
          }
        } else {
          task.status = DownloadStatus.failed;
          task.failureReason = '上次退出前下载未完成';
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
      await _markTaskFailed(task, generation, reason: '下载超过 2 分钟没有进度');
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
    String? reason,
  }) async {
    if (!_isCurrentDownload(task, generation)) return;

    _cancelDownloadWatchdog(task);
    task.status = DownloadStatus.failed;
    task.failureReason = reason;
    if (resetProgress) {
      task.progress = 0.0;
    }
    tasks.refresh();
    await saveTasksToStorage();
    _syncDownloadWakelock();
  }

  Future<void> _completeTaskIfFileExists(
    DownloadTask task,
    int generation,
  ) async {
    if (!_isCurrentDownload(task, generation)) return;

    if (!await _downloadedFileExists(task)) {
      task.progress = 0.0;
      print('[Download] 进度达到100%，但文件不存在: ${task.filePath}');
      await _markTaskFailed(
        task,
        generation,
        resetProgress: true,
        reason: '进度达到 100%，但文件不存在或为空',
      );
      return;
    }

    _cancelDownloadWatchdog(task);
    print('[Download] 进度达到100%，文件存在，准备设置为 completed');
    task.progress = 1.0;
    task.status = DownloadStatus.completed;
    task.failureReason = null;

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
    _syncDownloadWakelock();
  }

  void _syncDownloadWakelock() {
    final shouldKeepScreenOn =
        tasks.any((task) => task.status == DownloadStatus.downloading);
    _setDownloadWakelockEnabled(shouldKeepScreenOn);
  }

  void _setDownloadWakelockEnabled(bool enabled) {
    _wakelockOperation = _wakelockOperation.then((_) async {
      if (_downloadWakelockEnabled == enabled) return;

      try {
        if (enabled) {
          await WakelockPlus.enable();
        } else {
          await WakelockPlus.disable();
        }
        _downloadWakelockEnabled = enabled;
        debugPrint('[Download] ${enabled ? '开启' : '关闭'}下载防熄屏');
      } catch (e) {
        debugPrint('[Download] 切换防熄屏失败: $e');
      }
    });
  }

  bool _hasTask(String taskKey) {
    return tasks.any((task) => _taskKey(task.url, task.mediaType) == taskKey);
  }

  String _sanitizeRenameBaseName(
    String requestedName, {
    required String fallback,
    required String extension,
  }) {
    var baseName = requestedName.trim();
    baseName = baseName.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    if (extension.isNotEmpty &&
        baseName.toLowerCase().endsWith(extension.toLowerCase())) {
      baseName = baseName.substring(0, baseName.length - extension.length);
    }
    baseName = baseName.trim();
    baseName = baseName.replaceAll(RegExp(r'\s+'), ' ');
    baseName = baseName.replaceAll(RegExp(r'^\.+|\.+$'), '').trim();

    if (baseName.isEmpty) {
      baseName = fallback.trim();
    }
    if (baseName.isEmpty) {
      baseName = 'download';
    }

    const maxBaseNameLength = 80;
    if (baseName.length > maxBaseNameLength) {
      baseName = baseName.substring(0, maxBaseNameLength).trim();
    }
    return baseName;
  }

  Future<String> _availableRenamePath({
    required String directoryPath,
    required String baseName,
    required String extension,
    required String currentFileName,
  }) async {
    var index = 0;

    while (true) {
      final suffix = index == 0 ? '' : ' ($index)';
      final candidateFileName = '$baseName$suffix$extension';
      final candidatePath = p.join(directoryPath, candidateFileName);
      final isCurrentFile =
          candidateFileName.toLowerCase() == currentFileName.toLowerCase();

      if (isCurrentFile || !await File(candidatePath).exists()) {
        return candidatePath;
      }

      index++;
    }
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
      if (!await file.exists() || await file.length() <= 0) return false;
      if (task.mediaType == DownloadMediaType.image) {
        return DownloadManager.repairDownloadedImageFile(task);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshResolvedUrlIfNeeded(DownloadTask task) async {
    final attachmentId = task.sourceAttachmentId;
    if (attachmentId == null || task.originPageUrl.trim().isEmpty) return;

    final type = switch (task.mediaType) {
      DownloadMediaType.audio => ExtractedMediaType.audio,
      DownloadMediaType.image => ExtractedMediaType.image,
      DownloadMediaType.video => ExtractedMediaType.video,
    };
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

  Future<bool> _refreshAndRestartAfterLinkFailure(
    DownloadTask task,
    int generation,
    String failureReason,
  ) async {
    if (!_isCurrentDownload(task, generation)) return false;
    if (!_shouldRefreshAfterFailure(task, failureReason)) return false;

    final oldUrl = task.url;
    debugPrint('[Download] 链接失效，尝试刷新线路后重试: $failureReason');

    try {
      await _refreshResolvedUrlIfNeeded(task);
    } catch (e) {
      debugPrint('[Download] 刷新下载线路失败: $e');
      return false;
    }

    if (!_isCurrentDownload(task, generation)) return false;
    if (task.url == oldUrl || !DownloadManager.isDownloadableUrl(task.url)) {
      return false;
    }

    _invalidateDownload(task);
    _cancelDownloadWatchdog(task);
    await _deleteFile(task);
    task.progress = 0.0;
    task.status = DownloadStatus.pending;
    task.failureReason = null;
    tasks.refresh();
    await saveTasksToStorage();
    _startDownload(task, allowLinkRefreshRetry: false);
    return true;
  }

  bool _shouldRefreshAfterFailure(DownloadTask task, String failureReason) {
    if (task.sourceAttachmentId == null || task.originPageUrl.trim().isEmpty) {
      return false;
    }

    final lower = failureReason.toLowerCase();
    return lower.contains('404') ||
        lower.contains('403') ||
        lower.contains('not found') ||
        lower.contains('forbidden') ||
        lower.contains('server returned') ||
        lower.contains('unable to open key file') ||
        lower.contains('error when loading first segment') ||
        lower.contains('invalid data found when processing input');
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
