import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/db.dart';
import 'package:jizhang_android/core/models.dart';

enum SyncStatus {
  idle, // 空闲（未开始 / 上次成功）
  syncing, // 同步中（右上角小圈）
  offline, // 离线（网络不可达，静默）
  error, // 出错（可展示在设置页）
}

/// 同步引擎：本地镜像 <-> 服务器双向同步
/// - 增量拉取流水（/flows/sync?since=）+ all_ids 对账删除
/// - 小表（分类/账本/收藏/目标）每次全量替换
/// - Outbox 待同步队列按序补传（create 带 uuid 幂等）
class SyncEngine extends ChangeNotifier {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  ApiClient? _api;
  SyncStatus status = SyncStatus.idle;
  DateTime? lastSyncAt;
  String? lastError;
  bool _syncing = false;
  int _syncTick = 0; // 每次完成自增，供页面监听刷新

  void bind(ApiClient api) {
    _api = api;
  }

  ApiClient get api => _api!;

  bool get isSyncing => _syncing;

  /// 当前账本的同步游标 key
  static String _cursorKey(int bookId) => 'last_sync_$bookId';

  /// 触发同步：优先增量；本地无该账本数据时自动全量。
  /// 返回是否成功完成（含"无需同步"）
  Future<bool> syncNow(int bookId) async {
    final a = _api;
    if (a == null || _syncing) return false;
    _syncing = true;
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      await _flushOutbox(bookId, a);
      await _pullSmallTables(bookId, a);
      await _pullFlows(bookId, a);
      status = SyncStatus.idle;
      lastError = null;
      _syncTick++;
      notifyListeners();
      return true;
    } catch (e) {
      final s = e.toString();
      final isNet = s.contains('SocketException') ||
          s.contains('Connection') ||
          s.contains('网络') ||
          s.contains('timed out') ||
          s.contains('TimeoutException') ||
          s.contains('HandshakeException') ||
          s.contains('Failed host lookup');
      status = isNet ? SyncStatus.offline : SyncStatus.error;
      lastError = s;
      notifyListeners();
      return false;
    } finally {
      _syncing = false;
    }
  }

  /// 记录刷新信号：页面可 watch 此字段触发重新读取本地
  int get tick => _syncTick;

  // ---------------- Outbox 补传 ----------------
  Future<void> _flushOutbox(int bookId, ApiClient a) async {
    final rows = await LocalDb.instance.listOutbox();
    if (rows.isEmpty) return;
    for (final row in rows) {
      final id = (row['id'] as num).toInt();
      final op = row['op'] as String;
      final entityId = (row['entity_id'] as num?)?.toInt();
      final uuid = row['uuid'] as String?;
      final bodyRaw = row['body'] as String?;
      final body = bodyRaw == null
          ? <String, dynamic>{}
          : jsonDecode(bodyRaw) as Map<String, dynamic>;
      try {
        if (op == 'create') {
          // 幂等：uuid 必须带上；服务器返回 {id, dup?}
          final newId = await a.createFlow({...body, 'uuid': uuid ?? ''});
          // 本地临时行（client_uuid=uuid）删除，稍后增量拉取回填真实行
          if (uuid != null && uuid.isNotEmpty) {
            await LocalDb.instance.deleteFlowByUuid(uuid);
          }
          if (newId > 0) {
            await LocalDb.instance.upsertFlow(
                (await LocalDb.instance.flowById(newId)) ?? <String, Object?>{
                  'id': newId,
                  'book_id': bookId,
                });
          }
        } else if (op == 'update' && entityId != null) {
          await a.updateFlow(entityId, body);
          await LocalDb.instance.markDirty(entityId, false);
        } else if (op == 'delete' && entityId != null) {
          await a.deleteFlow(entityId);
          await LocalDb.instance.deleteFlowById(entityId);
        }
        await LocalDb.instance.removeOutbox(id);
      } catch (e) {
        await LocalDb.instance.bumpRetries(id);
        rethrow; // 网络或服务器错误：中止补传，等待下次同步
      }
    }
  }

  // ---------------- 小表全量 ----------------
  Future<void> _pullSmallTables(int bookId, ApiClient a) async {
    final db = LocalDb.instance;
    // 分类
    final cats = await a.getCategories();
    await db.replaceCategories(
        bookId,
        cats
            .map((c) => {
                  'id': c.id,
                  'book_id': bookId,
                  'name': c.name,
                  'type': c.type,
                  'icon': c.icon,
                  'color': c.color,
                  'sort': c.sort,
                })
            .toList());
    // 账本
    final books = await a.getBooks();
    await db.replaceBooks(books
        .map((b) => {
              'id': b.id,
              'name': b.name,
              'owner_id': b.ownerId,
              'role': b.role,
              'members': b.members,
              'flows': b.flows,
            })
        .toList());
    // 收藏名称（两种类型）
    for (final t in ['expense', 'income']) {
      final pd = await a.getPresets(type: t, limit: 1000);
      await db.replacePresets(
          bookId,
          pd.presets
              .map((p) => {
                    'name': p.name,
                    'type': t,
                    'category': p.category ?? '',
                    'payment_method': p.paymentMethod ?? '',
                    'amount': p.amount ?? 0,
                  })
              .toList());
    }
    // 目标/细则（整包 JSON）
    final sav = await a.getSavings();
    Map itemJson(SavingsItem it) => {
          'id': it.id,
          'name': it.name,
          'sign': it.sign,
          'amount': it.amount,
          'note': it.note,
          'as_of': it.asOf,
          'as_of_end': it.asOfEnd,
          'sort': it.sort,
        };

    Map monthJson(SavingsMonth m) => {
          'ymd': m.ymd,
          'asset': m.asset,
          'liability': m.liability,
          'net': m.net,
          'op_user': m.opUser,
        };

    final savJson = jsonEncode({
      'goal': sav.goal,
      'items': sav.items.map(itemJson).toList(),
      'expiredItems': sav.expiredItems.map(itemJson).toList(),
      'current': sav.current,
      'months': sav.months.map(monthJson).toList(),
    });
    await db.saveSavings(bookId, savJson);
  }

  // ---------------- 流水增量 / 全量 ----------------
  Future<void> _pullFlows(int bookId, ApiClient a) async {
    final db = LocalDb.instance;
    final since = await db.getMeta(_cursorKey(bookId));
    final d = await a.fetchFlowsSync(since: since);
    final allIds = (d['all_ids'] as List? ?? [])
        .map((e) => (e as num).toInt())
        .toList();
    final changed = d['changed'] as List? ?? [];

    // 跳过仍在待同步队列中的行（本地未同步修改，避免被服务器旧值覆盖）
    final rows = <Map<String, Object?>>[];
    for (final c in changed) {
      final m = (c as Map).cast<String, dynamic>();
      final id = (m['id'] as num).toInt();
      final uuid = m['client_uuid'] as String?;
      if (await db.flowPending(id: id, uuid: uuid)) continue;
      rows.add(_flowToRow(bookId, m));
    }
    if (rows.isNotEmpty) await db.upsertFlows(rows);
    // 对账删除：all_ids 之外的本地行删掉（outbox 中的行在服务器仍存在，不受影响）
    await db.deleteFlowsNotIn(bookId, allIds);
    // 游标推进用服务器时间（避免手机时钟偏差）
    final serverTime = (d['server_time'] as String?) ??
        DateTime.now().toIso8601String();
    await db.setMeta(_cursorKey(bookId), serverTime);
    lastSyncAt = DateTime.tryParse(serverTime.replaceFirst(' ', 'T'));
  }

  Map<String, Object?> _flowToRow(int bookId, Map<String, dynamic> j) => {
        'id': (j['id'] as num).toInt(),
        'book_id': bookId,
        'user_id': (j['user_id'] as num?)?.toInt() ?? 0,
        'type': j['type'] ?? 'expense',
        'amount': (j['amount'] as num?)?.toDouble() ?? 0,
        'category': j['category'] ?? '',
        'payment_method': j['payment_method'] ?? '',
        'description': j['description'] ?? '',
        'flow_time': j['flow_time'] ?? '',
        'created_at': j['created_at'],
        'updated_at': j['updated_at'],
        'source': j['source'] ?? '',
        'attribution': j['attribution'] ?? '',
        'attribution_uid': (j['attribution_uid'] as num?)?.toInt(),
        'attribution_color': j['attribution_color'],
        'client_uuid': j['client_uuid'],
        'dirty': 0,
      };

  // ---------------- 工具 ----------------
  /// 生成简单 UUID（离线幂等键）
  static String newUuid() {
    final r = Random.secure();
    final hex = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
