import 'dart:io';

import 'package:flutter/services.dart';

class FileShareService {
  static const MethodChannel _channel = MethodChannel('player/file_share');

  static Future<void> shareFile(
    String path, {
    String? title,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', path);
    }

    await _channel.invokeMethod<void>('shareFile', {
      'path': path,
      'title': title ?? file.uri.pathSegments.last,
    });
  }
}
