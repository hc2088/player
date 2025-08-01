import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/favorite.dart';
import '../routes/route_helper.dart';
import '../services/favorite_service.dart';
import '../utils/event_bus_helper.dart';

class FavoriteListPage extends StatefulWidget {
  const FavoriteListPage({super.key});

  @override
  State<FavoriteListPage> createState() => _FavoriteListPageState();
}

class _FavoriteListPageState extends State<FavoriteListPage> {
  late StreamSubscription _favoriteUpdateSubscription;

  @override
  void initState() {
    super.initState();
    _favoriteUpdateSubscription =
        eventBus.on<FavoriteChangedEvent>().listen((event) {
      final favoriteService = Get.find<FavoriteService>();

      // 这里调用刷新方法，通常是刷新favorites列表
      favoriteService.loadFavorites();
      setState(() {}); // 触发UI刷新
    });
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
            return ListTile(
              title: Text(fav.title.isNotEmpty ? fav.title : fav.url),
              subtitle: Text(fav.url),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () {
                  favoriteService.removeFavorite(fav);
                  Get.snackbar('收藏', '已删除');
                },
              ),
              onTap: () {
                Get.toNamed(RouteHelper.videoWebDetail,
                    arguments: {'url': fav.url});
              },
            );
          },
        );
      }),
    );
  }
}
