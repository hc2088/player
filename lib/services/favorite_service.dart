import 'dart:convert';

import 'package:get/get.dart';
import 'package:player/config/app_config.dart';
import 'package:player/config/event_names.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite.dart';
import '../utils/event_bus_helper.dart';

class FavoriteService extends GetxService {
  static const _storageKey = 'favorite_list';

  final RxList<Favorite> favorites = <Favorite>[].obs;

  Future<FavoriteService> init() async {
    await loadFavorites();
    return this;
  }

  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null) {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      favorites.value = jsonList.map((e) => Favorite.fromJson(e)).toList();
    }
  }

  Future<void> saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(favorites.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }

  Future<bool> addFavorite(Favorite fav) async {
    final normalizedUrl = AppConfig.normalizeWebUrl(fav.url);
    if (normalizedUrl.isEmpty) return false;

    fav.url = normalizedUrl;
    print('[FavoriteService] 尝试添加收藏: ${fav.url}');

    if (!favorites
        .any((f) => AppConfig.normalizeWebUrl(f.url) == normalizedUrl)) {
      favorites.add(fav);
      print('[FavoriteService] 添加成功: ${fav.url}');
      await saveFavorites();
      return true; // ✅ 添加成功
    } else {
      print('[FavoriteService] 收藏已存在: ${fav.url}');
      return false; // ❌ 已存在
    }
  }

  Future<void> removeFavorite(Favorite fav) async {
    final normalizedUrl = AppConfig.normalizeWebUrl(fav.url);
    favorites
        .removeWhere((f) => AppConfig.normalizeWebUrl(f.url) == normalizedUrl);
    await saveFavorites();
    emitEvent(FavoriteChangedEvent(
        name: EventNames.favoriteChanged,
        url: normalizedUrl,
        isFavorite: false));
  }

  Future<bool> removeFavoriteUrl(String url) async {
    final normalizedUrl = AppConfig.normalizeWebUrl(url);
    favorites
        .removeWhere((f) => AppConfig.normalizeWebUrl(f.url) == normalizedUrl);
    await saveFavorites();
    emitEvent(FavoriteChangedEvent(
        name: EventNames.favoriteChanged,
        url: normalizedUrl,
        isFavorite: false));
    return true;
  }

  bool isFavorite(String url) {
    final normalizedUrl = AppConfig.normalizeWebUrl(url);
    return favorites
        .any((f) => AppConfig.normalizeWebUrl(f.url) == normalizedUrl);
  }
}
