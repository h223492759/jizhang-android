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
    return openDatabase(path, version: 4, onCreate: (d, v) async {
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
      await _createV2Tables(d);
    }, onUpgrade: (d, oldV, newV) async {
      if (oldV < 2) await _createV2Tables(d);
      if (oldV < 3) await _createV3Tables(d);
      if (oldV < 4) await _createV4Alter(d);
    });
  }

  /// v4：分类预算加 sort 列（网页端 ↑↓ 调序后，安卓端按 sort 显示）
  Future<void> _createV4Alter(DatabaseExecutor d) async {
    try {
      await d.execute('ALTER TABLE budgets ADD COLUMN sort INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}
  }

  /// v3：常用名称镜像表（preset_suggest / hidden_names）。
  /// 从 v1.3.x 升级过来的库 version 已是 2，onCreate 不会重跑，必须在这里补建，
  /// 否则 getSuggest 查询报 no such table → 记账页"常用名加载失败"。
  Future<void> _createV3Tables(DatabaseExecutor d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS preset_suggest(
        book_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 0,
        category TEXT NOT NULL DEFAULT '',
        payment_method TEXT NOT NULL DEFAULT '',
        avg_amount REAL NOT NULL DEFAULT 0,
        last_time TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (book_id, type, name)
      )''');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_suggest_book ON preset_suggest(book_id, type)');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS hidden_names(
        book_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (book_id, type, name)
      )''');
  }

  // 补一列（如果表里没有）
  Future<void> _addColumnIfMissing(DatabaseExecutor d, String table, String col, String ddl) async {
    final cols = await d.rawQuery("PRAGMA table_info($table)");
    if (!cols.any((c) => c['name'] == col)) {
      await d.execute("ALTER TABLE $table ADD COLUMN $ddl");
    }
  }

  Future<void> _createV2Tables(DatabaseExecutor d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS budgets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        year INTEGER NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL DEFAULT 0,
        expression TEXT NOT NULL DEFAULT '',
        sort INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_budgets_book ON budgets(book_id, year)');
    // 补 sort 列（v1.4.40 之前老库没这列）
    final budgetCols = await d.rawQuery('PRAGMA table_info(budgets)');
    if (!budgetCols.any((c) => c['name'] == 'sort')) {
      await d.execute('ALTER TABLE budgets ADD COLUMN sort INTEGER NOT NULL DEFAULT 0');
    }
    await d.execute('''
      CREATE TABLE IF NOT EXISTS recurring(
        id INTEGER PRIMARY KEY,
        book_id INTEGER NOT NULL,
        type TEXT NOT NULL DEFAULT 'expense',
        category TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL DEFAULT 0,
        payment_method TEXT NOT NULL DEFAULT '',
        freq TEXT NOT NULL DEFAULT 'monthly',
        day_of_month INTEGER NOT NULL DEFAULT 1,
        month_of_year INTEGER NOT NULL DEFAULT 1,
        note TEXT NOT NULL DEFAULT '',
        next_run TEXT NOT NULL DEFAULT '',
        attribution_uid INTEGER,
        attribution TEXT NOT NULL DEFAULT '',
        client_uuid TEXT,
        dirty INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS wallet_json(
        book_id INTEGER PRIMARY KEY,
        json TEXT NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS ops_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        ts TEXT NOT NULL,
        op TEXT NOT NULL,
        entity TEXT NOT NULL DEFAULT '',
        entity_id INTEGER,
        uuid TEXT,
        summary TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'ok'
      )''');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_opslog_book ON ops_log(book_id, id DESC)');
    // 方案 A：常用名称镜像表（preset_suggest + hidden_names），记账/发现页直接读本地
    await d.execute('''
      CREATE TABLE IF NOT EXISTS preset_suggest(
        book_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 0,
        category TEXT NOT NULL DEFAULT '',
        payment_method TEXT NOT NULL DEFAULT '',
        avg_amount REAL NOT NULL DEFAULT 0,
        last_time TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (book_id, type, name)
      )''');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_suggest_book ON preset_suggest(book_id, type)');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS hidden_names(
        book_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (book_id, type, name)
      )''');
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

  /// 删除本地不在 allIds 里的流水（与服务器对账）。
  /// [safeSinceSeconds] 保护窗口秒数：本地 created_at 在该窗口内的行不被删除，
  /// 用于「首页新建/改日期」流水写入后 syncNow 对账时被误删导致「先消失再刷新才出现」。
  /// 默认 30s；超过保护窗口的本地行若不在 allIds 仍按原逻辑删除（服务器真删了能跟上）。
  Future<void> deleteFlowsNotIn(int bookId, List<int> allIds,
      {int safeSinceSeconds = 30}) async {
    final d = await db;
    // 计算保护截止时间（当前时间往前 safeSinceSeconds 秒），字符串便于 SQL 比较
    final useSafe = safeSinceSeconds > 0;
    String cutoff = '';
    if (useSafe) {
      cutoff = DateTime.now()
          .subtract(Duration(seconds: safeSinceSeconds))
          .toString()
          .substring(0, 19);
    }
    if (allIds.isEmpty) {
      if (useSafe) {
        await d.rawDelete(
            'DELETE FROM flows WHERE book_id=? AND (created_at IS NULL OR created_at < ?)',
            [bookId, cutoff]);
      } else {
        await d.delete('flows', where: 'book_id=?', whereArgs: [bookId]);
      }
      return;
    }
    final marks = List.filled(allIds.length, '?').join(',');
    if (useSafe) {
      await d.rawDelete(
          'DELETE FROM flows WHERE book_id=? AND id NOT IN ($marks) '
          'AND (created_at IS NULL OR created_at < ?)',
          [bookId, ...allIds, cutoff]);
    } else {
      await d.rawDelete(
          'DELETE FROM flows WHERE book_id=? AND id NOT IN ($marks)',
          [bookId, ...allIds]);
    }
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

  /// 整个账簿最早一笔流水的年份（用于预算页年份选择的下限）
  Future<int> minFlowYear(int bookId) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT MIN(flow_time) AS m FROM flows WHERE book_id=? AND flow_time IS NOT NULL',
        [bookId]);
    final m = rows.isNotEmpty ? rows.first['m'] as String? : null;
    if (m == null || m.length < 4) return DateTime.now().year;
    return int.tryParse(m.substring(0, 4)) ?? DateTime.now().year;
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
  // 按 (book_id, type) 替换——两个 type 分开存储，避免互相覆盖
  Future<void> replacePresets(
      int bookId, String type, List<Map<String, Object?>> rows) async {
    final d = await db;
    await d.delete('presets',
        where: 'book_id=? AND type=?', whereArgs: [bookId, type]);
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

  // ---------------- preset_suggest / hidden_names 镜像（方案 A） ----------------
  // 按 (book_id, type) 替换——修复 v1.4.0 bug：之前按 book_id 全删再插单 type，
  // 循环里 income 会覆盖 expense，导致记账页"支出一条都没有"
  Future<void> replaceSuggest(
      int bookId, String type, List<Map<String, Object?>> rows) async {
    final d = await db;
    await d.delete('preset_suggest',
        where: 'book_id=? AND type=?', whereArgs: [bookId, type]);
    final batch = d.batch();
    for (final r in rows) {
      batch.insert('preset_suggest', Map<String, Object?>.from(r)..['book_id'] = bookId);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> getSuggest(int bookId, String type) async {
    final d = await db;
    return d.query('preset_suggest',
        where: 'book_id=? AND type=?',
        whereArgs: [bookId, type]);
  }

  Future<void> replaceHidden(
      int bookId, String type, List<Map<String, Object?>> rows) async {
    final d = await db;
    await d.delete('hidden_names',
        where: 'book_id=? AND type=?', whereArgs: [bookId, type]);
    final batch = d.batch();
    for (final r in rows) {
      batch.insert('hidden_names', Map<String, Object?>.from(r)..['book_id'] = bookId);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> getHidden(int bookId, String type) async {
    final d = await db;
    return d.query('hidden_names',
        where: 'book_id=? AND type=?',
        whereArgs: [bookId, type]);
  }

  // ---------------- sync_meta ----------------
  Future<String?> getMeta(String key) async {
    final d = await db;
    final rows = await d.query('sync_meta', where: 'key=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : (rows.first['value'] as String?);
  }

  Future<void> setMeta(String key, String value) async {
    final d = await db;
    await d.insert('sync_meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
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

  // ---------------- budgets（预算设置镜像） ----------------
  Future<void> replaceBudgets(int bookId, List<Map<String, Object?>> rows) async {
    final d = await db;
    await d.delete('budgets', where: 'book_id=?', whereArgs: [bookId]);
    final batch = d.batch();
    for (final r in rows) {
      batch.insert('budgets', Map<String, Object?>.from(r)..['book_id'] = bookId);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> getBudgetSettings(int bookId) async {
    final d = await db;
    try {
      return d.query('budgets',
          where: 'book_id=?', whereArgs: [bookId], orderBy: 'year, sort, category');
    } catch (e) {
      // 老数据库没 sort 列，降级
      return d.query('budgets',
          where: 'book_id=?', whereArgs: [bookId], orderBy: 'year, category');
    }
  }

  Future<void> upsertBudgetLocal(int bookId, int year, String category,
      double amount, String expression) async {
    final d = await db;
    await d.insert('budgets', {
      'book_id': bookId,
      'year': year,
      'category': category,
      'amount': amount,
      'expression': expression,
      'dirty': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBudgetLocal(int bookId, int year, String category) async {
    final d = await db;
    await d.delete('budgets',
        where: 'book_id=? AND year=? AND category=?',
        whereArgs: [bookId, year, category]);
  }

  // ---------------- recurring（定期模板镜像） ----------------
  Future<void> replaceRecurring(int bookId, List<Map<String, Object?>> rows) async {
    final d = await db;
    await d.delete('recurring', where: 'book_id=?', whereArgs: [bookId]);
    final batch = d.batch();
    for (final r in rows) {
      batch.insert('recurring', Map<String, Object?>.from(r)..['book_id'] = bookId);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> getRecurringLocal(int bookId) async {
    final d = await db;
    return d.query('recurring', where: 'book_id=?', whereArgs: [bookId], orderBy: 'id');
  }

  Future<void> upsertRecurringLocal(Map<String, Object?> row) async {
    final d = await db;
    await d.insert('recurring', Map<String, Object?>.from(row),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteRecurringLocal(int id) async {
    final d = await db;
    await d.delete('recurring', where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteRecurringByUuid(String uuid) async {
    final d = await db;
    await d.delete('recurring', where: 'client_uuid=?', whereArgs: [uuid]);
  }

  // ---------------- wallets（整包 JSON 镜像） ----------------
  Future<void> saveWalletsJson(int bookId, String json) async {
    final d = await db;
    await d.insert('wallet_json', {'book_id': bookId, 'json': json},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getWalletsJson(int bookId) async {
    final d = await db;
    final rows = await d.query('wallet_json',
        where: 'book_id=?', whereArgs: [bookId], limit: 1);
    return rows.isEmpty ? null : (rows.first['json'] as String?);
  }

  // ---------------- ops_log（本地操作日志） ----------------
  Future<void> addOpLog(int bookId, {
    required String op,
    String entity = '',
    int? entityId,
    String? uuid,
    String summary = '',
    String status = 'ok',
  }) async {
    final d = await db;
    await d.insert('ops_log', {
      'book_id': bookId,
      'ts': DateTime.now().toIso8601String(),
      'op': op,
      'entity': entity,
      'entity_id': entityId,
      'uuid': uuid,
      'summary': summary,
      'status': status,
    });
  }

  Future<List<Map<String, Object?>>> listOpLogs(int bookId, {int limit = 100}) async {
    final d = await db;
    return d.query('ops_log',
        where: 'book_id=?', whereArgs: [bookId],
        orderBy: 'id DESC', limit: limit);
  }

  // outbox 待重试数量（日志页展示）
  Future<int> pendingOutboxCount() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) AS n FROM outbox');
    return (r.first['n'] as int?) ?? 0;
  }
}

