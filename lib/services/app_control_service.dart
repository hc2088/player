import 'package:flutter/services.dart';

class AppControlService {
  static const MethodChannel _channel = MethodChannel('player/app_control');

  static Future<void> exitApp() async {
    try {
      await _channel.invokeMethod<void>('exitApp');
    } on MissingPluginException {
      await SystemNavigator.pop();
    } on PlatformException {
      await SystemNavigator.pop();
    }
  }
}
