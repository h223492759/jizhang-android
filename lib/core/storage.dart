import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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

  // ---------------- 读取/写入容错（v2.2.25） ----------------
  // ⚠️ 任何 key 被历史版本写成了别的类型（例如本该是 int 的存成了 String），
  // SharedPreferences 的 getString/getInt 会抛 TypeError。以前这里是**裸调用**，
  // 异常会一路冒到 SessionNotifier._load() 的 try 里 → **整个启动恢复中断**
  // （后面读的全读不到，用户看到的就是「打开 App 变成登录页」）。
  // 现在统一吞掉异常并返回 null：单个 key 坏掉只影响它自己，不连累登录态。
  static Future<String?> _getString(String key) async {
    try {
      return (await sp).getString(key);
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _getInt(String key) async {
    try {
      return (await sp).getInt(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _setString(String key, String v) async {
    try {
      await (await sp).setString(key, v);
    } catch (_) {}
  }

  static Future<void> _setInt(String key, int v) async {
    try {
      await (await sp).setInt(key, v);
    } catch (_) {}
  }

  static Future<void> _remove(String key) async {
    try {
      await (await sp).remove(key);
    } catch (_) {}
  }

  static Future<String?> getServerUrl() async => _getString(_kServer);
  static Future<void> setServerUrl(String v) async => _setString(_kServer, v);

  static const _kServers = 'servers';
  static Future<List<String>> getServers() async {
    final raw = await _getString(_kServers);
    if (raw != null) {
      try {
        return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    final cur = await _getString(_kServer);
    if (cur != null && cur.isNotEmpty) return [cur];
    return [];
  }

  static Future<void> setServers(List<String> list) async =>
      _setString(_kServers, jsonEncode(list));

  static Future<String?> getToken() async => _getString(_kToken);
  static Future<void> setToken(String? v) async {
    if (v == null) {
      await _remove(_kToken);
    } else {
      await _setString(_kToken, v);
    }
  }

  static Future<String?> getUserJson() async => _getString(_kUser);
  static Future<void> setUserJson(String? v) async {
    if (v == null) {
      await _remove(_kUser);
    } else {
      await _setString(_kUser, v);
    }
  }

  static Future<int?> getBookId() async => _getInt(_kBookId);

  static Future<void> setBookId(int? v) async {
    if (v == null) {
      await _remove(_kBookId);
    } else {
      await _setInt(_kBookId, v);
    }
  }

  static Future<String?> getBooksJson() async => _getString(_kBooks);
  static Future<void> setBooksJson(String? v) async {
    if (v == null) {
      await _remove(_kBooks);
    } else {
      await _setString(_kBooks, v);
    }
  }

  static Future<void> clearAuth() async {
    await _remove(_kToken);
    await _remove(_kUser);
    await _remove(_kBookId);
    await _remove(_kBooks);
  }

  // ---------------- 登录态冗余镜像（v2.2.25） ----------------
  // 目的：SharedPreferences 万一写失败 / 被系统清掉，App 就成了「莫名登出」
  // （用户报的问题）。这里把登录态**再写一份**到 App 私有目录的文件，与 SP 双写：
  //   - 启动时若 SP 里没有 token 但镜像文件有 → 自动恢复并回写 SP，用户无感；
  //   - 只有**用户主动「退出登录」**或**切换到别的服务器**时才删除这份镜像
  //     （token 与服务器绑定，换服务器必须重新登录）。
  // 文件在 App 私有目录（同 native_logs.json 的位置），其他应用读不到。
  static const _kMirror = 'login_state.json';

  static Future<File?> _mirrorFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_kMirror');
    } catch (_) {
      return null;
    }
  }

  /// 写入/更新登录态镜像。token 为空时不动（避免把有效镜像覆盖成空）。
  static Future<void> writeMirror({
    String? serverUrl,
    String? token,
    String? userJson,
    int? bookId,
    String? booksJson,
  }) async {
    try {
      if (token == null || token.isEmpty) return;
      final f = await _mirrorFile();
      if (f == null) return;
      await f.writeAsString(jsonEncode({
        'server_url': serverUrl ?? '',
        'token': token,
        'user_json': userJson ?? '',
        'book_id': bookId,
        'books_json': booksJson ?? '',
      }));
    } catch (_) {}
  }

  /// 读镜像；没有或不完整（无 token）时返回 null。
  static Future<Map<String, dynamic>?> readMirror() async {
    try {
      final f = await _mirrorFile();
      if (f == null || !f.existsSync()) return null;
      final m = jsonDecode(await f.readAsString());
      if (m is Map && (m['token']?.toString().isNotEmpty ?? false)) {
        return m.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  static Future<void> deleteMirror() async {
    try {
      final f = await _mirrorFile();
      if (f != null && f.existsSync()) await f.delete();
    } catch (_) {}
  }

  // 归属人（多账号记账）底色：owner name -> hex 颜色
  static const _kOwnerColors = 'owner_colors';
  static Future<Map<String, String>> getOwnerColors() async {
    final raw = await _getString(_kOwnerColors);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map;
      return m.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> setOwnerColors(Map<String, String> m) async =>
      _setString(_kOwnerColors, jsonEncode(m));
}
