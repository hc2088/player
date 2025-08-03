import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:player/routes/route_helper.dart';
import 'dart:io';

import '../models/download_task.dart';
import '../services/download_service.dart';

class DownloadListPage extends StatefulWidget {
  const DownloadListPage({super.key});

  @override
  State<DownloadListPage> createState() => _DownloadListPageState();
}

class _DownloadListPageState extends State<DownloadListPage> {
  Future<String> _getFullPath(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$fileName';
  }

  @override
  Widget build(BuildContext context) {
    final downloadService = Get.find<DownloadService>();
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('下载列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: '收藏列表',
            onPressed: () => RouteHelper.toUnique(RouteHelper.favorite),
          ),
        ],
      ),
      body: Obx(() {
        final tasks = downloadService.tasks;
        if (tasks.isEmpty) {
          return const Center(child: Text('暂无下载任务'));
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 20),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return FutureBuilder<String>(
              future: _getFullPath(task.fileName ?? ''),
              builder: (context, snapshot) {
                final filePath = snapshot.data ?? '';
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Get.toNamed(RouteHelper.videoWebDetail, arguments: {
                        'url': (task.originPageUrl.isNotEmpty)
                            ? task.originPageUrl
                            : task.url,
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 封面图
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              color: Colors.black, // 黑色背景
                              width: double.infinity,
                              height: 180,
                              child: (task.thumbnailPath != null &&
                                      File(task.thumbnailPath!).existsSync())
                                  ? Image.file(
                                      File(task.thumbnailPath!),
                                      fit: BoxFit.fitHeight,
                                    )
                                  : Container(
                                      color: Colors.grey[300],
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.videocam,
                                          color: Colors.white54, size: 48),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 标题
                          Text(
                            task.fileName ?? task.url,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // 状态、进度
                          Row(
                            children: [
                              Text('状态: ${task.status.name}'),
                              if (task.status ==
                                  DownloadStatus.downloading) ...[
                                const SizedBox(width: 12),
                                Text(
                                  '下载进度：${(task.progress * 100).toStringAsFixed(1)}%',
                                  style:
                                      const TextStyle(color: Colors.blueAccent),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          // 按钮区
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (task.status == DownloadStatus.downloading)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: LinearProgressIndicator(
                                        value: task.progress),
                                  ),
                                ),
                              if (task.status == DownloadStatus.completed)
                                IconButton(
                                  icon: const Icon(Icons.play_arrow),
                                  onPressed: () async {
                                    if (await File(filePath).exists()) {
                                      Get.toNamed(RouteHelper.player,
                                          arguments: filePath);
                                    } else {
                                      Get.snackbar('错误', '文件不存在');
                                    }
                                  },
                                ),
                              if (task.status != DownloadStatus.completed &&
                                  task.status != DownloadStatus.downloading)
                                IconButton(
                                  icon: const Icon(Icons.refresh),
                                  onPressed: () =>
                                      downloadService.retryDownload(task),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () =>
                                    downloadService.removeTask(task),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      }),
    );
  }
}
