import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../config/event_names.dart';
import '../controllers/home_page_controller.dart';
import '../models/favorite.dart';
import '../routes/route_helper.dart';
import '../services/favorite_service.dart';
import '../utils/event_bus_helper.dart';

class FavoriteListPage extends StatefulWidget {
  final void Function(String url)? onItemTap;
  final bool isDrawerMode; // 新增参数，默认false
  final String? selectedUrl; // 新增传入默认选中 url

  const FavoriteListPage({
    super.key,
    this.onItemTap,
    this.isDrawerMode = false, // 默认为普通模式
    this.selectedUrl,
  });

  @override
  State<FavoriteListPage> createState() => _FavoriteListPageState();
}

class _FavoriteListPageState extends State<FavoriteListPage> {
  late StreamSubscription _favoriteUpdateSubscription;
  String? _selectedUrl; // 记录当前选中 url

  @override
  void initState() {
    super.initState();

    _selectedUrl = AppConfig.normalizeWebUrl(widget.selectedUrl);

    _favoriteUpdateSubscription = listenNamedEvent<FavoriteChangedEvent>(
      name: EventNames.favoriteChanged,
      onData: (event) {
        final favoriteService = Get.find<FavoriteService>();
        favoriteService.loadFavorites();
        setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _favoriteUpdateSubscription.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FavoriteListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedUrl = AppConfig.normalizeWebUrl(widget.selectedUrl);
    if (selectedUrl != AppConfig.normalizeWebUrl(oldWidget.selectedUrl)) {
      _selectedUrl = selectedUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    final favoriteService = Get.find<FavoriteService>();

    return Scaffold(
      appBar: AppBar(title: const Text('收藏列表')),
      body: Obx(() {
        final favorites = favoriteService.favorites;
        if (favorites.isEmpty) {
          return const Center(child: Text('暂无收藏'));
        }
        return ListView.builder(
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            final fav = favorites[index];

            final itemUrl = AppConfig.normalizeWebUrl(fav.url);
            final isSelected = _selectedUrl == itemUrl;

            final tile = ListTile(
              dense: widget.isDrawerMode,
              contentPadding: EdgeInsets.symmetric(
                horizontal: widget.isDrawerMode ? 14 : 16,
                vertical: widget.isDrawerMode ? 6 : 8,
              ),
              selected: isSelected,
              //selectedTileColor: Colors.blue.shade100,
              // 选中背景色
              title: _FavoriteContent(
                favorite: fav,
                selected: isSelected,
                compact: widget.isDrawerMode,
              ),
              trailing: widget.isDrawerMode
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        favoriteService.removeFavorite(fav);
                        _showMessage('已删除');
                        if (_selectedUrl == fav.url) {
                          setState(() {
                            _selectedUrl = null; // 删除时取消选中
                          });
                        }
                      },
                    ),
              onTap: () async {
                if (itemUrl.isEmpty) {
                  _showMessage('收藏地址为空');
                  return;
                }
                setState(() {
                  _selectedUrl = itemUrl;
                });
                if (widget.onItemTap != null) {
                  widget.onItemTap!(itemUrl);
                } else {
                  Get.toNamed(RouteHelper.videoWebDetail,
                      arguments: {'url': itemUrl});
                  await AppConfig.setCustomHomePageUrl(itemUrl);
                  Get.find<HomePageController>().refreshWebHome();
                }
              },
              onLongPress: () {
                _showConfirmUnfavorite(fav);
              },
            );

            if (widget.isDrawerMode) {
              return Column(
                children: [
                  tile,
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(height: 1, thickness: 1),
                  ),
                ],
              );
            } else {
              return tile;
            }
          },
        );
      }),
    );
  }

  void _showConfirmUnfavorite(Favorite fav) {
    final favoriteService = Get.find<FavoriteService>();
    showModalBottomSheet(
        context: context,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(16),
          ),
        ),
        builder: (BuildContext context) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '确认取消收藏',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // 关闭弹窗
                        },
                        child: Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // 关闭弹窗
                          favoriteService.removeFavorite(fav);
                          _showMessage('已删除');
                          if (_selectedUrl == fav.url) {
                            setState(() {
                              _selectedUrl = null; // 删除时取消选中
                            });
                          }
                        },
                        child: const Text('确定'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }
}

class _FavoriteContent extends StatelessWidget {
  const _FavoriteContent({
    required this.favorite,
    required this.selected,
    required this.compact,
  });

  final Favorite favorite;
  final bool selected;
  final bool compact;

  String get _domain {
    final parsed = Uri.tryParse(favorite.url.trim());
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.hasPort ? '${parsed.host}:${parsed.port}' : parsed.host;
    }

    final withScheme = Uri.tryParse('https://${favorite.url.trim()}');
    if (withScheme != null && withScheme.host.isNotEmpty) {
      return withScheme.hasPort
          ? '${withScheme.host}:${withScheme.port}'
          : withScheme.host;
    }

    return '未知域名';
  }

  String get _title {
    final title = favorite.title.trim();
    if (title.isNotEmpty) return title;
    if (_domain != '未知域名') return _domain;
    return favorite.url.trim().isNotEmpty ? favorite.url.trim() : '未命名网页';
  }

  @override
  Widget build(BuildContext context) {
    final titleSize = compact ? 13.0 : 15.0;
    final metaSize = compact ? 11.0 : 12.0;
    final selectedColor = selected ? Colors.blue : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _title,
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selectedColor,
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(
              Icons.public,
              size: 13,
              color: Colors.blueGrey,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _domain,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.blue : Colors.blueGrey,
                  fontSize: metaSize,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          favorite.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: metaSize,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}
