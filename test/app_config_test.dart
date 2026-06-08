import 'package:flutter_test/flutter_test.dart';
import 'package:player/config/app_config.dart';

void main() {
  test('normalizeWebUrl keeps http and https URLs', () {
    expect(
      AppConfig.normalizeWebUrl('https://examplehj.com/post/details?pid=1'),
      'https://examplehj.com/post/details?pid=1',
    );
    expect(
      AppConfig.normalizeWebUrl('http://example.com/a'),
      'http://example.com/a',
    );
  });

  test('normalizeWebUrl adds https for legacy favorite URLs', () {
    expect(
      AppConfig.normalizeWebUrl('examplehj.com/post/details?pid=1'),
      'https://examplehj.com/post/details?pid=1',
    );
  });

  test('normalizeWebUrl trims blank input', () {
    expect(AppConfig.normalizeWebUrl('   '), '');
    expect(AppConfig.normalizeWebUrl(null), '');
  });
}
