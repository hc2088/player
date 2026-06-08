import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // 视频详情页面的默认地址
  static const String defaultVideoUrl = 'https://www.baidu.com/';

  static String normalizeWebUrl(String? url) {
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return '';

    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }

    return 'https://$trimmed';
  }

  static Future<String> getDefaultVideoUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = normalizeWebUrl(prefs.getString('customHomePageUrl'));
    return url.isNotEmpty ? url : defaultVideoUrl;
  }

  static Future<void> setCustomHomePageUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizeWebUrl(url);
    if (normalized.isEmpty) {
      await prefs.remove('customHomePageUrl');
      return;
    }
    await prefs.setString('customHomePageUrl', normalized);
  }

  static Future<void> resetHomePageUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('customHomePageUrl');
  }
}
