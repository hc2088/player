import 'package:flutter_test/flutter_test.dart';
import 'package:player/models/download_task.dart';

void main() {
  test('DownloadTask keeps serialized id', () {
    final task = DownloadTask(
      id: 'download_1',
      url: 'https://example.com/video.m3u8',
      originPageUrl: 'https://example.com/post',
      sourceAttachmentId: 123,
      status: DownloadStatus.pending,
    );

    final restored = DownloadTask.fromJson(task.toJson());

    expect(restored.id, 'download_1');
    expect(restored.sourceAttachmentId, 123);
  });

  test('DownloadTask creates id for old stored tasks', () {
    final restored = DownloadTask.fromJson({
      'url': 'https://example.com/video.m3u8',
      'originPageUrl': 'https://example.com/post',
      'progress': 0,
      'status': DownloadStatus.pending.index,
    });

    expect(restored.id, isNotEmpty);
  });
}
