import 'package:get/get.dart';

enum DownloadStatus { pending, downloading, completed, failed, canceled }

enum DownloadMediaType { video, audio }

class DownloadTask {
  String id;
  String url;
  String originPageUrl;
  int? sourceAttachmentId;
  String? fileName;
  DownloadMediaType mediaType;
  double progress;

  Rx<DownloadStatus> statusRx;

  DownloadStatus get status => statusRx.value;

  set status(DownloadStatus value) => statusRx.value = value;

  String? thumbnailPath; // 新增封面路径
  String? filePath; //本地绝对路径

  // 运行时使用，不参与序列化
  dynamic session; // FFmpegSession? 类型，可在运行中取消任务

  DownloadTask({
    String? id,
    required this.url,
    required this.originPageUrl,
    this.sourceAttachmentId,
    required DownloadStatus status,
    this.mediaType = DownloadMediaType.video,
    this.fileName,
    this.progress = 0.0,
    this.session,
    this.thumbnailPath,
    this.filePath,
  })  : id = id ?? _newId(),
        statusRx = status.obs;

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final mediaTypeIndex = json['mediaType'];
    return DownloadTask(
      id: json['id']?.toString(),
      url: json['url'] ?? "",
      originPageUrl: json['originPageUrl'] ?? "",
      sourceAttachmentId: _intFromJson(json['sourceAttachmentId']),
      fileName: json['fileName'],
      progress: (json['progress'] as num).toDouble(),
      status: DownloadStatus.values[json['status']],
      mediaType: mediaTypeIndex is int &&
              mediaTypeIndex >= 0 &&
              mediaTypeIndex < DownloadMediaType.values.length
          ? DownloadMediaType.values[mediaTypeIndex]
          : DownloadMediaType.video,
      thumbnailPath: json['thumbnailPath'],
      filePath: json['filePath'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'originPageUrl': originPageUrl,
      'sourceAttachmentId': sourceAttachmentId,
      'fileName': fileName,
      'mediaType': mediaType.index,
      'progress': progress,
      'status': status.index,
      'thumbnailPath': thumbnailPath,
      'filePath': filePath,
    };
  }

  static List<DownloadTask> fromJsonList(List<dynamic> list) {
    return list.map((e) => DownloadTask.fromJson(e)).toList();
  }

  static List<Map<String, dynamic>> toJsonList(List<DownloadTask> list) {
    return list.map((e) => e.toJson()).toList();
  }

  static int _idSequence = 0;

  static int? _intFromJson(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static String _newId() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final sequence = (_idSequence++).toRadixString(36);
    return '${time}_$sequence';
  }
}
