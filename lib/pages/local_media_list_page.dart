import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/download_task.dart';
import '../models/local_media_item.dart';
import '../routes/route_helper.dart';
import '../services/local_media_service.dart';
import '../widgets/password_input_dialog.dart';

class LocalMediaListPage extends StatefulWidget {
  const LocalMediaListPage({
    super.key,
    this.initialPassword,
    this.onHideEntry,
  });

  final String? initialPassword;
  final VoidCallback? onHideEntry;

  @override
  State<LocalMediaListPage> createState() => _LocalMediaListPageState();
}

class _LocalMediaListPageState extends State<LocalMediaListPage> {
  final LocalMediaService _service = LocalMediaService();

  late Future<List<LocalMediaItem>> _itemsFuture;
  String? _password;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _password = widget.initialPassword;
    _itemsFuture = _service.loadItems();
  }

  Future<void> _reload() async {
    setState(() {
      _itemsFuture = _service.loadItems();
    });
  }

  Future<String?> _askPassword() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PasswordInputDialog(title: '解密验证'),
    );
  }

  Future<void> _openItem(LocalMediaItem item) async {
    var password = _password;
    if (password == null || password.isEmpty) {
      password = await _askPassword();
      if (password == null || password.isEmpty) return;
    }

    if (!LocalMediaService.isUnlockPassword(password)) {
      _password = null;
      _showMessage('密码有误');
      return;
    }

    setState(() {
      _opening = true;
    });

    try {
      final file = await _service.decryptToTempFile(item, password);
      _password = LocalMediaService.normalizePassword(password);

      if (!mounted) return;

      if (item.isVideo || item.isAudio) {
        await Get.toNamed(
          RouteHelper.player,
          arguments: {
            'path': file.path,
            'title': item.displayName,
            'mediaType': item.isAudio
                ? DownloadMediaType.audio
                : DownloadMediaType.video,
          },
        );
      } else {
        await Get.toNamed(
          RouteHelper.localImageViewer,
          arguments: {
            'path': file.path,
            'title': item.displayName,
          },
        );
      }
    } catch (_) {
      _password = null;
      _showMessage('解密失败，请确认密码和加密文件格式');
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    });
  }

  Widget _buildItem(LocalMediaItem item) {
    final isVideo = item.mediaType == LocalMediaType.video;
    final isAudio = item.mediaType == LocalMediaType.audio;
    final iconColor = isAudio
        ? Colors.deepOrange
        : isVideo
            ? Colors.indigo
            : Colors.green;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.1),
        child: Icon(
          isAudio
              ? Icons.audiotrack_outlined
              : isVideo
                  ? Icons.movie_outlined
                  : Icons.image_outlined,
          color: iconColor,
        ),
      ),
      title: Text(
        item.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        isAudio
            ? '音频'
            : isVideo
                ? '视频'
                : '图片',
      ),
      trailing: const Icon(Icons.lock_outline),
      onTap: _opening ? null : () => _openItem(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地文件'),
        actions: [
          if (widget.onHideEntry != null)
            IconButton(
              tooltip: '隐藏入口',
              onPressed: _opening ? null : widget.onHideEntry,
              icon: const Icon(Icons.visibility_off_outlined),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          FutureBuilder<List<LocalMediaItem>>(
            future: _itemsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '本地文件读取失败\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final items = snapshot.data ?? const <LocalMediaItem>[];
              if (items.isEmpty) {
                return const Center(child: Text('暂无本地文件'));
              }

              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _buildItem(items[index]),
                ),
              );
            },
          ),
          if (_opening)
            Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
