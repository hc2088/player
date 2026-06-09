import 'dart:convert';
import 'dart:io' show HttpClient, HttpClientRequest, HttpException;

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

enum ExtractedMediaType { video, audio }

class ExtractedMediaUrl {
  const ExtractedMediaUrl({
    required this.url,
    required this.type,
    this.name,
    this.attachmentId,
  });

  final String url;
  final ExtractedMediaType type;
  final String? name;
  final int? attachmentId;

  bool get isVideo => type == ExtractedMediaType.video;
  bool get isAudio => type == ExtractedMediaType.audio;
}

class VideoExtractor {
  static Future<List<String>> extractVideoUrls(ScriptExecutor executor) async {
    final mediaItems = await extractMediaUrls(executor);
    return mediaItems
        .where((item) => item.isVideo)
        .map((item) => item.url)
        .toList();
  }

  static Future<List<ExtractedMediaUrl>> extractMediaUrls(
    ScriptExecutor executor, {
    String? pageUrl,
    String? pageTitle,
  }) async {
    final uri = pageUrl == null ? null : Uri.tryParse(pageUrl);
    final pid = _extractTargetSitePid(uri);
    if (uri != null && pid != null) {
      final targetSiteItems = await _extractTargetSiteMediaUrls(
        pageUri: uri,
        pid: pid,
        pageTitle: pageTitle,
      );
      if (targetSiteItems.isNotEmpty) {
        return _dedupe(targetSiteItems);
      }
    }

    final items = await _extractDomMediaUrls(executor, pageUri: uri);
    return _dedupe(items);
  }

  static Future<String?> refreshTargetSiteMediaUrl({
    required String pageUrl,
    required int attachmentId,
    required ExtractedMediaType type,
  }) async {
    final pageUri = Uri.tryParse(pageUrl);
    final pid = _extractTargetSitePid(pageUri);
    if (pageUri == null || pid == null) return null;

    try {
      final topicUri = _sameOriginUri(pageUri, '/api/topic/$pid');
      final topic = await _getDecodedApiData(topicUri, pageUri);
      if (topic is Map) {
        final attachments = topic['attachments'];
        if (attachments is List) {
          for (final attachment in attachments.whereType<Map>()) {
            if (_intValue(attachment['id']) != attachmentId) continue;

            final remoteUrl = _nonEmptyString(attachment['remoteUrl']);
            if (remoteUrl != null && _looksLikeMediaUrl(remoteUrl, type)) {
              final resolvedUrl = _resolveUrl(pageUri, remoteUrl);
              if (resolvedUrl != null) return resolvedUrl;
            }
          }
        }
      }
    } catch (_) {}

    final lines = await _extractTargetSiteAttachmentLines(
      pageUri: pageUri,
      pid: pid,
      attachmentId: attachmentId,
      type: type,
    );

    for (final line in lines) {
      final resolvedUrl = _resolveUrl(pageUri, line.url);
      if (resolvedUrl != null) return resolvedUrl;
    }

    return null;
  }

