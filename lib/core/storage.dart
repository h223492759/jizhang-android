import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// 本地持久化：服务器地址、登录态、当前账本。
class Storage {
  static const _kServer = 'server_url';
  static const _kToken = 'token';
  static const _kUser = 'user_json';
  static const _kBookId = 'book_id';
  static const _kBooks = 'books_json';

  static SharedPreferences? _sp;
  static Future<SharedPreferences> get sp async =>
      _sp ??= await SharedPreferences.getInstance();

  static Future<String?> getServerUrl() async => (await sp).getString(_kServer);
  static Future<void> setServerUrl(String v) async =>
      (await sp).setString(_kServer, v);

  static const _kServers = 'servers';
  static Future<List<String>> getServers() async {
    final s = await sp;
    final raw = s.getString(_kServers);
    if (raw != null) {
      try {
        return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    final cur = s.getString(_kServer);
    if (cur != null && cur.isNotEmpty) return [cur];
    return [];
  }

  static Future<void> setServers(List<String> list) async =>
      (await sp).setString(_kServers, jsonEncode(list));

  static Future<String?> getToken() async => (await sp).getString(_kToken);
  static Future<void> setToken(String? v) async {
    final s = await sp;
    if (v == null) {
      await s.remove(_kToken);
    } else {
      await s.setString(_kToken, v);
    }
  }

  static Future<String?> getUserJson() async => (await sp).getString(_kUser);
  static Future<void> setUserJson(String? v) async {
    final s = await sp;
    if (v == null) {
      await s.remove(_kUser);
    } else {
      await s.setString(_kUser, v);
    }
  }

  static Future<int?> getBookId() async {
    final v = (await sp).getInt(_kBookId);
    return v;
  }

  static Future<void> setBookId(int? v) async {
    final s = await sp;
    if (v == null) {
      await s.remove(_kBookId);
    } else {
      await s.setInt(_kBookId, v);
    }
  }

  static Future<String?> getBooksJson() async => (await sp).getString(_kBooks);
  static Future<void> setBooksJson(String? v) async {
    final s = await sp;
    if (v == null) {
      await s.remove(_kBooks);
    } else {
      await s.setString(_kBooks, v);
    }
  }

  static Future<void> clearAuth() async {
    final s = await sp;
    await s.remove(_kToken);
    await s.remove(_kUser);
    await s.remove(_kBookId);
    await s.remove(_kBooks);
  }

  // 归属人（多账号记账）底色：owner name -> hex 颜色
  static const _kOwnerColors = 'owner_colors';
  static Future<Map<String, String>> getOwnerColors() async {
    final raw = (await sp).getString(_kOwnerColors);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map;
      return m.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> setOwnerColors(Map<String, String> m) async {
    await (await sp).setString(_kOwnerColors, jsonEncode(m));
  }
}
