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
  void onInit() async {
    super.onInit();
    await loadTasksFromStorage();
    checkAndGenerateThumbnails(); // 只调用一次
  }

  Future<void> addDownloadTask(String url, String originPageUrl,
      {String? fileName}) async {
    if (tasks.any((task) => task.url == url)) {
      print('任务已存在: $url');
      return;
    }

    final task = DownloadTask(
        url: url,
        fileName: fileName,
        originPageUrl: originPageUrl,
        status: DownloadStatus.pending);

    // 异步赋值路径
    await assignPaths(task);

    tasks.add(task);
    await saveTasksToStorage();
    _startDownload(task);
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
          print('[Download] 进度达到100%，准备设置为 completed');
          task.status = DownloadStatus.completed;

          print('[Download] 开始生成封面...');
          bool success = await DownloadManager.generateThumbnail(task);
          if (success) {
            print('[Download] 封面生成成功: ${task.thumbnailPath}');
          } else {
            print('[Download] 封面生成失败');
          }
        }
      }

      tasks.refresh();
      print('[Download] 保存任务状态...');
      await saveTasksToStorage();
    });
  }

  /// 取消某个任务下载
  void cancelDownload(DownloadTask task) {
    if (task.status != DownloadStatus.downloading) return;

    DownloadManager.cancel(task);

    // 标记为取消状态
    task.status = DownloadStatus.canceled;
    task.progress = 0.0;

    // 删除文件和封面（可选）
    _deleteFile(task);

    tasks.refresh();
    saveTasksToStorage();
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

  Future<void> loadTasksFromStorage() async {
    final stored = box.read(storageKey);
    if (stored != null) {
      final List<dynamic> jsonList = stored;
      final loaded = DownloadTask.fromJsonList(jsonList);
      // 修复路径
      await DownloadManager.fixDownloadTaskPaths(loaded);
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

  Future<void> saveTasksToStorage() async {
    final jsonList = DownloadTask.toJsonList(tasks);
    await box.write(storageKey, jsonList);
  }

  /// 异步批量补生成历史任务封面（启动时调用）
  Future<void> checkAndGenerateThumbnails() async {
    for (var task in tasks) {
      if (task.status == DownloadStatus.completed) {
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
