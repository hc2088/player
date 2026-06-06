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
}
