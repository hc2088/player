import 'dart:io';

import 'package:blur/blur.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';

import '../models/download_task.dart';
import '../services/download_service.dart';
import '../routes/route_helper.dart';

class DownloadListPage extends StatefulWidget {
  const DownloadListPage({super.key});

  @override
  State<DownloadListPage> createState() => _DownloadListPageState();
}

class _DownloadListPageState extends State<DownloadListPage> {
  final DownloadService _downloadService = Get.find<DownloadService>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载列表'),
        // actions: [
        //   IconButton(
        //     icon: const Icon(Icons.favorite),
        //     tooltip: '收藏列表',
        //     onPressed: () => Get.toNamed(RouteHelper.favorite),
        //   ),
        // ],
      ),
      body: Obx(() {
        final tasks = _downloadService.tasks;
        if (tasks.isEmpty) {
          return const Center(child: Text('暂无下载任务'));
        }

        return MasonryGridView.count(
          crossAxisCount: 2,
          // 两列布局
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          itemCount: tasks.length,
          padding: const EdgeInsets.all(8.0),
          itemBuilder: (context, index) {
            final task = tasks[index];
            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Colors.grey.withOpacity(0.1),
                  width: 1, // 1 像素边框
                ),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 0, // 不要阴影
              child: InkWell(
                onTap: () => Get.toNamed(RouteHelper.videoSwiper,
                    arguments: {'initialIndex': index}),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 视频缩略图或占位
                    Container(
                      color: Colors.grey[300],
                      child: (task.thumbnailPath != null &&
                              File(task.thumbnailPath!).existsSync())
                          ? Image.file(
                              File(task.thumbnailPath!),
                              fit: BoxFit.cover,
                            ).blurred(
                              blur: 20,
                              blurColor: Colors.black26,
                              overlay: Container(
                                alignment: Alignment.center,
                                child: Image.file(
                                  File(task.thumbnailPath!),
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                ),
                              ),
                            )
                          : AspectRatio(
                              aspectRatio: 16 / 9,
                              child: const Icon(
                                Icons.videocam_off_outlined,
                                size: 48,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                    // 文件名
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        task.fileName ?? task.url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),

                    // 下载状态显示和进度条 + 百分比
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('状态: ${task.status.name}'),
                          if (task.status == DownloadStatus.downloading)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: task.progress,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(task.progress * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 4),

                    // 底部按钮组
                    OverflowBar(
                      alignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 跳转原网页
                        IconButton(
                          tooltip: '打开原网页',
                          icon: const Icon(Icons.language,
                              color: Colors.blueAccent),
                          onPressed: () {
                            final url = task.originPageUrl.isNotEmpty
                                ? task.originPageUrl
                                : task.url;
                            Get.toNamed(RouteHelper.videoWebDetail,
                                arguments: {'url': url});
                          },
                        ),

                        // 重新下载按钮
                        if (task.status != DownloadStatus.completed &&
                            task.status != DownloadStatus.downloading)
                          IconButton(
                            tooltip: '重新下载',
                            icon:
                                const Icon(Icons.refresh, color: Colors.orange),
                            onPressed: () {
                              _downloadService.retryDownload(task);
                            },
                          ),

                        // 取消删除按钮
                        IconButton(
                          tooltip: '取消/删除任务',
                          icon:
                              const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () {
                            _downloadService.removeTask(task);
                          },
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
