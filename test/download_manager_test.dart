import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/models/download_task.dart';
import 'package:player/services/download_manager.dart';

void main() {
  test('decodeDownloadedImageBytes keeps raw image bytes', () {
    final rawJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00]);

    final decoded =
        DownloadManager.decodeDownloadedImageBytesForTesting(rawJpeg);

    expect(decoded, orderedEquals(rawJpeg));
  });

  test('decodeDownloadedImageBytes decodes target site image text', () {
    const encoded = '#FEyXSnnZVEl#R8oaFUlN1Ifa1T1MCutNVmtPT*8OP';

    final decoded = DownloadManager.decodeDownloadedImageBytesForTesting(
      Uint8List.fromList(utf8.encode(encoded)),
    );

    expect(decoded, orderedEquals([0xFF, 0xD8, 0xFF, 0x00]));
  });

  test('repairDownloadedImageFile rewrites target site text as image bytes',
      () async {
    const encoded = '#FEyXSnnZVEl#R8oaFUlN1Ifa1T1MCutNVmtPT*8OP';
    final dir = await Directory.systemTemp.createTemp('download_manager_test_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final file = File('${dir.path}/image.jpg');
    await file.writeAsString(encoded);
    final task = DownloadTask(
      id: 'image_task',
      url: 'https://example.com/image.jpeg.txt',
      originPageUrl: 'https://example.com/post',
      status: DownloadStatus.completed,
      mediaType: DownloadMediaType.image,
      filePath: file.path,
    );

    final repaired = await DownloadManager.repairDownloadedImageFile(task);

    expect(repaired, isTrue);
    expect(await file.readAsBytes(), orderedEquals([0xFF, 0xD8, 0xFF, 0x00]));
  });
}
