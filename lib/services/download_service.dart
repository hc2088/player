// lib/services/download_service.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../models/download_task.dart';
import '../utils/video_extractor.dart';
import 'download_manager.dart';

class DownloadService extends GetxController {
  static const String storageKey = 'download_tasks';
  final box = GetStorage();

  var tasks = <DownloadTask>[].obs;
  final Set<String> _creatingTaskKeys = {};

  @override
  void onInit() async {
    super.onInit();
    await loadTasksFromStorage();
    checkAndGenerateThumbnails(); // 只调用一次
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
    task.status = DownloadStatus.downloading;
    print('[Download] 开始下载: ${task.url}');
    tasks.refresh();
    await saveTasksToStorage();

    await DownloadManager.download(task, (progress) async {
      print(
          '[Download] 进度回调: ${(progress * 100).toStringAsFixed(2)}%, status=${task.status}');

      if (progress < 0) {
        task.status = DownloadStatus.failed;
        print('[Download] 下载失败: ${task.url}');
      } else {
        task.progress = progress;

        if (progress >= 1.0 && task.status != DownloadStatus.completed) {
          if (!await _downloadedFileExists(task)) {
            task.status = DownloadStatus.failed;
            task.progress = 0.0;
            print('[Download] 进度达到100%，但文件不存在: ${task.filePath}');
            tasks.refresh();
            await saveTasksToStorage();
            return;
          }

          print('[Download] 进度达到100%，文件存在，准备设置为 completed');
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
        }
      }

      tasks.refresh();
      print('[Download] 保存任务状态...');
      await saveTasksToStorage();
    });
  }

  /// 取消某个任务下载
  Future<void> cancelDownload(DownloadTask task) async {
    if (task.status != DownloadStatus.downloading) return;

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
    await DownloadManager.cancel(task);

    await _deleteFile(task);

    tasks.remove(task);
    await saveTasksToStorage();
  }

  Future<void> clearAllTasks() async {
    for (var task in tasks) {
      await DownloadManager.cancel(task);
      await _deleteFile(task);
    }
    tasks.clear();
    await saveTasksToStorage();
  }

  Future<void> retryDownload(DownloadTask task) async {
    if (task.status == DownloadStatus.downloading) return;
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
    final resolvedUrl = await VideoExtractor.refreshHaijiaoMediaUrl(
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
