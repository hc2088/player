// lib/services/download_service.dart
import 'dart:io';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../models/download_task.dart';
import 'download_manager.dart';

class DownloadService extends GetxController {
  static const String storageKey = 'download_tasks';
  final box = GetStorage();

  var tasks = <DownloadTask>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadTasksFromStorage();
  }

  void addDownloadTask(String url, String originPageUrl, {String? fileName}) {
    if (tasks.any((task) => task.url == url)) {
      print('任务已存在: $url');
      return;
    }

    final task = DownloadTask(
        url: url, fileName: fileName, originPageUrl: originPageUrl);
    tasks.add(task);
    saveTasksToStorage();
    _startDownload(task);
  }

  void _startDownload(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    tasks.refresh();
    saveTasksToStorage();

    await DownloadManager.download(task, (progress) {
      if (progress < 0) {
        // 下载失败
        task.status = DownloadStatus.failed;
      } else {
        task.progress = progress;

        if (progress >= 1.0 && task.status != DownloadStatus.completed) {
          task.status = DownloadStatus.completed;
        }
      }

      tasks.refresh();
      saveTasksToStorage();
    });

    tasks.refresh();
    saveTasksToStorage();
  }

  Future<void> _deleteFile(DownloadTask task) async {
    final path = await DownloadManager.getFilePath(task);
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
        print('已删除本地文件: $path');
      } catch (e) {
        print('删除文件失败: $e');
      }
    }
  }

  void removeTask(DownloadTask task) {
    DownloadManager.cancel(task);

    _deleteFile(task);

    tasks.remove(task);
    saveTasksToStorage();
  }

  void clearAllTasks() {
    for (var task in tasks) {
      DownloadManager.cancel(task);
      _deleteFile(task);
    }
    tasks.clear();
    saveTasksToStorage();
  }

  void retryDownload(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) return;
    task.progress = 0.0;
    task.status = DownloadStatus.pending;
    _deleteFile(task);
    tasks.refresh();
    saveTasksToStorage();
    _startDownload(task);
  }

  void loadTasksFromStorage() {
    final stored = box.read(storageKey);
    if (stored != null) {
      final List<dynamic> jsonList = stored;
      final loaded = DownloadTask.fromJsonList(jsonList);
      // 设置未完成任务为失败
      for (var task in loaded) {
        if (task.status != DownloadStatus.completed) {
          task.status = DownloadStatus.failed;
        }
      }
      tasks.assignAll(loaded);
    }
    tasks.refresh();
  }

  void saveTasksToStorage() {
    final jsonList = DownloadTask.toJsonList(tasks);
    box.write(storageKey, jsonList);
  }
}
