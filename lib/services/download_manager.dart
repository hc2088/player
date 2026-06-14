import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/download_task.dart';

class DownloadProgress {
  const DownloadProgress(this.progress, {this.failureReason});

  const DownloadProgress.failed(String reason)
      : progress = -1.0,
        failureReason = reason;

  final double progress;
  final String? failureReason;

  bool get isFailure => progress < 0;
}

class DownloadManager {
  static final Map<String, FFmpegSession> _activeSessions = {};
  static final Map<String, HttpClient> _activeHttpClients = {};
  static const Duration _networkIdleTimeout = Duration(seconds: 90);

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
    try {
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
      ]).timeout(_networkIdleTimeout);
      final info = session.getMediaInformation();
      final durationStr = info?.getDuration();
      if (durationStr != null) {
        return double.tryParse(durationStr);
      }
    } catch (e) {
      debugPrint('[Download] 获取视频时长超时或失败: $e');
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

    if (task.mediaType == DownloadMediaType.image) {
      final path = Uri.tryParse(task.url)?.path ?? '';
      final normalizedPath =
          path.toLowerCase().endsWith('.txt') ? p.withoutExtension(path) : path;
      final ext = p.extension(normalizedPath).toLowerCase();
      const imageExts = {
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.gif',
        '.bmp',
        '.heic',
        '.heif',
      };
      return imageExts.contains(ext) ? ext : '.jpg';
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

    final safeId = task.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final shortId =
        safeId.length > 8 ? safeId.substring(safeId.length - 8) : safeId;
    final uniqueSuffix = '_$shortId';
    final uniqueMaxNameLength = maxNameLength - uniqueSuffix.length;
    if (uniqueMaxNameLength > 0) {
      if (fileName.length > uniqueMaxNameLength) {
        fileName = fileName.substring(0, uniqueMaxNameLength);
      }
      fileName += uniqueSuffix;
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
    Function(DownloadProgress) onProgress, {
    bool Function()? shouldContinue,
  }) async {
    if (shouldContinue?.call() == false) return;

    if (!isDownloadableUrl(task.url)) {
      const reason = '不支持下载页面内临时地址';
      debugPrint('[Download] $reason: ${task.url}');
      onProgress(const DownloadProgress.failed(reason));
      return;
    }

    if (task.mediaType == DownloadMediaType.image) {
      await _downloadImageFile(task, onProgress, shouldContinue);
      return;
    }

    if (task.mediaType == DownloadMediaType.audio) {
      await _downloadDirectFile(task, onProgress, shouldContinue);
      return;
    }

    var duration = _shouldProbeDuration(task) ? await _getDuration(task) : null;
    if (shouldContinue?.call() == false) return;

    print('[Download] 获取视频时长: $duration 秒');

    final filePath = task.filePath;
    if (filePath == null || filePath.isEmpty) {
      onProgress(const DownloadProgress.failed('本地保存路径为空'));
      return;
    }

    final arguments = [
      '-y',
      ...await _inputArgumentsForTask(task),
      '-i',
      task.url,
      '-c',
      'copy',
      filePath,
    ];
    print('[Download] 执行命令: ${arguments.join(' ')}');

    try {
      final ffmpegLogs = <String>[];
      var nextLogMayBeDuration = false;
      final sessionFuture = FFmpegKit.executeWithArgumentsAsync(
        arguments,
        (session) async {
          final returnCode = await session.getReturnCode();
          _activeSessions.remove(task.id);

          if (ReturnCode.isSuccess(returnCode)) {
            print('[Download] FFmpeg 成功: $filePath');
            onProgress(const DownloadProgress(1.0));
          } else {
            final reason = await _ffmpegFailureReason(
              session,
              returnCode,
              liveLogs: ffmpegLogs,
            );
            debugPrint('[Download] FFmpeg 失败: $reason');
            onProgress(DownloadProgress.failed(reason));
          }
        },
        (log) {
          final message = log.getMessage();
          ffmpegLogs.add(message);
          final parsedDuration = _parseDurationFromLog(
            message,
            acceptStandalone: nextLogMayBeDuration,
          );
          if (parsedDuration != null) {
            duration = parsedDuration;
            nextLogMayBeDuration = false;
          } else {
            nextLogMayBeDuration = message.contains('Duration:');
          }
          print('[FFmpegLog] $message');
        },
        (statistics) {
          final time = statistics.getTime();
          final currentDuration = duration;
          if (currentDuration != null && currentDuration > 0) {
            final progress =
                (time / (currentDuration * 1000)).clamp(0.0, 0.999);
            print('[Download] 实时进度: ${(progress * 100).toStringAsFixed(2)}%');
            onProgress(DownloadProgress(progress));
          }
        },
      );

      final session = await sessionFuture;
      _activeSessions[task.id] = session;
      print('[Download] FFmpeg session 存储完成');
    } catch (e) {
      final reason = _downloadExceptionReason(e);
      debugPrint('[Download] FFmpeg 启动失败: $reason');
      onProgress(DownloadProgress.failed(reason));
    }
  }

  static bool _shouldProbeDuration(DownloadTask task) {
    final uri = Uri.tryParse(task.url);
    final lowerPath = (uri?.path ?? task.url).toLowerCase();
    return !lowerPath.endsWith('.m3u8') && !lowerPath.contains('/m3u8');
  }

  static double? _parseDurationFromLog(
    String message, {
    required bool acceptStandalone,
  }) {
    final text = message.trim();
    final pattern = acceptStandalone
        ? RegExp(r'^(\d{2}):(\d{2}):(\d{2}(?:\.\d+)?)$')
        : RegExp(r'Duration:\s*(\d{2}):(\d{2}):(\d{2}(?:\.\d+)?)');
    final match = pattern.firstMatch(text);
    if (match == null) return null;

    final hours = int.tryParse(match.group(1) ?? '');
    final minutes = int.tryParse(match.group(2) ?? '');
    final seconds = double.tryParse(match.group(3) ?? '');
    if (hours == null) return null;
    if (minutes == null) return null;
    if (seconds == null) return null;
    return (hours * 3600) + (minutes * 60) + seconds;
  }

  static Future<void> _downloadDirectFile(
    DownloadTask task,
    Function(DownloadProgress) onProgress,
    bool Function()? shouldContinue,
  ) async {
    if (shouldContinue?.call() == false) return;

    final filePath = task.filePath;
    if (filePath == null || filePath.isEmpty) {
      onProgress(const DownloadProgress.failed('本地保存路径为空'));
      return;
    }

    final uri = Uri.tryParse(task.url);
    if (uri == null) {
      onProgress(const DownloadProgress.failed('下载链接格式无效'));
      return;
    }

    final outputFile = File(filePath);
    final parent = outputFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final client = HttpClient();
    client.connectionTimeout = _networkIdleTimeout;
    IOSink? sink;
    _activeHttpClients[task.id] = client;

    try {
      final request = await client.getUrl(uri);
      final headers = await _httpHeadersForTask(task);
      headers.forEach(request.headers.set);

      final response = await request.close().timeout(_networkIdleTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      sink = outputFile.openWrite();
      final totalBytes = response.contentLength;
      var receivedBytes = 0;

      await for (final chunk in response.timeout(_networkIdleTimeout)) {
        if (shouldContinue?.call() == false) return;

        receivedBytes += chunk.length;
        sink.add(chunk);

        if (totalBytes > 0) {
          onProgress(
            DownloadProgress((receivedBytes / totalBytes).clamp(0.0, 0.999)),
          );
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;
      onProgress(const DownloadProgress(1.0));
    } catch (e) {
      final reason = _downloadExceptionReason(e);
      debugPrint('[Download] 直连文件下载失败: $reason');
      await sink?.close();
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      onProgress(DownloadProgress.failed(reason));
    } finally {
      _activeHttpClients.remove(task.id);
      client.close(force: true);
    }
  }

  static Future<void> _downloadImageFile(
    DownloadTask task,
    Function(DownloadProgress) onProgress,
    bool Function()? shouldContinue,
  ) async {
    if (shouldContinue?.call() == false) return;

    final filePath = task.filePath;
    if (filePath == null || filePath.isEmpty) {
      onProgress(const DownloadProgress.failed('本地保存路径为空'));
      return;
    }

    final uri = Uri.tryParse(task.url);
    if (uri == null) {
      onProgress(const DownloadProgress.failed('下载链接格式无效'));
      return;
    }

    final outputFile = File(filePath);
    final parent = outputFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final client = HttpClient();
    client.connectionTimeout = _networkIdleTimeout;
    _activeHttpClients[task.id] = client;

    try {
      final request = await client.getUrl(uri);
      final headers = await _httpHeadersForTask(task);
      headers.forEach(request.headers.set);

      final response = await request.close().timeout(_networkIdleTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      final builder = BytesBuilder(copy: false);

      await for (final chunk in response.timeout(_networkIdleTimeout)) {
        if (shouldContinue?.call() == false) return;

        receivedBytes += chunk.length;
        builder.add(chunk);

        if (totalBytes > 0) {
          onProgress(
            DownloadProgress((receivedBytes / totalBytes).clamp(0.0, 0.999)),
          );
        }
      }

      if (shouldContinue?.call() == false) return;

      final imageBytes = _decodeDownloadedImageBytes(builder.takeBytes());
      await outputFile.writeAsBytes(imageBytes, flush: true);
      onProgress(const DownloadProgress(1.0));
    } catch (e) {
      final reason = _downloadExceptionReason(e);
      debugPrint('[Download] 图片下载失败: $reason');
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      onProgress(DownloadProgress.failed(reason));
    } finally {
      _activeHttpClients.remove(task.id);
      client.close(force: true);
    }
  }

  @visibleForTesting
  static Uint8List decodeDownloadedImageBytesForTesting(Uint8List bytes) {
    return _decodeDownloadedImageBytes(bytes);
  }

  static Future<bool> repairDownloadedImageFile(DownloadTask task) async {
    if (task.mediaType != DownloadMediaType.image) return true;

    final filePath = task.filePath;
    if (filePath == null || filePath.isEmpty) return false;

    final file = File(filePath);
    if (!await file.exists()) return false;

    try {
      final bytes = await file.readAsBytes();
      final decoded = _decodeDownloadedImageBytes(bytes);
      if (!listEquals(bytes, decoded)) {
        await file.writeAsBytes(decoded, flush: true);
      }
      return true;
    } catch (e) {
      debugPrint('[Download] 图片文件校验失败: $e');
      return false;
    }
  }

  static Uint8List _decodeDownloadedImageBytes(Uint8List bytes) {
    if (_hasSupportedImageHeader(bytes)) return bytes;

    final text = utf8.decode(bytes, allowMalformed: true).trim();
    final directDataUri = _decodeDataImageUri(text);
    if (directDataUri != null) return directDataUri;

    final targetSiteText = _decodeTargetSiteImageText(text).trim();
    final targetSiteDataUri = _decodeDataImageUri(targetSiteText);
    if (targetSiteDataUri != null) return targetSiteDataUri;

    final base64Image = _decodeBase64Image(targetSiteText);
    if (base64Image != null) return base64Image;

    throw const FormatException('响应不是有效图片数据');
  }

  static Uint8List? _decodeDataImageUri(String text) {
    final match = RegExp(
      r'^data:image/[^;]+;base64,',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (match == null) return null;

    return _decodeBase64Image(text.substring(match.end));
  }

  static Uint8List? _decodeBase64Image(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 8 ||
        !RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(compact)) {
      return null;
    }

    try {
      final decoded = base64.decode(base64.normalize(compact));
      return _hasSupportedImageHeader(decoded) ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _decodeTargetSiteImageText(String text) {
    const alphabet =
        'ABCD*EFGHIJKLMNOPQRSTUVWX#YZabcdefghijklmnopqrstuvwxyz1234567890';
    final encoded = text.replaceAll(RegExp(r'[^A-Za-z0-9*#]'), '');
    if (encoded.length < 2) {
      throw const FormatException('图片编码内容为空');
    }

    final builder = BytesBuilder(copy: false);
    for (var offset = 0; offset < encoded.length; offset += 4) {
      final remaining = encoded.length - offset;
      if (remaining < 2) break;

      final first = alphabet.indexOf(encoded[offset]);
      final second = alphabet.indexOf(encoded[offset + 1]);
      final third = remaining > 2 ? alphabet.indexOf(encoded[offset + 2]) : 64;
      final fourth = remaining > 3 ? alphabet.indexOf(encoded[offset + 3]) : 64;

      if (first < 0 ||
          second < 0 ||
          (remaining > 2 && third < 0) ||
          (remaining > 3 && fourth < 0)) {
        throw const FormatException('图片编码包含非法字符');
      }

      final byte1 = (first << 2) | (second >> 4);
      builder.addByte(byte1 & 0xFF);

      if (third != 64) {
        final byte2 = ((second & 15) << 4) | (third >> 2);
        builder.addByte(byte2 & 0xFF);
      }

      if (fourth != 64) {
        final byte3 = ((third & 3) << 6) | fourth;
        builder.addByte(byte3 & 0xFF);
      }
    }

    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  static bool _hasSupportedImageHeader(List<int> bytes) {
    if (bytes.length < 4) return false;

    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }

    if (bytes.length >= 6) {
      final signature = String.fromCharCodes(bytes.take(6));
      if (signature == 'GIF87a' || signature == 'GIF89a') return true;
    }

    if (bytes.length >= 12) {
      final riff = String.fromCharCodes(bytes.take(4));
      final webp = String.fromCharCodes(bytes.skip(8).take(4));
      if (riff == 'RIFF' && webp == 'WEBP') return true;
    }

    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true;

    if (bytes.length >= 12) {
      final box = String.fromCharCodes(bytes.skip(4).take(4));
      final brand = String.fromCharCodes(bytes.skip(8).take(4));
      const heifBrands = {
        'heic',
        'heix',
        'hevc',
        'hevx',
        'heif',
        'mif1',
        'msf1',
      };
      if (box == 'ftyp' && heifBrands.contains(brand)) return true;
    }

    return false;
  }

  static Future<List<String>> _inputArgumentsForTask(DownloadTask task) async {
    final args = <String>[
      '-user_agent',
      _userAgent,
      '-rw_timeout',
      _networkIdleTimeout.inMicroseconds.toString(),
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

  static Future<String> _ffmpegFailureReason(
      FFmpegSession session, ReturnCode? returnCode,
      {List<String> liveLogs = const []}) async {
    final parts = <String>[];

    if (ReturnCode.isCancel(returnCode)) {
      parts.add('FFmpeg 任务被取消');
    } else {
      parts.add('FFmpeg 退出码 ${returnCode?.getValue() ?? '未知'}');
    }

    final failStackTrace = await _safeString(session.getFailStackTrace);
    if (failStackTrace != null && failStackTrace.trim().isNotEmpty) {
      parts.add(_compactLogText(failStackTrace));
    }

    if (liveLogs.isNotEmpty) {
      parts.add(_lastUsefulLines(liveLogs.join('\n')));
    }

    final output = await _safeString(session.getOutput);
    if (output != null && output.trim().isNotEmpty) {
      parts.add(_lastUsefulLines(output));
    }

    return parts.where((part) => part.trim().isNotEmpty).join('：').trim();
  }

  static Future<String?> _safeString(Future<String?> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }

  static String _downloadExceptionReason(Object error) {
    if (error is TimeoutException) {
      return '网络超时，${_networkIdleTimeout.inSeconds} 秒内没有响应';
    }

    if (error is HttpException) {
      final uri = error.uri;
      final target = uri == null ? '' : '，地址：$uri';
      return '${error.message}$target';
    }

    if (error is FormatException) {
      return error.message;
    }

    final text = error.toString().trim();
    if (text.isEmpty) return '未知下载错误';
    return _compactLogText(text);
  }

  static String _lastUsefulLines(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';

    final usefulLines = lines
        .where((line) =>
            line.contains('Error') ||
            line.contains('error') ||
            line.contains('Invalid') ||
            line.contains('HTTP') ||
            line.contains('403') ||
            line.contains('404') ||
            line.contains('Not Found') ||
            line.contains('Unable') ||
            line.contains('key file') ||
            line.contains('segment') ||
            line.contains('processing input') ||
            line.contains('timed out') ||
            line.contains('Failed') ||
            line.contains('failed'))
        .toList();
    final selected = usefulLines.isNotEmpty
        ? usefulLines.skip(usefulLines.length > 4 ? usefulLines.length - 4 : 0)
        : lines.skip(lines.length > 4 ? lines.length - 4 : 0);

    return _compactLogText(selected.join(' | '));
  }

  static String _compactLogText(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    const maxLength = 260;
    if (compact.length <= maxLength) return compact;
    return '...${compact.substring(compact.length - maxLength)}';
  }

  static Future<void> cancel(DownloadTask task) async {
    final session = _activeSessions[task.id];
    if (session != null) {
      print('[FFmpegCancel] 取消任务：${task.url}');
      await session.cancel();
      _activeSessions.remove(task.id);
    }

    final client = _activeHttpClients.remove(task.id);
    client?.close(force: true);
  }

  static bool isDownloadableUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return false;

    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  static const String _userAgent =
      'Mozilla/5.0 AppleWebKit/537.36 Chrome Safari';
}
