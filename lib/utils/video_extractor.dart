import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

abstract class ScriptExecutor {
  Future<String?> evaluateJavascript(String js);
}

class InAppWebViewScriptExecutor implements ScriptExecutor {
  final InAppWebViewController controller;

  InAppWebViewScriptExecutor(this.controller);

  @override
  Future<String?> evaluateJavascript(String js) async {
    final result = await controller.evaluateJavascript(source: js);
    return result?.toString();
  }
}

class WebViewScriptExecutor implements ScriptExecutor {
  final WebViewController controller;

  WebViewScriptExecutor(this.controller);

  @override
  Future<String?> evaluateJavascript(String js) async {
    final result = await controller.runJavaScriptReturningResult(js);
    return result.toString();
  }
}

class VideoExtractor {
  static Future<List<String>> extractVideoUrls(ScriptExecutor executor) async {
    try {
      const js = """
        (() => {
          const videos = document.querySelectorAll('video');
          let urls = [];
          videos.forEach(v => {
            if(v.src) urls.push(v.src);
            else {
              const sources = v.querySelectorAll('source');
              sources.forEach(s => {
                if(s.src) urls.push(s.src);
              });
            }
          });
          return JSON.stringify(urls);
        })();
      """;

      final result = await executor.evaluateJavascript(js);
      if (result != null && result.isNotEmpty) {
        final decoded = jsonDecode(result);
        return List<String>.from(decoded);
      }
    } catch (e) {
      print('视频提取失败: $e');
    }
    return [];
  }
}
