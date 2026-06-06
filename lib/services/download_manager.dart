import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/download_task.dart';

class DownloadManager {
  static final Map<String, FFmpegSession> _activeSessions = {};
  static final Map<String, HttpClient> _activeHttpClients = {};

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

  static Future<double?> _getDuration(DownloadTask task) async {
    final session = await FFprobeKit.getMediaInformationFromCommandArguments([
      '-v',
      'error',
      '-hide_banner',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      '-show_chapters',
      ...await _inputArgumentsForTask(task),
      '-i',
      task.url,
    ]);
    final info = session.getMediaInformation();
    final durationStr = info?.getDuration();
    if (durationStr != null) {
      return double.tryParse(durationStr);
    }
    return null;
  }

  static String _formatDateTime(DateTime dt) {
    return DateFormat('yyyyMMddHHmmss').format(dt);
  }

  static String _extensionForTask(DownloadTask task) {
    if (task.mediaType == DownloadMediaType.audio) {
      final ext = p.extension(Uri.tryParse(task.url)?.path ?? '').toLowerCase();
      const audioExts = {'.mp3', '.m4a', '.aac', '.wav', '.ogg', '.flac'};
      return audioExts.contains(ext) ? ext : '.mp3';
    }

    return '.mp4';
  }

  // 公用方法：根据任务获取文件路径
  static Future<String> getFilePath(DownloadTask task) async {
    final dir = await _getDownloadDir();
    final now = DateTime.now();
    final formattedTime = _formatDateTime(now);
    final suffix = _extensionForTask(task);

    // 初步获取文件名
    String fileName = (task.fileName?.trim().isNotEmpty ?? false)
        ? task.fileName!.trim()
        : '${task.mediaType.name}_$formattedTime';

    // 清除可能的扩展名，准备自己添加
    final currentExtension = p.extension(fileName);
    if (currentExtension.isNotEmpty) {
      fileName =
          fileName.substring(0, fileName.length - currentExtension.length);
    }

    // 限制总长度为 50，包括后缀
    const maxLength = 50;
    final maxNameLength = maxLength - suffix.length;

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
    return '$dir/thumb_$baseName.jpg';
  }

  // 生成封面
  static Future<bool> generateThumbnail(DownloadTask task) async {
    if (task.mediaType != DownloadMediaType.video) {
      return false;
    }

    final videoPath = task.filePath;
    final thumbPath = await getThumbnailPath(task);

    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      videoPath ?? '',
      '-ss',
      '00:00:01',
      '-vframes',
      '1',
      thumbPath,
    ]);
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
    if (task.mediaType == DownloadMediaType.audio) {
      await _downloadDirectFile(task, onProgress);
      return;
    }

    final duration = await _getDuration(task);
    print('[Download] 获取视频时长: $duration 秒');

    final filePath = task.filePath;
    final arguments = [
      '-y',
      ...await _inputArgumentsForTask(task),
      '-i',
      task.url,
      '-c',
      'copy',
      filePath ?? '',
    ];
    print('[Download] 执行命令: ${arguments.join(' ')}');

    final sessionFuture = FFmpegKit.executeWithArgumentsAsync(
      arguments,
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

  static Future<void> _downloadDirectFile(
    DownloadTask task,
    Function(double) onProgress,
  ) async {
    final filePath = task.filePath;
    if (filePath == null || filePath.isEmpty) {
      onProgress(-1.0);
      return;
    }

    final uri = Uri.tryParse(task.url);
    if (uri == null) {
      onProgress(-1.0);
      return;
    }

    final outputFile = File(filePath);
    final parent = outputFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final client = HttpClient();
    IOSink? sink;
    _activeHttpClients[task.url] = client;

    try {
      final request = await client.getUrl(uri);
      final headers = await _httpHeadersForTask(task);
      headers.forEach(request.headers.set);

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      sink = outputFile.openWrite();
      final totalBytes = response.contentLength;
      var receivedBytes = 0;

      await for (final chunk in response) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        if (totalBytes > 0) {
          onProgress((receivedBytes / totalBytes).clamp(0.0, 1.0));
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;
      onProgress(1.0);
    } catch (e) {
      print('[Download] 直连音频下载失败: $e');
      await sink?.close();
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      onProgress(-1.0);
    } finally {
      _activeHttpClients.remove(task.url);
      client.close(force: true);
    }
  }

  static Future<List<String>> _inputArgumentsForTask(DownloadTask task) async {
    final args = <String>[
      '-user_agent',
      _userAgent,
      '-protocol_whitelist',
      'file,http,https,tcp,tls,crypto',
      '-allowed_extensions',
      'ALL',
    ];

    final headerText = await _ffmpegHeadersForTask(task);
    if (headerText.isNotEmpty) {
      args.addAll(['-headers', headerText]);
    }

    return args;
  }

  static Future<String> _ffmpegHeadersForTask(DownloadTask task) async {
    final originPageUrl = task.originPageUrl.trim();
    final lines = <String>[];

    if (originPageUrl.isNotEmpty) {
      lines.add('Referer: $originPageUrl');

      final origin = _originString(originPageUrl);
      if (origin != null) {
        lines.add('Origin: $origin');
      }

      final cookieHeader = await _cookieHeader(originPageUrl);
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        lines.add('Cookie: $cookieHeader');
      }
    }

    return lines.isEmpty ? '' : '${lines.join('\r\n')}\r\n';
  }

  static Future<String?> _cookieHeader(String pageUrl) async {
    try {
      final origin = _originString(pageUrl);
      if (origin == null) return null;

      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(origin),
      );
      if (cookies.isEmpty) return null;

      return cookies
          .where((cookie) => cookie.name.isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>> _httpHeadersForTask(
    DownloadTask task,
  ) async {
    final headers = <String, String>{
      'User-Agent': _userAgent,
    };

    final originPageUrl = task.originPageUrl.trim();
    if (originPageUrl.isNotEmpty) {
      headers['Referer'] = originPageUrl;

      final origin = _originString(originPageUrl);
      if (origin != null) {
        headers['Origin'] = origin;
      }

      final cookieHeader = await _cookieHeader(originPageUrl);
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        headers['Cookie'] = cookieHeader;
      }
    }

    return headers;
  }

  static String? _originString(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static Future<void> cancel(DownloadTask task) async {
    final session = _activeSessions[task.url];
    if (session != null) {
      print('[FFmpegCancel] 取消任务：${task.url}');
      await session.cancel();
      _activeSessions.remove(task.url);
    }

    final client = _activeHttpClients.remove(task.url);
    client?.close(force: true);
  }

  static const String _userAgent =
      'Mozilla/5.0 AppleWebKit/537.36 Chrome Safari';
}