  static Future<List<ExtractedMediaUrl>> _extractDomMediaUrls(
    ScriptExecutor executor, {
    Uri? pageUri,
  }) async {
    try {
      const js = """
        (() => {
          const items = [];
          const push = (type, url, name) => {
            if (!url) return;
            items.push({ type, url, name: name || '' });
          };

          document.querySelectorAll('video,audio').forEach((node, index) => {
            const type = node.tagName.toLowerCase() === 'audio'
              ? 'audio'
              : 'video';
            const name = node.getAttribute('title')
              || node.getAttribute('aria-label')
              || '';
            [
              node.currentSrc,
              node.src,
              node.getAttribute('src')
            ].forEach(url => push(type, url, name));
            node.querySelectorAll('source').forEach(source => {
              push(type, source.src, name);
              push(type, source.getAttribute('src'), name);
            });
          });

          document.querySelectorAll('a[href]').forEach(link => {
            const href = link.href || link.getAttribute('href');
            const text = link.textContent || link.getAttribute('title') || '';
            if (/\\.(m3u8|mp4|mov|m4v)(\\?|#|\$)/i.test(href)) {
              push('video', href, text);
            } else if (/\\.(mp3|m4a|aac|wav|ogg|flac)(\\?|#|\$)/i.test(href)) {
              push('audio', href, text);
            }
          });

          if (window.performance && performance.getEntriesByType) {
            performance.getEntriesByType('resource').forEach(entry => {
              const url = entry.name || '';
              if (/\\.(m3u8|mp4|mov|m4v)(\\?|#|\$)/i.test(url)) {
                push('video', url, '');
              } else if (/\\.(mp3|m4a|aac|wav|ogg|flac)(\\?|#|\$)/i.test(url)) {
                push('audio', url, '');
              }
            });
          }
          return JSON.stringify(items);
        })();
      """;

      final result = await executor.evaluateJavascript(js);
      final decoded = _decodeJavascriptJson(result);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((item) {
            final rawUrl = item['url']?.toString().trim() ?? '';
            final url = _resolveDomUrl(pageUri, rawUrl);
            if (url.isEmpty) return null;
            if (!_isDownloadableWebUrl(url)) return null;
            return ExtractedMediaUrl(
              url: url,
              type: item['type'] == 'audio'
                  ? ExtractedMediaType.audio
                  : ExtractedMediaType.video,
              name: item['name']?.toString(),
            );
          })
          .whereType<ExtractedMediaUrl>()
          .toList();
    } catch (e) {
      print('媒体 DOM 提取失败: $e');
    }
    return [];
  }

  static dynamic _decodeJavascriptJson(String? result) {
    if (result == null || result.isEmpty || result == 'null') return null;

    final decoded = jsonDecode(result);
    if (decoded is String) {
      return jsonDecode(decoded);
    }
    return decoded;
  }

  static String? _extractTargetSitePid(Uri? uri) {
    if (uri == null) return null;
    if (!uri.path.contains('/post/details')) return null;

    final pid = uri.queryParameters['pid'];
    if (pid != null && pid.isNotEmpty) return pid;

    final match = RegExp(r'[?&]pid=(\d+)').firstMatch(uri.toString());
    return match?.group(1);
  }

  static Future<List<ExtractedMediaUrl>> _extractTargetSiteMediaUrls({
    required Uri pageUri,
    required String pid,
    String? pageTitle,
  }) async {
    final items = <ExtractedMediaUrl>[];

    try {
      final topicUri = _sameOriginUri(pageUri, '/api/topic/$pid');
      final topic = await _getDecodedApiData(topicUri, pageUri);
      if (topic is! Map) return items;

      final title = _nonEmptyString(topic['title']) ??
          _nonEmptyString(pageTitle) ??
          'target_site_$pid';
      final attachments = topic['attachments'];
      if (attachments is! List) return items;

      var index = 0;
      for (final rawAttachment in attachments.whereType<Map>()) {
        final category = _nonEmptyString(rawAttachment['category']);
        final type = category == 'audio'
            ? ExtractedMediaType.audio
            : category == 'video'
                ? ExtractedMediaType.video
                : null;
        if (type == null) continue;

        final attachmentId = _intValue(rawAttachment['id']);
        final urls = <_ResolvedMediaLine>[];
        final remoteUrl = _nonEmptyString(rawAttachment['remoteUrl']);
        if (remoteUrl != null && _looksLikeMediaUrl(remoteUrl, type)) {
          urls.add(_ResolvedMediaLine(url: remoteUrl));
        }

        if (attachmentId != null) {
          urls.addAll(await _extractTargetSiteAttachmentLines(
            pageUri: pageUri,
            pid: pid,
            attachmentId: attachmentId,
            type: type,
          ));
        }

        for (final line in urls) {
          final url = _resolveUrl(pageUri, line.url);
          if (url == null) continue;

          index++;
          items.add(ExtractedMediaUrl(
            url: url,
            type: type,
            attachmentId: attachmentId,
            name: _buildMediaName(title, type, index, line.name),
          ));
        }
      }
    } catch (e) {
      print('目标站点媒体提取失败: $e');
    }

    return items;
  }

