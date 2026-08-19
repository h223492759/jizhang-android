import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// 日期范围归一：'YYYY-MM-DD' 补全为完整时间（与后端 range 同口径）
String _normStart(String s) => s.length <= 10 ? '$s 00:00:00' : s;
String _normEnd(String s) => s.length <= 10 ? '$s 23:59:59' : s;

/// 本地镜像数据库（离线优先核心）：
/// - flows 结构化存储（查询/统计/分页）
/// - categories / books / presets 结构化小表
/// - savings 整包 JSON（目标+细则+历史快照，服务器一次性返回）
/// - outbox 待同步队列（离线写操作）
/// - sync_meta 同步元信息（last_sync_at 等）
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;
  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'jizhang_local.db');
    return openDatabase(path, version: 1, onCreate: (d, v) async {
      await d.execute('''
        CREATE TABLE flows(
          id INTEGER PRIMARY KEY,
          book_id INTEGER NOT NULL,
          user_id INTEGER NOT NULL DEFAULT 0,
          type TEXT NOT NULL,
          amount REAL NOT NULL,
          category TEXT NOT NULL DEFAULT '',
          payment_method TEXT NOT NULL DEFAULT '',
          description TEXT NOT NULL DEFAULT '',
          flow_time TEXT NOT NULL,
          created_at TEXT,
          updated_at TEXT,
          source TEXT NOT NULL DEFAULT '',
          attribution TEXT NOT NULL DEFAULT '',
          attribution_uid INTEGER,
          attribution_color TEXT,
          client_uuid TEXT,
          dirty INTEGER NOT NULL DEFAULT 0
        )''');
      await d.execute(
          'CREATE INDEX idx_flows_book_time ON flows(book_id, flow_time DESC)');
      await d.execute('''
        CREATE TABLE categories(
          id INTEGER PRIMARY KEY,
          book_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'expense',
          icon TEXT NOT NULL DEFAULT '',
          color TEXT NOT NULL DEFAULT '',
          sort INTEGER NOT NULL DEFAULT 0
        )''');
      await d.execute('''
        CREATE TABLE books(
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL DEFAULT '',
          owner_id INTEGER NOT NULL DEFAULT 0,
          role TEXT NOT NULL DEFAULT 'editor',
          members INTEGER NOT NULL DEFAULT 0,
          flows INTEGER NOT NULL DEFAULT 0
        )''');
      await d.execute('''
        CREATE TABLE presets(
          id INTEGER PRIMARY KEY,
          book_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'expense',
          category TEXT NOT NULL DEFAULT '',
          payment_method TEXT NOT NULL DEFAULT '',
          amount REAL NOT NULL DEFAULT 0,
          sort INTEGER NOT NULL DEFAULT 0
        )''');
      await d.execute(
          'CREATE INDEX idx_presets_book ON presets(book_id, type)');
      await d.execute('''
        CREATE TABLE savings(
          book_id INTEGER PRIMARY KEY,
          json TEXT NOT NULL
        )''');
      await d.execute('''
        CREATE TABLE outbox(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          op TEXT NOT NULL,
          entity TEXT NOT NULL,
          entity_id INTEGER,
          uuid TEXT,
          body TEXT,
          retries INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )''');
      await d.execute(
          'CREATE TABLE sync_meta(key TEXT PRIMARY KEY, value TEXT)');
    });
  }

  // ---------------- flows ----------------
  Future<void> upsertFlow(Map<String, Object?> row) async {
    final d = await db;
    await d.insert('flows', Map<String, Object?>.from(row),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertFlows(List<Map<String, Object?>> rows) async {
    final d = await db;
    final batch = d.batch();
    for (final r in rows) {
      batch.insert('flows', Map<String, Object?>.from(r),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearFlows(int bookId) async {
    final d = await db;
    await d.delete('flows', where: 'book_id=?', whereArgs: [bookId]);
  }

  /// 删除本地不在 allIds 里的流水（与服务器对账）
  Future<void> deleteFlowsNotIn(int bookId, List<int> allIds) async {
    final d = await db;
    if (allIds.isEmpty) {
      await d.delete('flows', where: 'book_id=?', whereArgs: [bookId]);
      return;
    }
    final marks = List.filled(allIds.length, '?').join(',');
    await d.rawDelete(
        'DELETE FROM flows WHERE book_id=? AND id NOT IN ($marks)',
        [bookId, ...allIds]);
  }

  Future<List<Map<String, Object?>>> queryFlows(
    int bookId, {
    String? type,
    String? category,
    String? start,
    String? end,
    int page = 1,
    int pageSize = 50,
  }) async {
    final d = await db;
    final w = <String>['book_id=?'];
    final args = <Object?>[bookId];
    if (type != null && type.isNotEmpty) {
      w.add('type=?');
      args.add(type);
    }
    if (category != null && category.isNotEmpty) {
      w.add('category=?');
      args.add(category);
    }
    if (start != null && start.isNotEmpty) {
      w.add('flow_time>=?');
      args.add(_normStart(start));
    }
    if (end != null && end.isNotEmpty) {
      w.add('flow_time<=?');
      args.add(_normEnd(end));
    }
    final off = (page - 1) * pageSize;
    return d.query('flows',
        where: w.join(' AND '),
        whereArgs: args,
        orderBy: 'flow_time DESC, id DESC',
        limit: pageSize,
        offset: off);
  }

  /// 筛选条件下的总条数与收支汇总（流水列表页用）
  Future<Map<String, Object?>> countAndSum(int bookId,
      {String? type, String? category, String? start, String? end}) async {
    final d = await db;
    final w = <String>['book_id=?'];
    final args = <Object?>[bookId];
    if (type != null && type.isNotEmpty) {
      w.add('type=?');
      args.add(type);
    }
    if (category != null && category.isNotEmpty) {
      w.add('category=?');
      args.add(category);
    }
    if (start != null && start.isNotEmpty) {
      w.add('flow_time>=?');
      args.add(_normStart(start));
    }
    if (end != null && end.isNotEmpty) {
      w.add('flow_time<=?');
      args.add(_normEnd(end));
    }
    final row = await d.rawQuery(
        'SELECT COUNT(*) AS total,'
        ' COALESCE(SUM(CASE WHEN type=\'expense\' THEN amount END),0) AS expense,'
        ' COALESCE(SUM(CASE WHEN type=\'income\' THEN amount END),0) AS income'
        ' FROM flows WHERE ${w.join(' AND ')}',
        args);
    return row.first;
  }

  Future<Map<String, Object?>?> flowById(int id) async {
    final d = await db;
    final rows = await d.query('flows', where: 'id=?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> deleteFlowById(int id) async {
    final d = await db;
    await d.delete('flows', where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteFlowByUuid(String uuid) async {
    final d = await db;
    await d.delete('flows',
        where: 'client_uuid=?', whereArgs: [uuid]);
  }

  Future<void> markDirty(int id, bool dirty) async {
    final d = await db;
    await d.update('flows', {'dirty': dirty ? 1 : 0},
        where: 'id=?', whereArgs: [id]);
  }

  /// 本地统计（与后端 /overview 同口径）
  Future<Map<String, Object?>> flowStats(int bookId,
      {String? start, String? end}) async {
    final d = await db;
    final w = <String>['book_id=?'];
    final args = <Object?>[bookId];
    if (start != null && start.isNotEmpty) {
      w.add('flow_time>=?');
      args.add(_normStart(start));
    }
    if (end != null && end.isNotEmpty) {
      w.add('flow_time<=?');
      args.add(_normEnd(end));
    }
    final row = await d.rawQuery(
        'SELECT COALESCE(SUM(CASE WHEN type=\'expense\' THEN amount END),0) AS expense,'
        ' COALESCE(SUM(CASE WHEN type=\'income\' THEN amount END),0) AS income,'
        ' COUNT(*) AS count FROM flows WHERE ${w.join(' AND ')}',
        args);
    return row.first;
  }

  Future<int> totalFlowCount(int bookId) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) AS n FROM flows WHERE book_id=?', [bookId]);
    return (r.first['n'] as int?) ?? 0;
  }

  Future<List<Map<String, Object?>>> allFlows(int bookId) async {
    final d = await db;
    return d.query('flows',
        where: 'book_id=?', whereArgs: [bookId],
        orderBy: 'flow_time DESC, id DESC');
  }

  // ---------------- categories ----------------
  Future<void> replaceCategories(int bookId, List<Map<String, Object?>> rows) async {
    final d = await db;
    await d.delete('categories', where: 'book_id=?', whereArgs: [bookId]);
    final batch = d.batch();
    for (final r in rows) {
      batch.insert('categories', Map<String, Object?>.from(r)..['book_id'] = bookId);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> getCategories(int bookId) async {
    final d = await db;
    return d.query('categories',
        where: 'book_id=?',
        whereArgs: [bookId],
        orderBy: 'sort, id');
  }

  // ---------------- books ----------------
  Future<void> replaceBooks(List<Map<String, Object?>> rows) async {
    final d = await db;
    await d.delete('books');
    final batch = d.batch();
    for (final r in rows) {
      batch.insert('books', Map<String, Object?>.from(r));
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> getBooks() async {
    final d = await db;
    return d.query('books', orderBy: 'id');
  }

  // ---------------- presets（收藏） ----------------
  Future<void> replacePresets(int bookId, List<Map<String, Object?>> rows) async {
    final d = await db;
    await d.delete('presets', where: 'book_id=?', whereArgs: [bookId]);
    final batch = d.batch();
    for (final r in rows) {
      batch.insert('presets', Map<String, Object?>.from(r)..['book_id'] = bookId);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> getPresets(int bookId, String type) async {
    final d = await db;
    return d.query('presets',
        where: 'book_id=? AND type=?',
        whereArgs: [bookId, type],
        orderBy: 'sort, id');
  }

  // ---------------- savings（整包 JSON） ----------------
  Future<void> saveSavings(int bookId, String json) async {
    final d = await db;
    await d.insert('savings', {'book_id': bookId, 'json': json},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSavingsJson(int bookId) async {
    final d = await db;
    final rows = await d.query('savings',
        where: 'book_id=?', whereArgs: [bookId], limit: 1);
    return rows.isEmpty ? null : (rows.first['json'] as String?);
  }

  // ---------------- outbox ----------------
  Future<int> enqueue(String op, String entity,
      {int? entityId, String? uuid, Map<String, dynamic>? body}) async {
    final d = await db;
    return d.insert('outbox', {
      'op': op,
      'entity': entity,
      'entity_id': entityId,
      'uuid': uuid,
      'body': body == null ? null : jsonEncode(body),
      'retries': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> listOutbox() async {
    final d = await db;
    return d.query('outbox', orderBy: 'id');
  }

  Future<void> removeOutbox(int id) async {
    final d = await db;
    await d.delete('outbox', where: 'id=?', whereArgs: [id]);
  }

  Future<void> bumpRetries(int id) async {
    final d = await db;
    await d.rawUpdate('UPDATE outbox SET retries=retries+1 WHERE id=?', [id]);
  }

  /// 判断某条流水（按 id 或 uuid）是否在待同步队列中（拉取时跳过覆盖）
  Future<bool> flowPending({int? id, String? uuid}) async {
    final d = await db;
    if (id != null) {
      final r = await d.rawQuery(
          'SELECT 1 FROM outbox WHERE entity=\'flow\' AND entity_id=? LIMIT 1',
          [id]);
      if (r.isNotEmpty) return true;
    }
    if (uuid != null && uuid.isNotEmpty) {
      final r = await d.rawQuery(
          'SELECT 1 FROM outbox WHERE entity=\'flow\' AND uuid=? LIMIT 1',
          [uuid]);
      if (r.isNotEmpty) return true;
    }
    return false;
  }

  // ---------------- sync_meta ----------------
  Future<String?> getMeta(String key) async {
    final d = await db;
    final rows = await d.query('sync_meta',
        where: 'key=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : (rows.first['value'] as String?);
  }

  Future<void> setMeta(String key, String value) async {
    final d = await db;
    await d.insert('sync_meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
