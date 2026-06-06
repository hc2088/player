import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import '../models/local_media_item.dart';

enum _OpenSslDigest {
  sha256,
  md5,
}

class LocalMediaService {
  static const String assetDirectory = 'assets/local_media/';
  static const String assetIndexPath = '${assetDirectory}index.json';
  static const String unlockPasswordMd5 = '7d573eff533d0dfcf742aa2fb0706db1';

  static final Set<String> _encryptedExtensions = {'.cpp', '.dat'};
  static final Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };
  static final Set<String> _videoExtensions = {'mp4'};
  static final Set<String> _audioExtensions = {
    'mp3',
    'm4a',
    'aac',
    'wav',
    'ogg',
    'flac',
  };

  static String normalizePassword(String password) {
    return password.replaceAll(RegExp(r'[\n\r]'), '').trim();
  }

  static bool isUnlockPassword(String password) {
    final normalized = normalizePassword(password);
    if (normalized.isEmpty) return false;

    final digest = crypto.md5.convert(utf8.encode(normalized)).toString();
    return digest == unlockPasswordMd5;
  }

  Future<List<LocalMediaItem>> loadItems() async {
    final assetPaths = await _loadAssetPaths();

    final items = <LocalMediaItem>[];
    for (final assetPath in assetPaths) {
      if (!assetPath.startsWith(assetDirectory)) continue;
      if (assetPath == assetIndexPath) continue;

      final encryptedExtension = _matchedEncryptedExtension(assetPath);
      if (encryptedExtension == null) continue;

      final fileName = assetPath.split('/').last;
      final displayName = fileName.substring(
        0,
        fileName.length - encryptedExtension.length,
      );
      final mediaType = _mediaTypeForName(displayName);
      if (mediaType == null) continue;

      items.add(LocalMediaItem(
        assetPath: assetPath,
        displayName: displayName,
        mediaType: mediaType,
      ));
    }

    items.sort((a, b) => a.displayName.compareTo(b.displayName));
    return items;
  }

  Future<List<String>> _loadAssetPaths() async {
    try {
      final indexJson = await rootBundle.loadString(assetIndexPath);
      final indexData = jsonDecode(indexJson);
      if (indexData is List) {
        return indexData.cast<String>();
      }
      if (indexData is Map && indexData['assets'] is List) {
        return (indexData['assets'] as List).cast<String>();
      }
    } catch (_) {
      // Fall back to Flutter's generated binary manifest.
    }

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets();
  }

  Future<File> decryptToTempFile(
    LocalMediaItem item,
    String password,
  ) async {
    final normalizedPassword = normalizePassword(password);
    if (!isUnlockPassword(normalizedPassword)) {
      throw const FormatException('password is invalid');
    }

    final tempDir = await getTemporaryDirectory();
    final outputDir = Directory('${tempDir.path}/local_bundle_media');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final outputFile = File('${outputDir.path}/${_safeOutputName(item)}');
    if (await outputFile.exists() && await outputFile.length() > 0) {
      return outputFile;
    }

    final data = await rootBundle.load(item.assetPath);
    final encryptedBytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final decryptedBytes = _decryptOpenSslBytes(
      encryptedBytes,
      normalizedPassword,
      item,
    );

    await outputFile.writeAsBytes(decryptedBytes, flush: true);
    return outputFile;
  }

  static String? _matchedEncryptedExtension(String path) {
    final lowerPath = path.toLowerCase();
    for (final extension in _encryptedExtensions) {
      if (lowerPath.endsWith(extension)) {
        return path.substring(path.length - extension.length);
      }
    }
    return null;
  }

  static LocalMediaType? _mediaTypeForName(String fileName) {
    final extension = _extensionOf(fileName);
    if (_imageExtensions.contains(extension)) {
      return LocalMediaType.image;
    }
    if (_videoExtensions.contains(extension)) {
      return LocalMediaType.video;
    }
    if (_audioExtensions.contains(extension)) {
      return LocalMediaType.audio;
    }
    return null;
  }

  static String _extensionOf(String fileName) {
    final lowerName = fileName.toLowerCase();
    final dotIndex = lowerName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == lowerName.length - 1) {
      return '';
    }
    return lowerName.substring(dotIndex + 1);
  }

  static String _safeOutputName(LocalMediaItem item) {
    final digest = crypto.md5.convert(utf8.encode(item.assetPath)).toString();
    final cleanName = item.displayName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    return '${digest}_$cleanName';
  }

  static Uint8List _decryptOpenSslBytes(
    Uint8List encryptedBytes,
    String password,
    LocalMediaItem item,
  ) {
    final encodedText = utf8.decode(encryptedBytes).replaceAll(
          RegExp(r'\s+'),
          '',
        );
    final payload = base64.decode(encodedText);
    final payloadBytes = Uint8List.fromList(payload);

    if (payloadBytes.length <= 16) {
      throw const FormatException('encrypted file is too short');
    }

    final magic = ascii.decode(payloadBytes.sublist(0, 8));
    if (magic != 'Salted__') {
      throw const FormatException('missing OpenSSL salt header');
    }

    final salt = payloadBytes.sublist(8, 16);
    final cipherText = payloadBytes.sublist(16);

    for (final digest in _OpenSslDigest.values) {
      try {
        final keyAndIv = _deriveKeyAndIv(
          password: utf8.encode(password),
          salt: salt,
          digest: digest,
        );
        final decrypted = _decryptAes256Cbc(
          cipherText: cipherText,
          key: keyAndIv.sublist(0, 32),
          iv: keyAndIv.sublist(32, 48),
        );

        if (_looksLikeExpectedMedia(decrypted, item)) {
          return decrypted;
        }
      } catch (_) {
        continue;
      }
    }

    throw const FormatException('decrypt failed');
  }

  static Uint8List _deriveKeyAndIv({
    required List<int> password,
    required List<int> salt,
    required _OpenSslDigest digest,
  }) {
    final output = <int>[];
    var previous = <int>[];

    while (output.length < 48) {
      final input = <int>[...previous, ...password, ...salt];
      previous = _digest(input, digest);
      output.addAll(previous);
    }

    return Uint8List.fromList(output.take(48).toList());
  }

  static List<int> _digest(List<int> input, _OpenSslDigest digest) {
    switch (digest) {
      case _OpenSslDigest.sha256:
        return crypto.sha256.convert(input).bytes;
      case _OpenSslDigest.md5:
        return crypto.md5.convert(input).bytes;
    }
  }

  static Uint8List _decryptAes256Cbc({
    required Uint8List cipherText,
    required Uint8List key,
    required Uint8List iv,
  }) {
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
    cipher.init(
      false,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );

    return cipher.process(cipherText);
  }

  static bool _looksLikeExpectedMedia(Uint8List bytes, LocalMediaItem item) {
    if (bytes.length < 12) return false;

    switch (item.extension) {
      case 'jpg':
      case 'jpeg':
        return bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
      case 'png':
        return bytes[0] == 0x89 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x4e &&
            bytes[3] == 0x47;
      case 'webp':
        return ascii.decode(bytes.sublist(0, 4), allowInvalid: true) ==
                'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
      case 'mp4':
        return ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp';
      case 'mp3':
        return ascii.decode(bytes.sublist(0, 3), allowInvalid: true) == 'ID3' ||
            (bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0);
      case 'm4a':
      case 'aac':
        return ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp';
      case 'wav':
        return ascii.decode(bytes.sublist(0, 4), allowInvalid: true) ==
                'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WAVE';
      case 'ogg':
        return ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'OggS';
      case 'flac':
        return ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'fLaC';
    }

    return false;
  }
}
