enum DownloadStatus { pending, downloading, completed, failed, canceled }

class DownloadTask {
  String url;
  String originPageUrl;
  String? fileName;
  double progress;
  DownloadStatus status;

  // 运行时使用，不参与序列化
  dynamic session; // FFmpegSession? 类型，可在运行中取消任务

  DownloadTask({
    required this.url,
    required this.originPageUrl,
    this.fileName,
    this.progress = 0.0,
    this.status = DownloadStatus.pending,
    this.session,
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      url: json['url'] ?? "",
      originPageUrl: json['originPageUrl'] ?? "",
      fileName: json['fileName'],
      progress: (json['progress'] as num).toDouble(),
      status: DownloadStatus.values[json['status']],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'originPageUrl': originPageUrl,
      'fileName': fileName,
      'progress': progress,
      'status': status.index,
    };
  }

  static List<DownloadTask> fromJsonList(List<dynamic> list) {
    return list.map((e) => DownloadTask.fromJson(e)).toList();
  }

  static List<Map<String, dynamic>> toJsonList(List<DownloadTask> list) {
    return list.map((e) => e.toJson()).toList();
  }
}
