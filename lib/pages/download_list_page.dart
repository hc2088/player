import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:player/routes/route_helper.dart';
import 'dart:io';

import '../models/download_task.dart';
import '../services/download_service.dart';

class DownloadListPage extends StatelessWidget {
  const DownloadListPage({super.key});

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
            onPressed: () => Get.toNamed(RouteHelper.favorite),
          ),
        ],
      ),
      body: Obx(() {
        final tasks = downloadService.tasks;
        if (tasks.isEmpty) {
          return const Center(child: Text('暂无下载任务'));
        }
        return ListView.builder(
          padding: EdgeInsets.only(bottom: 20),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return FutureBuilder<String>(
              future: _getFullPath(task.fileName ?? ''),
              builder: (context, snapshot) {
                final filePath = snapshot.data ?? '';
                return ListTile(
                  title: Text(task.fileName ?? task.url),
                  onTap: () {
                    Get.toNamed(RouteHelper.videoWebDetail, arguments: {
                      'url': (task.originPageUrl.length > 0)
                          ? task.originPageUrl
                          : task.url
                    });
                  },
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('状态: ${task.status.name}'),
                      if (task.status == DownloadStatus.completed)
                        // Text(
                        //   '文件路径: $filePath',
                        //   style:
                        //       const TextStyle(fontSize: 12, color: Colors.grey),
                        // ),
                        if (task.status == DownloadStatus.downloading) ...[
                          Text(
                            '下载进度：${(task.progress * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.blueAccent),
                          ),
                        ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (task.status == DownloadStatus.downloading)
                        SizedBox(
                          width: 60,
                          height: 20,
                          child: LinearProgressIndicator(value: task.progress),
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
                          icon: Icon(Icons.refresh),
                          onPressed: () {
                            downloadService.retryDownload(task);
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => downloadService.removeTask(task),
                      ),
                    ],
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
