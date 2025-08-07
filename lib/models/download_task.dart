import 'package:get/get.dart';

import '../services/download_service.dart';

enum DownloadStatus { pending, downloading, completed, failed, canceled }

class DownloadTask {
  String url;
  String originPageUrl;
  String? fileName;
  double progress;

  Rx<DownloadStatus> statusRx;

  DownloadStatus get status => statusRx.value;

  set status(DownloadStatus value) => statusRx.value = value;

  String? thumbnailPath; // 新增封面路径
  String? filePath; //本地绝对路径

  // 运行时使用，不参与序列化
  dynamic session; // FFmpegSession? 类型，可在运行中取消任务

  DownloadTask({
    required this.url,
    required this.originPageUrl,
    required DownloadStatus status,
    this.fileName,
    this.progress = 0.0,
    this.session,
    this.thumbnailPath,
    this.filePath,
  }) : statusRx = status.obs;

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      url: json['url'] ?? "",
      originPageUrl: json['originPageUrl'] ?? "",
      fileName: json['fileName'],
      progress: (json['progress'] as num).toDouble(),
      status: DownloadStatus.values[json['status']],
      thumbnailPath: json['thumbnailPath'],
      filePath: json['filePath'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'originPageUrl': originPageUrl,
      'fileName': fileName,
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
}
