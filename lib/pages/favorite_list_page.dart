import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:player/utils/string_ext.dart';

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

    _selectedUrl = widget.selectedUrl;

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

            final isSelected = _selectedUrl == fav.url;

            final tile = ListTile(
              selected: isSelected,
              //selectedTileColor: Colors.blue.shade100,
              // 选中背景色
              title: widget.isDrawerMode
                  ? Text(
                      "${index + 1}、${fav.title.breakWord}",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.blue : null, // 选中文字颜色
                      ),
                    )
                  : Text(
                      fav.title.isNotEmpty ? fav.title : fav.url,
                      style: TextStyle(
                        color: isSelected ? Colors.blue : null,
                      ),
                    ),
              subtitle: widget.isDrawerMode ? null : Text(fav.url),
              trailing: widget.isDrawerMode
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        favoriteService.removeFavorite(fav);
                        Get.snackbar('收藏', '已删除');
                        if (_selectedUrl == fav.url) {
                          setState(() {
                            _selectedUrl = null; // 删除时取消选中
                          });
                        }
                      },
                    ),
              onTap: () async {
                setState(() {
                  _selectedUrl = fav.url;
                });
                if (widget.onItemTap != null) {
                  widget.onItemTap!(fav.url);
                } else {
                  Get.toNamed(RouteHelper.videoWebDetail,
                      arguments: {'url': fav.url});
                  await AppConfig.setCustomHomePageUrl(fav.url);
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
            top: Radius.circular(16),
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                          // 这里写确定逻辑，例如取消收藏
                          print('已取消收藏');
                          Navigator.of(context).pop(); // 关闭弹窗
                          favoriteService.removeFavorite(fav);
                          Get.snackbar('收藏', '已删除');
                          if (_selectedUrl == fav.url) {
                            setState(() {
                              _selectedUrl = null; // 删除时取消选中
                            });
                          }
                        },
                        child: Text('确定'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
  }
}
