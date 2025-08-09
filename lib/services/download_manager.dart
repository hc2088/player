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

  // 公用方法：根据任务获取文件路径
  static Future<String> getFilePath(DownloadTask task) async {
    final dir = await _getDownloadDir();
    final now = DateTime.now();
    final formattedTime = _formatDateTime(now);

    // 初步获取文件名
    String fileName = (task.fileName?.trim().isNotEmpty ?? false)
        ? task.fileName!.trim()
        : 'video_$formattedTime';

    // 清除可能的扩展名，准备自己添加
    fileName = fileName.replaceAll(RegExp(r'\.mp4$', caseSensitive: false), '');

    // 限制总长度为 50，包括后缀（".mp4" 为 4 个字符）
    const maxLength = 50;
    const suffix = '.mp4';
    const maxNameLength = maxLength - suffix.length;

    if (fileName.length > maxNameLength) {
      fileName = fileName.substring(0, maxNameLength);
    }

    // 添加后缀
    fileName += suffix;

    // 赋值回 task
    task.fileName = fileName;

    // 拼接完整路径
    final rawPath = '$dir/$fileName';

    // 平台安全路径
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
    final duration = await _getDuration(task.url);
    print('[Download] 获取视频时长: $duration 秒');

    final filePath = task.filePath;
    final command = "-y -i '${task.url}' -c copy '$filePath'";
    print('[Download] 执行命令: $command');

    final sessionFuture = FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        _activeSessions.remove(task.url);

        if (ReturnCode.isSuccess(returnCode)) {
          print('[Download] FFmpeg 成功: $filePath');
          onProgress(1.0);
        } else {
          print('[Download] FFmpeg 失败，code=$returnCode');
          onProgress(-1.0);
        }
      },
      (log) => print('[FFmpegLog] ${log.getMessage()}'),
      (statistics) {
        final time = statistics.getTime();
        if (duration != null && duration > 0) {
          final progress = (time / (duration * 1000)).clamp(0.0, 1.0);
          print('[Download] 实时进度: ${(progress * 100).toStringAsFixed(2)}%');
          onProgress(progress);
        }
      },
    );

    final session = await sessionFuture;
    _activeSessions[task.url] = session;
    print('[Download] FFmpeg session 存储完成');
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
