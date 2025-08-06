import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/download_task.dart';

class DownloadManager {
  static final Map<String, FFmpegSession> _activeSessions = {};

  static Future<String> _getDownloadDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static Future<void> fixDownloadTaskPaths(List<DownloadTask> tasks) async {
    final newDir = await _getDownloadDir();

    for (final task in tasks) {
      if (task.filePath != null) {
        final oldFileName = p.basename(task.filePath!);
        task.filePath = p.join(newDir, oldFileName);
      }

      if (task.thumbnailPath != null) {
        final oldThumbName = p.basename(task.thumbnailPath!);
        task.thumbnailPath = p.join(newDir, oldThumbName);
      }
    }
  }

  static Future<double?> _getDuration(String url) async {
    final session = await FFprobeKit.getMediaInformation(url);
    final info = await session.getMediaInformation();
    final durationStr = info?.getDuration();
    if (durationStr != null) {
      return double.tryParse(durationStr);
    }
    return null;
  }

  static String _formatDateTime(DateTime dt) {
    return DateFormat('yyyyMMddHHmmss').format(dt);
  }

  // ✅ 公用方法：根据任务获取文件路径
  static Future<String> getFilePath(DownloadTask task) async {
    final dir = await _getDownloadDir();
    final now = DateTime.now();
    final formattedTime = _formatDateTime(now);

    // 初步获取文件名
    String fileName = (task.fileName?.trim().isNotEmpty ?? false)
        ? task.fileName!.trim()
        : 'video_$formattedTime.mp4';

    // ✅ 强制添加后缀（避免有中文但没有.mp4 的情况）
    if (!fileName.toLowerCase().endsWith('.mp4')) {
      fileName += '.mp4';
    }

    // 赋值回 task
    task.fileName = fileName;

    // 组合完整路径
    final rawPath = '$dir/$fileName';

    // ✅ 转为平台安全路径，防止中文/特殊字符报错
    final safePath = Uri.file(rawPath).toFilePath(windows: Platform.isWindows);
    task.filePath = safePath;
    return safePath;
  }

  static Future<String> getThumbnailPath(DownloadTask task) async {
    final dir = await _getDownloadDir();
    final baseName = (task.fileName ?? 'video').split('.').first;
    return '$dir/thumb_${baseName}.jpg';
  }

  // 生成封面
  static Future<bool> generateThumbnail(DownloadTask task) async {
    final videoPath = task.filePath;
    final thumbPath = await getThumbnailPath(task);

    final command = "-y -i '$videoPath' -ss 00:00:01 -vframes 1 '$thumbPath'";
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      task.thumbnailPath = thumbPath;
      return true;
    }
    return false;
  }

  static Future<void> download(
    DownloadTask task,
    Function(double) onProgress,
  ) async {
    // 获取视频总时长
    final duration = await _getDuration(task.url);

    final filePath = task.filePath;
    final command = "-y -i '${task.url}' -c copy '$filePath'";

    // 关键点：先启动 async 会返回 Future<FFmpegSession>
    final sessionFuture = FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        // 下载完成或失败后，清理 session
        _activeSessions.remove(task.url);
        if (ReturnCode.isSuccess(returnCode)) {
          onProgress(1.0);
        } else {
          onProgress(-1.0);
        }
      },
      (log) => print('[FFmpegLog] ${log.getMessage()}'),
      (statistics) {
        final time = statistics.getTime();
        if (duration != null && duration > 0) {
          final progress = (time / (duration * 1000)).clamp(0.0, 1.0);
          onProgress(progress);
        }
      },
    );

    // 等 session 创建完毕后，保存引用
    final session = await sessionFuture;
    _activeSessions[task.url] = session;
  }

  static Future<void> cancel(DownloadTask task) async {
    final session = _activeSessions[task.url];
    if (session != null) {
      print('[FFmpegCancel] 取消任务：${task.url}');
      await session.cancel();
      _activeSessions.remove(task.url);
    }
  }
}
