import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // 视频详情页面的默认地址
  static const String defaultVideoUrl = 'https://www.baidu.com/';

  static Future<String> getDefaultVideoUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('customHomePageUrl') ?? defaultVideoUrl;
  }

  static Future<void> setCustomHomePageUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customHomePageUrl', url);
  }

  static Future<void> resetHomePageUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('customHomePageUrl');
  }
}
