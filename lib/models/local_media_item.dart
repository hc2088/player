enum LocalMediaType {
  image,
  video,
  audio,
}

class LocalMediaItem {
  const LocalMediaItem({
    required this.assetPath,
    required this.displayName,
    required this.mediaType,
  });

  final String assetPath;
  final String displayName;
  final LocalMediaType mediaType;

  String get extension {
    final name = displayName.toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == name.length - 1) {
      return '';
    }
    return name.substring(dotIndex + 1);
  }

  bool get isImage => mediaType == LocalMediaType.image;
  bool get isVideo => mediaType == LocalMediaType.video;
  bool get isAudio => mediaType == LocalMediaType.audio;
}
