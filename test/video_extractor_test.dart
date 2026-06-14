import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/utils/video_extractor.dart';

class _FakeScriptExecutor implements ScriptExecutor {
  _FakeScriptExecutor(this.result);

  final String result;

  @override
  Future<String?> evaluateJavascript(String js) async => result;
}

void main() {
  test('extractMediaUrls returns every audio item and dedupes repeats',
      () async {
    final executor = _FakeScriptExecutor(jsonEncode([
      {
        'type': 'audio',
        'url': 'https://media.example.com/voice-a.mp3',
        'name': 'voice a',
      },
      {
        'type': 'audio',
        'url': 'https://media.example.com/voice-b.mp3',
        'name': 'voice b',
      },
      {
        'type': 'audio',
        'url': 'https://media.example.com/voice-a.mp3',
        'name': 'voice a duplicate',
      },
      {
        'type': 'video',
        'url': 'https://media.example.com/movie.m3u8',
        'name': 'movie',
      },
    ]));

    final items = await VideoExtractor.extractMediaUrls(executor);
    final audioItems = items.where((item) => item.isAudio).toList();

    expect(items, hasLength(3));
    expect(audioItems, hasLength(2));
    expect(
      audioItems.map((item) => item.url),
      containsAll([
        'https://media.example.com/voice-a.mp3',
        'https://media.example.com/voice-b.mp3',
      ]),
    );
  });

  test('extractMediaUrls skips blob urls and keeps downloadable urls',
      () async {
    final executor = _FakeScriptExecutor(jsonEncode([
      {
        'type': 'video',
        'url': 'blob:https://example.com/session-video',
        'name': 'temporary video',
      },
      {
        'type': 'video',
        'url': 'https://media.example.com/movie.mp4',
        'name': 'movie',
      },
      {
        'type': 'audio',
        'url': 'data:audio/mp3;base64,AAA',
        'name': 'inline audio',
      },
    ]));

    final items = await VideoExtractor.extractMediaUrls(executor);

    expect(items, hasLength(1));
    expect(items.single.url, 'https://media.example.com/movie.mp4');
    expect(items.single.isVideo, isTrue);
  });

  test('extractMediaUrls returns image items', () async {
    final executor = _FakeScriptExecutor(jsonEncode([
      {
        'type': 'image',
        'url': 'https://media.example.com/photo-a.jpg',
        'name': 'photo a',
      },
      {
        'type': 'image',
        'url': 'https://media.example.com/photo-b.webp.txt?size=large',
        'name': 'photo b',
      },
      {
        'type': 'image',
        'url': 'data:image/png;base64,AAA',
        'name': 'inline image',
      },
      {
        'type': 'image',
        'url': 'https://media.example.com/photo-a.jpg',
        'name': 'photo a duplicate',
      },
    ]));

    final items = await VideoExtractor.extractMediaUrls(executor);
    final imageItems = items.where((item) => item.isImage).toList();

    expect(items, hasLength(2));
    expect(imageItems, hasLength(2));
    expect(
      imageItems.map((item) => item.url),
      containsAll([
        'https://media.example.com/photo-a.jpg',
        'https://media.example.com/photo-b.webp.txt?size=large',
      ]),
    );
  });
}