  static Future<List<_ResolvedMediaLine>> _extractTargetSiteAttachmentLines({
    required Uri pageUri,
    required String pid,
    required int attachmentId,
    required ExtractedMediaType type,
  }) async {
    final lines = <_ResolvedMediaLine>[];

    try {
      final uri = _sameOriginUri(pageUri, '/api/topic/att/$attachmentId');
      final data = await _getDecodedApiData(uri, pageUri);
      lines.addAll(_extractMediaLinesFromData(data, type));
    } catch (e) {
      print('目标站点附件线路 GET 提取失败: $e');
    }

    try {
      final uri = _sameOriginUri(pageUri, '/api/attachment');
      final data = await _postDecodedApiData(
        uri,
        pageUri,
        {
          'id': attachmentId,
          'is_ios': 0,
          'resource_id': int.tryParse(pid) ?? pid,
          'resource_type': 'topic',
          'line': 'normal1',
        },
      );
      lines.addAll(_extractMediaLinesFromData(data, type));
    } catch (e) {
      print('目标站点附件线路 POST 提取失败: $e');
    }

    return lines;
  }

  static List<_ResolvedMediaLine> _extractMediaLinesFromData(
    dynamic data,
    ExtractedMediaType type,
  ) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((line) {
            final url = _firstMediaUrl(line, type);
            if (url == null) return null;
            return _ResolvedMediaLine(
              url: url,
              name: _nonEmptyString(line['name']) ??
                  _nonEmptyString(line['title']) ??
                  _nonEmptyString(line['label']),
            );
          })
          .whereType<_ResolvedMediaLine>()
          .toList();
    }

    if (data is Map) {
      final url = _firstMediaUrl(data, type);
      if (url == null) return [];
      return [
        _ResolvedMediaLine(
          url: url,
          name: _nonEmptyString(data['name']) ??
              _nonEmptyString(data['title']) ??
              _nonEmptyString(data['label']),
        ),
      ];
    }

    return [];
  }

  static String? _firstMediaUrl(Map data, ExtractedMediaType type) {
    const keys = [
      'remoteUrl',
      'remote_url',
      'm3u8_url',
      'playUrl',
      'play_url',
      'downloadUrl',
      'download_url',
      'url',
      'src',
    ];

    for (final key in keys) {
      final value = _nonEmptyString(data[key]);
      if (value != null && _looksLikeMediaUrl(value, type)) {
        return value;
      }
    }

    for (final value in data.values) {
      if (value is Map) {
        final url = _firstMediaUrl(value, type);
        if (url != null) return url;
      }

      if (value is List) {
        for (final child in value.whereType<Map>()) {
          final url = _firstMediaUrl(child, type);
          if (url != null) return url;
        }
      }
    }

    return null;
  }

  static Future<dynamic> _getDecodedApiData(Uri uri, Uri pageUri) async {
    final rawText = await _httpGet(uri, pageUri);
    return _decodeApiPayload(rawText);
  }

  static Future<dynamic> _postDecodedApiData(
    Uri uri,
    Uri pageUri,
    Map<String, Object?> body,
  ) async {
    final rawText = await _httpPostJson(uri, pageUri, body);
    return _decodeApiPayload(rawText);
  }

  static dynamic _decodeApiPayload(String rawText) {
    final payload = jsonDecode(rawText);
    if (payload is! Map) return payload;

    final data = payload['data'];
    if (payload['isEncrypted'] == true && data is String) {
      return _decodeTripleBase64Json(data);
    }

    if (payload['status'] == 200 && data is Map) {
      final nestedData = data['data'];
      if (nestedData is String && nestedData.isNotEmpty) {
        return _decodeTripleBase64Json(nestedData);
      }
      return data;
    }

    if (data is String) {
      final decoded = _tryDecodeTripleBase64Json(data);
      if (decoded != null) return decoded;
    }

    return data;
  }

  static dynamic _decodeTripleBase64Json(String value) {
    final decoded = _tryDecodeTripleBase64Json(value);
    if (decoded == null) {
      throw const FormatException('encrypted api data decode failed');
    }
    return decoded;
  }

  static dynamic _tryDecodeTripleBase64Json(String value) {
    try {
      var decoded = value;
      for (var i = 0; i < 3; i++) {
        decoded = utf8.decode(base64.decode(decoded));
      }
      return jsonDecode(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<String> _httpGet(Uri uri, Uri pageUri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      await _setCommonHeaders(request, pageUri);

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $body', uri: uri);
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _httpPostJson(
    Uri uri,
    Uri pageUri,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      await _setCommonHeaders(request, pageUri);
      request.headers.set('Content-Type', 'application/json;charset=UTF-8');
      final bodyText = jsonEncode(body);
      request.add(utf8.encode(bodyText));

      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}: $responseBody',
          uri: uri,
        );
      }
      return responseBody;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _setCommonHeaders(
    HttpClientRequest request,
    Uri pageUri,
  ) async {
    request.headers.set('Accept', 'application/json');
    request.headers.set('Referer', pageUri.toString());
    request.headers.set('User-Agent', _userAgent);
    request.headers.set('Mver', '211112203214');

    final cookies = await _cookies(pageUri);
    final cookieHeader = _cookieHeaderFromCookies(cookies);
    if (cookieHeader != null) {
      request.headers.set('Cookie', cookieHeader);
    }

    final uid = _cookieValue(cookies, 'uid');
    final token = _cookieValue(cookies, 'token');
    if (uid != null && token != null) {
      request.headers.set('X-User-Id', uid);
      request.headers.set('X-User-Token', token);
    }
  }

  static Future<List<Cookie>> _cookies(Uri pageUri) async {
    final origin = _originString(pageUri);
    return CookieManager.instance().getCookies(
      url: WebUri(origin),
    );
  }

  static String? _cookieHeaderFromCookies(List<Cookie> cookies) {
    if (cookies.isEmpty) return null;

    return cookies
        .where((cookie) => cookie.name.isNotEmpty)
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  static String? _cookieValue(List<Cookie> cookies, String name) {
    for (final cookie in cookies) {
      if (cookie.name == name && cookie.value.isNotEmpty) {
        return cookie.value;
      }
    }
    return null;
  }

  static Uri _sameOriginUri(Uri pageUri, String path) {
    return Uri.parse(_originString(pageUri)).replace(path: path);
  }

  static String _originString(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static String? _resolveUrl(Uri pageUri, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.hasScheme) return trimmed;

    return pageUri.resolveUri(uri).toString();
  }

  static String _resolveDomUrl(Uri? pageUri, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    if (pageUri == null) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return '';
    if (uri.hasScheme) return trimmed;

    return pageUri.resolveUri(uri).toString();
  }

  static bool _isDownloadableWebUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme) return false;

    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  static String? _nonEmptyString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _looksLikeMediaUrl(String value, ExtractedMediaType type) {
    final lower = value.toLowerCase();
    if (type == ExtractedMediaType.audio) {
      return RegExp(r'\.(mp3|m4a|aac|wav|ogg|flac)(\?|#|$)').hasMatch(lower);
    }

    return RegExp(r'\.(m3u8|mp4|mov|m4v)(\?|#|$)').hasMatch(lower) ||
        lower.contains('/m3u8');
  }

  static String _buildMediaName(
    String title,
    ExtractedMediaType type,
    int index,
    String? lineName,
  ) {
    final cleanTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final cleanLine = lineName == null || lineName.trim().isEmpty
        ? ''
        : '_${lineName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim()}';
    return '${cleanTitle}_${type.name}${cleanLine}_$index';
  }

  static List<ExtractedMediaUrl> _dedupe(List<ExtractedMediaUrl> items) {
    final seen = <String>{};
    final result = <ExtractedMediaUrl>[];

    for (final item in items) {
      final key = '${item.type.name}:${item.url}';
      if (seen.add(key)) {
        result.add(item);
      }
    }

    return result;
  }

  static const String _userAgent =
      'Mozilla/5.0 AppleWebKit/537.36 Chrome Safari';
}

class _ResolvedMediaLine {
  const _ResolvedMediaLine({
    required this.url,
    this.name,
  });

  final String url;
  final String? name;
}
