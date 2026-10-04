import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/db.dart';
import 'package:jizhang_android/core/local_first_api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/screens/record/auto_record_service.dart';

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
  DateTime? _lastFailLogAt; // 失败日志节流（防离线时每次同步都刷一条）

  void bind(ApiClient api) {
    _api = api;
  }

  ApiClient get api => _api!;

  bool get isSyncing => _syncing;

  /// 当前账本的同步游标 key
  static String _cursorKey(int bookId) => 'last_sync_$bookId';
  /// 指纹 key（本地存上次同步指纹，判断服务器有无变化）
  static String _fpKey(int bookId) => 'bundle_fp_$bookId';

  /// 触发同步：优先增量；本地无该账本数据时自动全量。
  /// 返回是否成功完成（含"无需同步"）
  Future<bool> syncNow(int bookId) async {
    final a = _api;
    if (a == null || _syncing) return false;
    _syncing = true;
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      // 1) 补传本地待同步写操作
      await _flushOutbox(bookId, a);
      // 2) 指纹探测：无变化 → 跳过全部拉取（只同步有修改/新增的部分）
      final db = LocalDb.instance;
      final lastFp = await db.getMeta(_fpKey(bookId));
      final fpResp = await a.getFingerprint(lastFp: lastFp);
      final unchanged = fpResp['unchanged'] == true;
      if (!unchanged) {
        // 3) 小表 + 流水并行拉取（互不依赖，一次网络往返时间）。
        // _pullSmallTables 内部全部走 guard 吞错、永远不会抛 → 先 await 它
        // 不会出现「一个 Future 报错后另一个 Future 的错误无人监听」。
        final smallF = _pullSmallTables(bookId, a);
        final flowsF = _pullFlows(bookId, a);
        await smallF;
        final flowRows = await flowsF;
        // v2.2.27 修复：指纹必须等拉取【全部成功】之后再落盘！
        // 旧版先存指纹再拉取：拉取一旦中途失败（网络抖动、任一请求超时），
        // 指纹已被存成「最新」，之后每次同步服务器都返回 unchanged:true →
        // 拉取被整体跳过，家庭成员新增的流水永远拉不到，直到服务器数据
        // 再次变化才解锁（「队友记的账一直看不到、自己记一笔才出来」即此因）。
        await db.setMeta(_fpKey(bookId), (fpResp['fp'] ?? '') as String);
        AutoRecordService.instance.recordLog('[同步] 完成：流水变更 $flowRows 条');
      } else {
        AutoRecordService.instance.recordLog('[同步] 指纹一致，跳过拉取');
      }
      // 同步完成（无论 unchanged）：刷新 lastSyncAt → '我的'页能立即显示新时间
      lastSyncAt = DateTime.now();
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
      // v2.2.27：失败也写运行日志（5 分钟最多一条，防离线时每次同步都刷）。
      // 同步引擎此前零日志，「同步了但没数据」只能靠反推，无法定位。
      final now = DateTime.now();
      if (_lastFailLogAt == null ||
          now.difference(_lastFailLogAt!) > const Duration(minutes: 5)) {
        _lastFailLogAt = now;
        AutoRecordService.instance.recordLog(
            '[同步] 失败${isNet ? '（网络不可达）' : ''}：'
            '${s.length > 120 ? s.substring(0, 120) : s}');
      }
      notifyListeners();
      return false;
    } finally {
      _syncing = false;
    }
  }

  /// 记录刷新信号：页面可 watch 此字段触发重新读取本地
  int get tick => _syncTick;

  // ---------------- Outbox 补传（全实体分发器） ----------------
  Future<void> _flushOutbox(int bookId, ApiClient a) async {
    final rows = await LocalDb.instance.listOutbox();
    if (rows.isEmpty) return;
    var replayed = false;
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
        await _replay(a, op, entityId, uuid, body, bookId);
        await LocalDb.instance.removeOutbox(id);
        replayed = true;
      } catch (e) {
        if (_isNetErr(e)) {
          await LocalDb.instance.bumpRetries(id);
          rethrow; // 网络错误：中止补传，等待下次同步
        }
        // v2.2.28 服务器明确拒绝（400/404 等）＝重试永远不会成功：
        // 移除该条并记日志，防止毒丸卡死整个队列
        await LocalDb.instance.removeOutbox(id);
        final msg = e.toString();
        AutoRecordService.instance.recordLog('[同步] 补传失败(已跳过)：$op ${msg.length > 80 ? msg.substring(0, 80) : msg}');
      }
    }
    // 有补传成功 → 重拉小表保证镜像一致
    if (replayed) await _pullSmallTables(bookId, a);
  }

  /// v2.2.28 网络类错误判定（与 LocalFirstApi._isNetworkErr 同口径）：
  /// 网络错误 → 保留队列重试；其余（400/404 等）→ 永久失败，跳过防毒丸。
  bool _isNetErr(Object e) {
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('Connection') ||
        s.contains('timed out') ||
        s.contains('TimeoutException') ||
        s.contains('HandshakeException') ||
        s.contains('Failed host lookup') ||
        s.contains('网络');
  }

  Future<void> _replay(ApiClient a, String op, int? entityId, String? uuid,
      Map<String, dynamic> body, int bookId) async {
    switch (op) {
      // ---- 流水（op 名必须与 LocalFirstApi 入队一致：create/update/delete。
      // v2.2.28 前这里误写成 createFlow/updateFlow/deleteFlow，与入队名对不上
      // → 全部落入 default 被静默丢弃，弱网流水「记了又消失」的根因） ----
      case 'create':
        final newId = await a.createFlow({...body, 'uuid': uuid ?? ''});
        if (uuid != null && uuid.isNotEmpty) {
          // 用服务器真实 id 原地提升负 id 临时行（保留 created_at/本地编辑），
          // 不依赖后续拉取回填——万一拉取失败本地也不会丢这条流水
          await LocalDb.instance.promoteTmpFlow(uuid, newId);
        }
        break;
      case 'update':
        // 用 entityId（入队时带的），body 里从来没有 id 字段——
        // 旧代码从 body 里强取 id 是潜伏空指针毒丸；负/缺 id 时按 uuid 解析
        var rid = entityId ?? 0;
        if (rid <= 0) {
          final cu = (body['client_uuid'] as String?) ?? '';
          if (cu.isNotEmpty) {
            rid = await LocalDb.instance.flowIdByUuid(cu) ?? 0;
          }
        }
        if (rid > 0) {
          await a.updateFlow(rid, body);
          await LocalDb.instance.markDirty(rid, false);
        }
        break;
      case 'delete':
        var did = entityId ?? 0;
        if (did <= 0) {
          final cu = (body['client_uuid'] as String?) ?? '';
          if (cu.isNotEmpty) {
            did = await LocalDb.instance.flowIdByUuid(cu) ?? 0;
          }
        }
        if (did > 0) {
          await a.deleteFlow(did);
          await LocalDb.instance.deleteFlowById(did);
        }
        break;
      // ---- 预算（budgets 天然幂等） ----
      case 'setBudget':
        await a.setBudget(
            year: body['year'] as int,
            category: body['category'] as String?,
            amount: (body['amount'] as num).toDouble(),
            expression: body['expression'] as String?,
            categories: (body['categories'] as List?)?.cast<String>());
        break;
      case 'deleteBudget':
        await a.deleteBudget(
            year: body['year'] as int,
            category: (body['category'] as String?) ?? '');
        break;
      // ---- 储蓄 ----
      case 'setSavingsGoal':
        await a.setSavingsGoal(
            target: (body['target'] as num).toDouble(), note: body['note'] as String?);
        break;
      case 'addSavingsItem':
        await a.addSavingsItem(
            name: body['name'] as String,
            amount: (body['amount'] as num).toDouble(),
            sign: (body['sign'] as num).toInt(),
            asOf: body['as_of'] as String?,
            asOfEnd: body['as_of_end'] as String?,
            note: body['note'] as String?);
        break;
      case 'updateSavingsItem':
        await a.updateSavingsItem(
            id: body['id'] as int,
            name: body['name'] as String,
            amount: (body['amount'] as num).toDouble(),
            sign: (body['sign'] as num).toInt(),
            asOf: body['as_of'] as String?,
            asOfEnd: body['as_of_end'] as String?,
            note: body['note'] as String?);
        break;
      case 'deleteSavingsItem':
        await a.deleteSavingsItem(body['id'] as int);
        break;
      case 'reorderSavingsItems':
        await a.reorderSavingsItems(
            (body['ids'] as List).map((e) => (e as num).toInt()).toList());
        break;
      case 'bulkUpdateSavingsItems':
        await a.bulkUpdateSavingsItems(
            items: (body['items'] as List).cast<Map<String, dynamic>>(),
            ymd: body['ymd'] as String?,
            mode: body['mode'] as String?);
        break;
      case 'setSavingsItemAmount':
        await a.setSavingsItemAmount(body['id'] as int,
            amount: (body['amount'] as num).toDouble(),
            note: (body['note'] as String?) ?? '',
            ymd: (body['ymd'] as String?) ?? '');
        break;
      case 'updateSavingsItemHistory':
        await a.updateSavingsItemHistory(body['id'] as int, body['hid'] as int,
            amount: (body['amount'] as num).toDouble(),
            note: (body['note'] as String?) ?? '');
        break;
      case 'deleteSavingsItemHistory':
        await a.deleteSavingsItemHistory(body['id'] as int, body['hid'] as int);
        break;
      case 'deleteSavingsHistory':
        await a.deleteSavingsHistory(body['ymd'] as String);
        break;
      case 'updateSavingsHistory':
        await a.updateSavingsHistory(
            ymd: body['ymd'] as String,
            asset: (body['asset'] as num).toDouble(),
            liability: (body['liability'] as num).toDouble());
        break;
      // ---- 定期模板 ----
      case 'addRecurring':
        await a.addRecurring(body);
        if (uuid != null && uuid.isNotEmpty) {
          await LocalDb.instance.deleteRecurringByUuid(uuid);
        }
        break;
      case 'updateRecurring':
        await a.updateRecurring(body['id'] as int, body);
        break;
      case 'deleteRecurring':
        await a.deleteRecurring(body['id'] as int);
        await LocalDb.instance.deleteRecurringLocal(body['id'] as int);
        break;
      // ---- 钱包 ----
      case 'addWallet':
        await a.addWallet(
            name: body['name'] as String,
            icon: (body['icon'] as String?) ?? '👛',
            target: ((body['target'] as num?) ?? 0).toDouble(),
            linkCategory: (body['link_category'] as String?) ?? '',
            linkFrom: (body['link_from'] as String?) ?? '',
            note: (body['note'] as String?) ?? '');
        break;
      case 'updateWallet':
        await a.updateWallet(
            id: body['id'] as int,
            name: body['name'] as String,
            icon: (body['icon'] as String?) ?? '👛',
            target: ((body['target'] as num?) ?? 0).toDouble(),
            note: (body['note'] as String?) ?? '',
            linkCategory: (body['link_category'] as String?) ?? '',
            linkFrom: (body['link_from'] as String?) ?? '');
        break;
      case 'deleteWallet':
        await a.deleteWallet(body['id'] as int);
        break;
      case 'addWalletTxn':
        await a.addWalletTxn(body['id'] as int,
            amount: (body['amount'] as num).toDouble(),
            direction: body['direction'] as String,
            ymd: body['ymd'] as String,
            note: (body['note'] as String?) ?? '');
        break;
      case 'updateWalletTxn':
        await a.updateWalletTxn(body['id'] as int,
            amount: (body['amount'] as num).toDouble(),
            direction: body['direction'] as String,
            ymd: body['ymd'] as String,
            note: (body['note'] as String?) ?? '');
        break;
      case 'deleteWalletTxn':
        await a.deleteWalletTxn(body['id'] as int);
        break;
      default:
        break;
    }
  }

  // ---------------- 小表全量（各表并行拉取，一次网络往返时间） ----------------
  Future<void> _pullSmallTables(int bookId, ApiClient a) async {
    final db = LocalDb.instance;
    // 单个小表失败不影响其它（分类/账本失败比较关键，预算/钱包等可容忍）
    Future<void> guard(Future<void> f) => f.catchError((_) {});

    Future<void> pullCategories() async {
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
    }

    Future<void> pullBooks() async {
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
    }

    // 收藏名称 + 建议 + 已取消显示（方案 A：一次性镜像全量，含 suggest/hidden/last_time）
    Future<void> pullPresets() => LocalFirstApi(a).syncPresetsNow(bookId);

    Future<void> pullSavings() async {
      final sav = await a.getSavings();
      Map itemJson(SavingsItem it) => it.toMirrorJson();
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

    Future<void> pullBudgets() async {
      final bset = await a.getBudgetSettings();
      await db.replaceBudgets(
          bookId,
          bset
              .map((r) => {
                    'year': r['year'],
                    'category': r['category'] ?? '',
                    'amount': r['amount'] ?? 0,
                    'expression': r['expression'] ?? '',
                  })
              .toList());
    }

    Future<void> pullRecurring() async {
      final recs = await a.getRecurring();
      await db.replaceRecurring(
          bookId,
          recs
              .map((r) => {
                    'id': r.id,
                    'type': r.type,
                    'category': r.category,
                    'description': r.description,
                    'amount': r.amount,
                    'payment_method': r.paymentMethod,
                    'freq': r.freq,
                    'day_of_month': r.dayOfMonth,
                    'month_of_year': r.monthOfYear,
                    'note': r.note,
                    'next_run': r.nextRun,
                    'attribution_uid': r.attributionUid,
                    'attribution': r.attribution,
                  })
              .toList());
    }

    Future<void> pullWallets() async {
      final w = await a.getWallets();
      await db.saveWalletsJson(
          bookId,
          jsonEncode({
            'wallets': w.wallets
                .map((x) => {
                      'id': x.id,
                      'name': x.name,
                      'icon': x.icon,
                      'target': x.target,
                      'note': x.note,
                      'balance': x.balance,
                      'link_from': x.linkFrom,
                      'link_category': x.linkCategory,
                    })
                .toList(),
            'totalBalance': w.totalBalance,
            'totalTarget': w.totalTarget,
          }));
    }

    await Future.wait([
      guard(pullCategories()),
      guard(pullBooks()),
      guard(pullPresets()),
      guard(pullSavings()),
      guard(pullBudgets()),
      guard(pullRecurring()),
      guard(pullWallets()),
    ]);
  }

  // ---------------- 流水增量 / 全量 ----------------
  /// 拉取流水（增量/全量），返回写入本地镜像的变更行数（供运行日志展示）。
  Future<int> _pullFlows(int bookId, ApiClient a) async {
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
    // 对账删除：all_ids 之外的本地行删掉（outbox 中的行在服务器仍存在，不受影响）。
    // safeSinceSeconds=30：保护本地刚写入 30s 内的乐观行（首页新建/改日期后立即同步会被误删，
    // 导致「先消失再刷新才出现」；30s 保护窗口确保用户能在首页看到新建行，
    // 超过 30s 仍未出现在 server allIds 的仍按原逻辑删除——服务器真删了能跟上）。
    await db.deleteFlowsNotIn(bookId, allIds, safeSinceSeconds: 30);
    // 游标推进用服务器时间（避免手机时钟偏差）
    final serverTime = (d['server_time'] as String?) ??
        DateTime.now().toIso8601String();
    await db.setMeta(_cursorKey(bookId), serverTime);
    lastSyncAt = DateTime.tryParse(serverTime.replaceFirst(' ', 'T'));
    return rows.length;
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
