import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/db.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/sync_engine.dart';
import 'package:jizhang_android/core/storage.dart';
import 'package:jizhang_android/state/session.dart';

/// 离线优先数据访问层（页面唯一数据入口）：
/// - 读：先查本地镜像（断网秒开），后台由 SyncEngine 刷新
/// - 写：在线直连服务器；网络异常自动转为「本地生效 + 入待同步队列」，恢复后补传
/// - 非核心方法（预算/钱包/定期/账单/AI）保持透传在线
class LocalFirstApi {
  LocalFirstApi(this._api);
  final ApiClient _api;

  User? _user;

  /// 登录/切换账号时由外层注入当前用户（归属默认）
  set currentUser(User? u) => _user = u;

  /// 当前账本：直接读本地存储（切换账本后立即生效，首次同步自动全量）
  Future<int> _curBook() async => await Storage.getBookId() ?? 0;

  // ================= 读：本地优先 =================

  Future<FlowPage> getFlows({
    String? start,
    String? end,
    String? type,
    String? category,
    int page = 1,
    int pageSize = 50,
  }) async {
    final bookId = await _curBook();
    final db = LocalDb.instance;
    final cs = await db.countAndSum(bookId,
        type: type, category: category, start: start, end: end);
    final rows = await db.queryFlows(bookId,
        type: type,
        category: category,
        start: start,
        end: end,
        page: page,
        pageSize: pageSize);
    return FlowPage(
      total: (cs['total'] as int?) ?? 0,
      expense: ((cs['expense'] as num?) ?? 0).toDouble(),
      income: ((cs['income'] as num?) ?? 0).toDouble(),
      list: rows.map(_flowFromRow).toList(),
    );

  }

  // ---- 镜像刷新 helpers ----
  Future<void> _refreshRecurring() async {
    try {
      final bookId = await _curBook();
      final rows = await _api.getRecurring();
      await LocalDb.instance.replaceRecurring(
          bookId,
          rows
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
    } catch (_) {}
  }

  Future<void> _refreshBudgets() async {
    try {
      final bookId = await _curBook();
      final rows = await _api.getBudgetSettings();
      await LocalDb.instance.replaceBudgets(
          bookId,
          rows
              .map((r) => {
                    'year': r['year'],
                    'category': r['category'] ?? '',
                    'amount': r['amount'] ?? 0,
                    'expression': r['expression'] ?? '',
                    'sort': r['sort'] ?? 0,
                  })
              .toList());
    } catch (_) {}
  }

  /// 公共：刷新钱包镜像（从服务器拉最新 wallets 覆盖本地）
  Future<void> refreshWallets() => _refreshWallets();

  Future<void> _refreshWallets() async {
    try {
      final bookId = await _curBook();
final w = await _api.getWallets();
      await LocalDb.instance.saveWalletsJson(
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
                      'manualBalance': x.manualBalance,
                      'linked': x.linked,
                      'total_in': x.totalIn,
                      'total_out': x.totalOut,
                      'count': x.count,
                      'last_ymd': x.lastYmd,
                      'percent': x.percent,
                      'link_from': x.linkFrom,
                      'link_category': x.linkCategory,
                      'linkCategories': x.linkCategories,
                      'linkLinks': x.linkLinks.map((l) => {'cat': l.cat, 'from': l.from}).toList(),
                    })
                .toList(),
            'totalBalance': w.totalBalance,
            'totalTarget': w.totalTarget,
          }));
    } catch (_) {}
  }

  /// 把定期模板请求体转本地镜像行（离线新建乐观写入用）
  Map<String, Object?> _recurringFromBody(int bookId, int id,
      Map<String, dynamic> b, {String? uuid, bool dirty = false}) =>
      {
        'id': id,
        'book_id': bookId,
        'type': b['type'] ?? 'expense',
        'category': b['category'] ?? '',
        'description': b['description'] ?? '',
        'amount': (b['amount'] as num?)?.toDouble() ?? 0,
        'payment_method': b['payment_method'] ?? '',
        'freq': b['freq'] ?? 'monthly',
        'day_of_month': b['day_of_month'] ?? 1,
        'month_of_year': b['month_of_year'] ?? 1,
        'note': b['note'] ?? '',
        'next_run': b['next_run'] ?? '',
        'attribution_uid': b['attribution_uid'],
        'attribution': b['attribution'] ?? '',
        'client_uuid': uuid,
        'dirty': dirty ? 1 : 0,
      };


  Future<Overview> getOverview({String? start, String? end}) async {
    final bookId = await _curBook();
    final db = LocalDb.instance;
    final s = await db.flowStats(bookId, start: start, end: end);
    final totalCount = await db.totalFlowCount(bookId);
    final expense = ((s['expense'] as num?) ?? 0).toDouble();
    final income = ((s['income'] as num?) ?? 0).toDouble();
    return Overview(
      expense: expense,
      income: income,
      balance: income - expense,
      count: (s['count'] as int?) ?? 0,
      totalCount: totalCount,
    );
  }

  Future<List<Category>> getCategories() async {
    final bookId = await _curBook();
    final rows = await LocalDb.instance.getCategories(bookId);
    return rows
        .map((r) => Category(
              id: (r['id'] as num).toInt(),
              bookId: bookId,
              name: (r['name'] ?? '') as String,
              type: (r['type'] ?? 'expense') as String,
              icon: (r['icon'] ?? '') as String,
              color: (r['color'] ?? '#7c8cff') as String,
              sort: (r['sort'] ?? 0) as int,
            ))
        .toList();
  }

  Future<List<Book>> getBooks() async {
    final rows = await LocalDb.instance.getBooks();
    return rows
        .map((r) => Book(
              id: (r['id'] as num).toInt(),
              name: (r['name'] ?? '') as String,
              ownerId: (r['owner_id'] ?? 0) as int,
              role: (r['role'] ?? 'editor') as String,
              members: (r['members'] ?? 0) as int,
              flows: (r['flows'] ?? 0) as int,
            ))
        .toList();
  }

  /// 常用名称（方案 A：本地镜像表直读 + 后台同步）。
  /// 返回本地数据（立即，秒开）；若本地镜像过期（>5 分钟）或为空，则后台从服务器拉取刷新。
  Future<PresetsData> getPresets({required String type, int limit = 12}) async {
    final bookId = await _curBook();
    final db = LocalDb.instance;
    // 后台同步（不阻塞返回）：先给本地数据
    _maybeSyncPresets(bookId).catchError((_) {});

    final presetRows = await db.getPresets(bookId, type);
    final presets = presetRows
        .map((r) => PresetName(
              name: (r['name'] ?? '') as String,
              category: r['category'] as String?,
              paymentMethod: r['payment_method'] as String?,
              amount: (r['amount'] as num?)?.toDouble(),
            ))
        .toList();
    final presetNames = presets.map((p) => p.name).toSet();

    final hiddenRows = await db.getHidden(bookId, type);
    final hiddenNames =
        hiddenRows.map((r) => (r['name'] ?? '') as String).toSet();

    final suggestRows = await db.getSuggest(bookId, type);
    PresetName fromSuggest(Map<String, Object?> r) => PresetName(
          name: (r['name'] ?? '') as String,
          category: r['category'] as String?,
          paymentMethod: r['payment_method'] as String?,
          amount: (r['avg_amount'] as num?)?.toDouble(),
          count: ((r['count'] as num?) ?? 0).toInt(),
        );

    // frequent：count>=2（用户要求：频次大于等于2次才显示）且未收藏/未隐藏，按频次降序
    final freqRows = suggestRows
        .where((r) =>
            (((r['count'] as num?) ?? 0).toInt()) >= 2 &&
            !presetNames.contains(r['name']) &&
            !hiddenNames.contains(r['name']))
        .toList()
      ..sort((a, b) => ((b['count'] as num?) ?? 0)
          .compareTo((a['count'] as num?) ?? 0));
    final frequent = freqRows.map(fromSuggest).toList();

    // recent：last_time 非空，按最近时间倒序（物化字段，不再实时聚合 flows）
    final recentRows = suggestRows
        .where((r) =>
            ((r['last_time'] ?? '') as String).isNotEmpty &&
            !presetNames.contains(r['name']) &&
            !hiddenNames.contains(r['name']))
        .toList()
      ..sort((a, b) => ((b['last_time'] ?? '') as String)
          .compareTo((a['last_time'] ?? '') as String));
    final recent = recentRows.take(limit).map(fromSuggest).toList();

    return PresetsData(
        presets: presets, frequent: frequent, recent: recent);
  }

  /// 若本地镜像过期（>5 分钟）或为空 → 从服务器全量同步到本地表
  Future<void> _maybeSyncPresets(int bookId) async {
    final db = LocalDb.instance;
    if (bookId <= 0) return;
    final last = await db.getMeta('preset_sync_$bookId');
    if (last != null) {
      final t = DateTime.tryParse(last);
      if (t != null &&
          DateTime.now().difference(t) < const Duration(minutes: 5)) {
        return; // 5 分钟内同步过，直接用本地
      }
    }
    await syncPresetsNow(bookId);
  }

  /// 全量同步：拉服务器 /presets（两种类型），写入本地镜像表 + 时间戳
  Future<void> syncPresetsNow(int bookId) async {
    if (bookId <= 0) return;
    final db = LocalDb.instance;
    for (final type in ['expense', 'income']) {
      final resp = await _api.getPresetsRaw(type: type, limit: 500);
      final pRows = (resp['presets'] as List? ?? []).map<Map<String, Object?>>((e) {
        final m = e as Map<String, dynamic>;
        return {
          'id': m['id'],
          'name': m['name'] ?? '',
          'type': type,
          'category': m['category'] ?? '',
          'payment_method': m['payment_method'] ?? '',
          'amount': m['amount'] ?? 0,
          'sort': m['sort'] ?? 0,
        };
      }).toList();
      await db.replacePresets(bookId, type, pRows);

      // frequent + recent 合并成一张 preset_suggest 镜像（同名合并，count 取 frequent 的）
      final byName = <String, Map<String, Object?>>{};
      for (final f in (resp['frequent'] as List? ?? [])) {
        final m = f as Map<String, dynamic>;
        final n = (m['name'] ?? '') as String;
        byName[n] = {
          'type': type,
          'name': n,
          'count': m['count'] ?? 0,
          'category': m['category'] ?? '',
          'payment_method': m['payment_method'] ?? '',
          'avg_amount': m['avg_amount'] ?? 0,
          'last_time': m['last_time'] ?? '',
        };
      }
      for (final r in (resp['recent'] as List? ?? [])) {
        final m = r as Map<String, dynamic>;
        final n = (m['name'] ?? '') as String;
        final cur = byName[n];
        byName[n] = {
          'type': type,
          'name': n,
          'count': (cur?['count'] as num?) ?? 1,
          'category': m['category'] ?? (cur?['category'] ?? ''),
          'payment_method': m['payment_method'] ?? (cur?['payment_method'] ?? ''),
          'avg_amount': m['avg_amount'] ?? (cur?['avg_amount'] ?? 0),
          'last_time': m['last_time'] ?? '',
        };
      }
      await db.replaceSuggest(bookId, type, byName.values.toList());

      final hRows = (resp['hidden'] as List? ?? []).map<Map<String, Object?>>((e) {
        final m = e as Map<String, dynamic>;
        return {
          'type': type,
          'name': m['name'] ?? '',
          'category': m['category'] ?? '',
          'created_at': m['created_at'] ?? '',
        };
      }).toList();
      await db.replaceHidden(bookId, type, hRows);
    }
    await db.setMeta('preset_sync_$bookId', DateTime.now().toIso8601String());
  }

  Future<SavingsOverview> getSavings() async {
    final bookId = await _curBook();
    final j = await LocalDb.instance.getSavingsJson(bookId);
    if (j == null || j.isEmpty) {
      return SavingsOverview(
          goal: {}, items: [], expiredItems: [], current: {}, months: []);
    }
    return SavingsOverview.fromJson(jsonDecode(j));
  }

  // 日期范围归一：与 db.dart 同口径，避免漏月末当天
  String _normStart(String s) => s.length <= 10 ? '$s 00:00:00' : s;
  String _normEnd(String s) => s.length <= 10 ? '$s 23:59:59' : s;

  Flow _flowFromRow(Map<String, Object?> r) => Flow(
        id: (r['id'] as num).toInt(),
        type: (r['type'] ?? 'expense') as String,
        amount: ((r['amount'] as num?) ?? 0).toDouble(),
        category: (r['category'] ?? '') as String,
        paymentMethod: (r['payment_method'] ?? '') as String,
        description: (r['description'] ?? '') as String,
        flowTime: (r['flow_time'] ?? '') as String,
        attribution: (r['attribution'] ?? '') as String,
        attributionColor: r['attribution_color'] as String?,
      );

  // ================= 写：在线直写 / 离线入队 =================

  Future<int> createFlow(Map<String, dynamic> body) async {
    final bookId = await _curBook();
    final db = LocalDb.instance;
    final uuid = SyncEngine.newUuid();
    try {
      final id = await _api.createFlow({...body, 'uuid': uuid});
      await db.upsertFlow(_rowFromBody(bookId, id, body));
      _syncAfterWrite(); // 写成功 → 触发一次同步（常用名/小表刷新；指纹可跳过）
      return id;
    } catch (e) {
      if (_isNetworkErr(e)) {
        final tmpId = -DateTime.now().millisecondsSinceEpoch;
        await db.upsertFlow(
            _rowFromBody(bookId, tmpId, body, uuid: uuid, dirty: true));
        await db.enqueue('create', 'flow', uuid: uuid, body: body);
        return tmpId;
      }
      rethrow;
    }
  }

  /// 写操作成功后触发一次同步（事件驱动：用户离线极少，不需要 30s 轮询）。
  /// syncNow 内部有 _syncing 锁 + 指纹跳过，重复触发开销极低。
  void _syncAfterWrite() {
    try {
      _curBook().then((bookId) {
        if (bookId > 0) {
          SyncEngine.instance.syncNow(bookId).catchError((_) {});
        }
      });
    } catch (_) {}
  }

  Future<void> updateFlow(int id, Map<String, dynamic> body) async {
    final db = LocalDb.instance;
    final existing = await db.flowById(id);
    try {
      await _api.updateFlow(id, body);
      // 同步更新本地镜像（关键）：否则首页/流水列表读本地仍是旧值，
      // 必须切页重进才触发重新同步才会刷新
      if (existing != null) {
        final updated = <String, Object?>{...existing, ...body, 'id': id, 'dirty': 0};
        await db.upsertFlow(updated);
      }
      _syncAfterWrite();
    } catch (e) {
      if (_isNetworkErr(e) && existing != null) {
        await db.markDirty(id, true);
        await db.enqueue('update', 'flow', entityId: id, body: body);
        return;
      }
      rethrow;
    }
  }

  Future<void> deleteFlow(int id) async {
    final db = LocalDb.instance;
    try {
      await _api.deleteFlow(id);
      await db.deleteFlowById(id);
      _syncAfterWrite();
    } catch (e) {
      if (_isNetworkErr(e)) {
        await db.deleteFlowById(id);
        await db.enqueue('delete', 'flow', entityId: id);
        return;
      }
      rethrow;
    }
  }

  // ================= 通用离线写（在线直连 / 断网入队 + 操作日志） =================

  Future<void> _offlineWrite({
    required String op,
    required String entity,
    required Future<void> Function() online,
    Map<String, dynamic>? body,
    int? entityId,
    String? uuid,
    String summary = '',
    Future<void> Function()? refresh,
    Future<void> Function()? localApply,
  }) async {
    final bookId = await _curBook();
    try {
      await online();
      await LocalDb.instance.addOpLog(bookId,
          op: op, entity: entity, entityId: entityId, uuid: uuid,
          summary: summary, status: 'ok');
      if (refresh != null) await refresh();
    } catch (e) {
      if (_isNetworkErr(e)) {
        await LocalDb.instance.enqueue(op, entity,
            entityId: entityId, uuid: uuid, body: body);
        await LocalDb.instance.addOpLog(bookId,
            op: op, entity: entity, entityId: entityId, uuid: uuid,
            summary: summary, status: 'queued');
        if (localApply != null) await localApply();
        return;
      }
      await LocalDb.instance.addOpLog(bookId,
          op: op, entity: entity, entityId: entityId, uuid: uuid,
          summary: summary, status: 'failed');
      rethrow;
    }
  }

  // ---- 储蓄（目标）写操作：全部离线可改 ----
  Future<void> setSavingsGoal({required double target, String? note}) =>
      _offlineWrite(
          op: 'setSavingsGoal', entity: 'savings_goal',
          online: () => _api.setSavingsGoal(target: target, note: note),
          body: {'target': target, 'note': note},
          summary: '修改目标 ¥$target', refresh: _refreshSavings);

  Future<void> addSavingsItem({
    required String name,
    required double amount,
    required int sign,
    String? asOf,
    String? asOfEnd,
    String? note,
  }) {
    final uuid = SyncEngine.newUuid();
    return _offlineWrite(
        op: 'addSavingsItem', entity: 'savings_item', uuid: uuid,
        online: () => _api.addSavingsItem(
            name: name, amount: amount, sign: sign, asOf: asOf, asOfEnd: asOfEnd, note: note),
        body: {'name': name, 'amount': amount, 'sign': sign, 'as_of': asOf, 'as_of_end': asOfEnd, 'note': note, 'client_uuid': uuid},
        summary: '新增细则 $name ¥$amount', refresh: _refreshSavings);
  }

  Future<void> updateSavingsItem({
    required int id,
    required String name,
    required double amount,
    required int sign,
    String? asOf,
    String? asOfEnd,
    String? note,
  }) =>
      _offlineWrite(
          op: 'updateSavingsItem', entity: 'savings_item', entityId: id,
          online: () => _api.updateSavingsItem(
              id: id, name: name, amount: amount, sign: sign, asOf: asOf, asOfEnd: asOfEnd, note: note),
          body: {'id': id, 'name': name, 'amount': amount, 'sign': sign, 'as_of': asOf, 'as_of_end': asOfEnd, 'note': note},
          summary: '修改细则 $name', refresh: _refreshSavings);

  Future<void> deleteSavingsItem(int id) => _offlineWrite(
      op: 'deleteSavingsItem', entity: 'savings_item', entityId: id,
      online: () => _api.deleteSavingsItem(id),
      body: {'id': id}, summary: '删除细则 #$id', refresh: _refreshSavings);

  Future<void> reorderSavingsItems(List<int> ids) => _offlineWrite(
      op: 'reorderSavingsItems', entity: 'savings_item',
      online: () => _api.reorderSavingsItems(ids),
      body: {'ids': ids}, summary: '调整细则顺序', refresh: _refreshSavings);

  Future<void> bulkUpdateSavingsItems({
    required List<Map<String, dynamic>> items,
    String? ymd,
    String? mode,
  }) =>
      _offlineWrite(
          op: 'bulkUpdateSavingsItems', entity: 'savings_item',
          online: () => _api.bulkUpdateSavingsItems(items: items, ymd: ymd, mode: mode),
          body: {'items': items, 'ymd': ymd, 'mode': mode},
          summary: '更新资产和负债', refresh: _refreshSavings);

  Future<void> setSavingsItemAmount(int id,
          {required double amount, String note = '', String ymd = ''}) =>
      _offlineWrite(
          op: 'setSavingsItemAmount', entity: 'savings_item', entityId: id,
          online: () => _api.setSavingsItemAmount(id, amount: amount, note: note, ymd: ymd),
          body: {'id': id, 'amount': amount, 'note': note, 'ymd': ymd},
          summary: '新增记录 ¥$amount', refresh: _refreshSavings);

  Future<void> updateSavingsItemHistory(int id, int hid,
          {required double amount, String note = ''}) =>
      _offlineWrite(
          op: 'updateSavingsItemHistory', entity: 'savings_history', entityId: id,
          online: () => _api.updateSavingsItemHistory(id, hid, amount: amount, note: note),
          body: {'id': id, 'hid': hid, 'amount': amount, 'note': note},
          summary: '修改历史记录', refresh: _refreshSavings);

  Future<void> deleteSavingsItemHistory(int id, int hid) =>
      _offlineWrite(
          op: 'deleteSavingsItemHistory', entity: 'savings_history', entityId: id,
          online: () => _api.deleteSavingsItemHistory(id, hid),
          body: {'id': id, 'hid': hid}, summary: '删除历史记录', refresh: _refreshSavings);

  Future<void> deleteSavingsHistory(String ymd) =>
      _offlineWrite(
          op: 'deleteSavingsHistory', entity: 'savings_history',
          online: () => _api.deleteSavingsHistory(ymd),
          body: {'ymd': ymd}, summary: '删除 $ymd 历史', refresh: _refreshSavings);

  Future<void> updateSavingsHistory({
    required String ymd,
    required double asset,
    required double liability,
  }) =>
      _offlineWrite(
          op: 'updateSavingsHistory', entity: 'savings_history',
          online: () => _api.updateSavingsHistory(ymd: ymd, asset: asset, liability: liability),
          body: {'ymd': ymd, 'asset': asset, 'liability': liability},
          summary: '修改 $ymd 历史', refresh: _refreshSavings);

  Future<void> _refreshSavings() async {
    try {
      final bookId = await _curBook();
      final sav = await _api.getSavings();
      await LocalDb.instance.saveSavings(
          bookId,
          jsonEncode({
            'goal': sav.goal,
            'items': sav.items
                .map((it) => {
                      'id': it.id,
                      'name': it.name,
                      'sign': it.sign,
                      'amount': it.amount,
                      'note': it.note,
                      'as_of': it.asOf,
                      'as_of_end': it.asOfEnd,
                      'sort': it.sort,
                    })
                .toList(),
            'expiredItems': sav.expiredItems
                .map((it) => {
                      'id': it.id,
                      'name': it.name,
                      'sign': it.sign,
                      'amount': it.amount,
                      'note': it.note,
                      'as_of': it.asOf,
                      'as_of_end': it.asOfEnd,
                      'sort': it.sort,
                    })
                .toList(),
            'current': sav.current,
            'months': sav.months
                .map((m) => {
                      'ymd': m.ymd,
                      'asset': m.asset,
                      'liability': m.liability,
                      'net': m.net,
                      'op_user': m.opUser,
                    })
                .toList(),
          }));
    } catch (_) {
      // 刷新失败忽略（下次同步会补）
    }
  }

  // ================= 透传（在线） =================
  Future<int> generateRecurring() => _api.generateRecurring();
  Future<List<AttributionMember>> getAttributions() =>
      _api.getAttributions();

  // ---- 定期模板：读本地 / 写离线 ----
  Future<List<Recurring>> getRecurring() async {
    final bookId = await _curBook();
    final rows = await LocalDb.instance.getRecurringLocal(bookId);
    return rows
        .map((r) => Recurring.fromJson(
            r.map((k, v) => MapEntry(k.toString(), v))))
        .toList();
  }

  Future<int> addRecurring(Map<String, dynamic> body) async {
    final bookId = await _curBook();
    final uuid = SyncEngine.newUuid();
    final b2 = {...body, 'client_uuid': uuid};
    try {
      final id = await _api.addRecurring(b2);
      await LocalDb.instance.addOpLog(bookId,
          op: 'addRecurring', entity: 'recurring', entityId: id, uuid: uuid,
          summary: '新增定期模板', status: 'ok');
      await _refreshRecurring();
      return id;
    } catch (e) {
      if (_isNetworkErr(e)) {
        await LocalDb.instance.enqueue('addRecurring', 'recurring', uuid: uuid, body: b2);
        await LocalDb.instance.addOpLog(bookId,
            op: 'addRecurring', entity: 'recurring', uuid: uuid,
            summary: '新增定期模板', status: 'queued');
        await LocalDb.instance.upsertRecurringLocal(
            _recurringFromBody(bookId, -DateTime.now().millisecondsSinceEpoch, b2,
                uuid: uuid, dirty: true));
        return -DateTime.now().millisecondsSinceEpoch;
      }
      rethrow;
    }
  }

  Future<void> updateRecurring(int id, Map<String, dynamic> body) =>
      _offlineWrite(
          op: 'updateRecurring', entity: 'recurring', entityId: id,
          online: () => _api.updateRecurring(id, body),
          body: {'id': id, ...body}, summary: '修改定期模板',
          refresh: _refreshRecurring);

  Future<void> deleteRecurring(int id) =>
      _offlineWrite(
          op: 'deleteRecurring', entity: 'recurring', entityId: id,
          online: () => _api.deleteRecurring(id),
          body: {'id': id}, summary: '删除定期模板',
          localApply: () => LocalDb.instance.deleteRecurringLocal(id),
          refresh: _refreshRecurring);

  // ---- 预算：读本地（设置镜像 + 本地算进度）/ 写离线 ----
  Future<BudgetData> getBudgets({int? year}) async {
    final bookId = await _curBook();
    // 打开预算页先拉最新预算设置刷新本地镜像（网页端调序/修改后立即同步；失败用旧镜像）
    try {
      await _refreshBudgets();
    } catch (_) {}
    final y = year ?? DateTime.now().year;
    final settings = await LocalDb.instance.getBudgetSettings(bookId);
    final rows = settings.where((r) => (r['year'] as int) == y).toList();
    final totalRow = rows.where((r) => (r['category'] ?? '') == '').toList();
    final catRows = rows.where((r) => (r['category'] ?? '') != '').toList();
    final flows = await LocalDb.instance.allFlows(bookId);
    double yearSpent = 0;
    final catSpent = <String, double>{};
    for (final f in flows) {
      final t = (f['flow_time'] as String? ?? '');
      if (f['type'] != 'expense' || !t.startsWith('$y')) continue;
      final amt = ((f['amount'] as num?) ?? 0).toDouble();
      yearSpent += amt;
      final c = ((f['category'] as String?) ?? '');
      catSpent[c] = (catSpent[c] ?? 0) + amt;
    }
    final totalAmount = ((totalRow.isEmpty ? null : totalRow.first['amount']) as num?)?.toDouble() ?? 0;
    final cats = catRows.map((r) {
      final cat = ((r['category'] as String?) ?? '');
      // 多分类合并预算（category 存 JSON 数组字符串）：spent = 各分类支出之和
      List<String> names = [];
      if (cat.startsWith('[')) {
        try {
          final arr = jsonDecode(cat);
          if (arr is List) names = arr.map((e) => e.toString()).toList();
        } catch (_) {}
      }
      if (names.isEmpty) names = [cat];
      final amt = ((r['amount'] as num?) ?? 0).toDouble();
      final spent = names.fold<double>(0, (s, n) => s + (catSpent[n] ?? 0));
      return BudgetCat(
        category: cat,
        amount: amt,
        expression: ((r['expression'] as String?) ?? ''),
        spent: spent,
        remaining: amt - spent,
        percent: amt > 0 ? (spent / amt * 100).round() : 0,
      );
    }).toList();
    final sbc = <String, double>{};
    final allCats = await LocalDb.instance.getCategories(bookId);
    for (final c in allCats) {
      if (c['type'] == 'expense') {
        sbc[((c['name'] as String?) ?? '')] =
            catSpent[((c['name'] as String?) ?? '')] ?? 0;
      }
    }
    return BudgetData(
      year: y,
      totalAmount: totalAmount,
      totalSpent: yearSpent,
      totalRemaining: totalAmount - yearSpent,
      totalPercent: totalAmount > 0 ? (yearSpent / totalAmount * 100).round() : 0,
      categories: cats,
      spentByCategory: sbc,
    );
  }

  Future<void> setBudget({
    required int year,
    String? category,
    required double amount,
    String? expression,
    List<String>? categories,
  }) {
    final cat = category ?? '';
    return _offlineWrite(
        op: 'setBudget', entity: 'budget',
        online: () => _api.setBudget(
            year: year, category: category, amount: amount,
            expression: expression, categories: categories),
        body: {'year': year, 'category': category, 'amount': amount, 'expression': expression, 'categories': categories},
        summary: '设置预算 ¥$amount',
        localApply: () async {
          final b = await _curBook();
          await LocalDb.instance.upsertBudgetLocal(b, year, cat, amount, expression ?? '');
        },
        refresh: _refreshBudgets);
  }

  Future<void> deleteBudget({required int year, String category = ''}) =>
      _offlineWrite(
          op: 'deleteBudget', entity: 'budget',
          online: () => _api.deleteBudget(year: year, category: category),
          body: {'year': year, 'category': category},
          summary: '删除预算',
          localApply: () async {
            final b = await _curBook();
            await LocalDb.instance.deleteBudgetLocal(b, year, category);
          },
          refresh: _refreshBudgets);

  // ---- 钱包：读本地整包 / 写离线 ----
  Future<WalletsData> getWallets() async {
    final bookId = await _curBook();
    final j = await LocalDb.instance.getWalletsJson(bookId);
    if (j == null || j.isEmpty) {
      return WalletsData(wallets: [], totalBalance: 0, totalTarget: 0);
    }
    return WalletsData.fromJson(jsonDecode(j));
  }

  Future<int> addWallet({
    required String name,
    String icon = '👛',
    double target = 0,
    String linkCategory = '',
    String linkFrom = '',
    String note = '',
    List<Map<String, String>>? linkLinks,
    List<Map<String, dynamic>>? depositRules,
  }) async {
    final bookId = await _curBook();
    final uuid = SyncEngine.newUuid();
    try {
      final id = await _api.addWallet(
          name: name, icon: icon, target: target,
          linkCategory: linkCategory, linkFrom: linkFrom, note: note,
          linkLinks: linkLinks, depositRules: depositRules);
      await LocalDb.instance.addOpLog(bookId,
          op: 'addWallet', entity: 'wallet', entityId: id, uuid: uuid,
          summary: '新增钱包 $name', status: 'ok');
      await _refreshWallets();
      return id;
    } catch (e) {
      if (_isNetworkErr(e)) {
        await LocalDb.instance.enqueue('addWallet', 'wallet', uuid: uuid, body: {
          'name': name, 'icon': icon, 'target': target,
          'link_category': linkCategory, 'link_from': linkFrom, 'note': note,
          if (linkLinks != null) 'link_links': linkLinks,
          if (depositRules != null) 'deposit_rules': depositRules,
          'client_uuid': uuid,
        });
        await LocalDb.instance.addOpLog(bookId,
            op: 'addWallet', entity: 'wallet', uuid: uuid,
            summary: '新增钱包 $name', status: 'queued');
        return -DateTime.now().millisecondsSinceEpoch;
      }
      rethrow;
    }
  }

  Future<void> updateWallet({
    required int id,
    required String name,
    String icon = '👛',
    double target = 0,
    String note = '',
    String linkCategory = '',
    String linkFrom = '',
    List<Map<String, String>>? linkLinks,
    List<Map<String, dynamic>>? depositRules,
  }) =>
      _offlineWrite(
          op: 'updateWallet', entity: 'wallet', entityId: id,
          online: () => _api.updateWallet(
              id: id, name: name, icon: icon, target: target, note: note,
              linkCategory: linkCategory, linkFrom: linkFrom, linkLinks: linkLinks,
              depositRules: depositRules),
          body: {
            'id': id, 'name': name, 'icon': icon, 'target': target, 'note': note,
            'link_category': linkCategory, 'link_from': linkFrom,
            if (linkLinks != null) 'link_links': linkLinks,
          },
          summary: '修改钱包 $name', refresh: _refreshWallets);

  Future<void> deleteWallet(int id) =>
      _offlineWrite(
          op: 'deleteWallet', entity: 'wallet', entityId: id,
          online: () => _api.deleteWallet(id),
          body: {'id': id}, summary: '删除钱包', refresh: _refreshWallets);

  Future<void> addWalletTxn(int id,
          {required double amount,
          required String direction,
          required String ymd,
          String note = ''}) =>
      _offlineWrite(
          op: 'addWalletTxn', entity: 'wallet_txn', entityId: id,
          online: () => _api.addWalletTxn(id,
              amount: amount, direction: direction, ymd: ymd, note: note),
          body: {'id': id, 'amount': amount, 'direction': direction, 'ymd': ymd, 'note': note},
          summary: '钱包记账 $direction ¥$amount', refresh: _refreshWallets);

  Future<void> updateWalletTxn(int id,
          {required double amount,
          required String direction,
          required String ymd,
          String note = ''}) =>
      _offlineWrite(
          op: 'updateWalletTxn', entity: 'wallet_txn', entityId: id,
          online: () => _api.updateWalletTxn(id,
              amount: amount, direction: direction, ymd: ymd, note: note),
          body: {'id': id, 'amount': amount, 'direction': direction, 'ymd': ymd, 'note': note},
          summary: '修改钱包记录', refresh: _refreshWallets);

  Future<void> deleteWalletTxn(int id) =>
      _offlineWrite(
          op: 'deleteWalletTxn', entity: 'wallet_txn', entityId: id,
          online: () => _api.deleteWalletTxn(id),
          body: {'id': id}, summary: '删除钱包记录', refresh: _refreshWallets);

  Future<Map<String, dynamic>> getSavingsItemHistory(int id) =>
      _api.getSavingsItemHistory(id);
  Future<Map<String, dynamic>> getWalletTxns(int id) =>
      _api.getWalletTxns(id);

  // ================ 派生统计（账单/图表）本地聚合（离线可用） ================
  // 照搬后端 bills/stats SQL 同口径：直接读本地 flows 在 Dart 内聚合
  Future<List<Map<String, Object?>>> _flowsInRange(int bookId,
      {String? start, String? end, String? type}) async {
    final flows = await LocalDb.instance.allFlows(bookId);
    final s = start == null || start.isEmpty ? null : _normStart(start);
    final e = end == null || end.isEmpty ? null : _normEnd(end);
    final t = type;
    return flows.where((f) {
      if (t != null && (f['type'] ?? '') != t) return false;
      final ft = (f['flow_time'] as String? ?? '');
      if (s != null && ft.compareTo(s) < 0) return false;
      if (e != null && ft.compareTo(e) > 0) return false;
      return true;
    }).toList();
  }

  Future<List<CatStat>> getCategoryStat(
      {String? start, String? end, String? type}) async {
    final bookId = await _curBook();
    final rows = await _flowsInRange(bookId, start: start, end: end, type: type);
    final sum = <String, double>{};
    final cnt = <String, int>{};
    for (final f in rows) {
      final c = ((f['category'] as String?) ?? '未标注');
      sum[c] = (sum[c] ?? 0) + ((f['amount'] as num?) ?? 0).toDouble();
      cnt[c] = (cnt[c] ?? 0) + 1;
    }
    final list = sum.entries
        .map((e) => CatStat(name: e.key, value: e.value, count: cnt[e.key] ?? 0))
        .toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  Future<List<DailyStat>> getDaily({String? start, String? end}) async {
    final bookId = await _curBook();
    final rows = await _flowsInRange(bookId, start: start, end: end);
    final byDate = <String, List<Map<String, Object?>>>{};
    for (final f in rows) {
      final d = ((f['flow_time'] as String?) ?? '').substring(0, 10);
      if (d.isEmpty) continue;
      byDate.putIfAbsent(d, () => []).add(f);
    }
    final list = byDate.entries.map((e) {
      double inc = 0, exp = 0;
      final groups = <String, List<Map<String, Object?>>>{};
      for (final f in e.value) {
        final t = (f['type'] ?? '') as String;
        final amt = ((f['amount'] as num?) ?? 0).toDouble();
        if (t == 'income') inc += amt; else exp += amt;
        groups.putIfAbsent(t, () => []).add(f);
      }
      final top = <String, List<DailyTopItem>>{};
      groups.forEach((t, g) {
        g.sort((a, b) => ((b['amount'] as num?) ?? 0).compareTo((a['amount'] as num?) ?? 0));
        top[t] = g.take(3).map((f) => DailyTopItem(
              amount: ((f['amount'] as num?) ?? 0).toDouble(),
              category: f['category'] as String?,
              description: f['description'] as String?,
            )).toList();
      });
      return DailyStat(date: e.key, expense: exp, income: inc, top: top);
    }).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Future<List<MonthlyStat>> getMonthly({int? year, String? category}) async {
    final bookId = await _curBook();
    final y = year ?? DateTime.now().year;
    final all = await LocalDb.instance.allFlows(bookId);
    final list = <MonthlyStat>[];
    for (var m = 1; m <= 12; m++) {
      final key = '$y-${m.toString().padLeft(2, '0')}';
      double inc = 0, exp = 0;
      for (final f in all) {
        final ft = (f['flow_time'] as String? ?? '');
        if (!ft.startsWith(key)) continue;
        if (category != null && category.isNotEmpty &&
            ((f['category'] as String?) ?? '') != category) continue;
        final t = (f['type'] ?? '') as String;
        final amt = ((f['amount'] as num?) ?? 0).toDouble();
        if (t == 'income') inc += amt; else exp += amt;
      }
      list.add(MonthlyStat(month: key, expense: exp, income: inc));
    }
    return list;
  }

  Future<BillMonthly> getBillMonthly({int? year}) async {
    final bookId = await _curBook();
    final y = year ?? DateTime.now().year;
    final all = await LocalDb.instance.allFlows(bookId);
    final byMonth = <String, List<Map<String, Object?>>>{};
    for (final f in all) {
      final ft = (f['flow_time'] as String? ?? '');
      if (!ft.startsWith('$y')) continue;
      final k = ft.substring(0, 7);
      byMonth.putIfAbsent(k, () => []).add(f);
    }
    final rows = <BillRow>[];
    double ti = 0, te = 0;
    int tc = 0;
    for (var m = 1; m <= 12; m++) {
      final k = '$y-${m.toString().padLeft(2, '0')}';
      final list = byMonth[k] ?? [];
      double inc = 0, exp = 0;
      int cnt = 0;
      for (final f in list) {
        final t = (f['type'] ?? '') as String;
        final amt = ((f['amount'] as num?) ?? 0).toDouble();
        if (t == 'income') inc += amt; else exp += amt;
        cnt++;
      }
      rows.add(BillRow(
          month: k, label: '$m月',
          income: inc, expense: exp, balance: inc - exp,
          count: cnt, year: y));
      ti += inc; te += exp; tc += cnt;
    }
    // years：本地全部流水涉及的年份（倒序）
    final years = <int>{};
    for (final f in all) {
      final ft = (f['flow_time'] as String? ?? '');
      if (ft.length >= 4) years.add(int.tryParse(ft.substring(0, 4)) ?? 0);
    }
    final ys = years.where((x) => x > 0).toList()..sort((a, b) => b.compareTo(a));
    return BillMonthly(
      year: y,
      years: ys,
      summary: BillRow(
          month: '$y', label: '$y年',
          income: ti, expense: te, balance: ti - te,
          count: tc, year: y),
      rows: rows,
    );
  }

  Future<BillYearly> getBillYearly() async {
    final bookId = await _curBook();
    final all = await LocalDb.instance.allFlows(bookId);
    final byYear = <int, List<Map<String, Object?>>>{};
    for (final f in all) {
      final ft = (f['flow_time'] as String? ?? '');
      if (ft.length < 4) continue;
      final y = int.tryParse(ft.substring(0, 4));
      if (y == null) continue;
      byYear.putIfAbsent(y, () => []).add(f);
    }
    final list = byYear.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    final rows = <BillRow>[];
    double ti = 0, te = 0;
    int tc = 0;
    for (final e in list) {
      double inc = 0, exp = 0;
      int cnt = 0;
      for (final f in e.value) {
        final t = (f['type'] ?? '') as String;
        final amt = ((f['amount'] as num?) ?? 0).toDouble();
        if (t == 'income') inc += amt; else exp += amt;
        cnt++;
      }
      rows.add(BillRow(
          month: '${e.key}', label: '${e.key}年',
          income: inc, expense: exp, balance: inc - exp,
          count: cnt, year: e.key));
      ti += inc; te += exp; tc += cnt;
    }
    return BillYearly(
      summary: BillRow(
          month: 'all', label: '全部',
          income: ti, expense: te, balance: ti - te,
          count: tc, year: 0),
      rows: rows,
    );
  }

  // 整个账簿最早一笔流水的日期（YYYY-MM-DD）；用于「从 X 起已记账 N 天」
  // 与后端 bills.js 的 SELECT MIN(flow_time) 同口径（账簿整体，而非当前月/年）。
  // 注意：db.allFlows 默认按 flow_time DESC 排序，all.first 取到的是最新一笔，
  // 因此必须显式求最小值，不能再用 all.first。
  String _wholeBookFirstFlow(List<Map<String, Object?>> all) {
    String? min;
    for (final f in all) {
      final ft = (f['flow_time'] as String? ?? '');
      if (ft.isEmpty) continue;
      if (min == null || ft.compareTo(min) < 0) min = ft;
    }
    if (min == null || min.length < 10) return '';
    return min.substring(0, 10);
  }

  Future<Map<String, dynamic>> getBillMonthDetail(String ym) async {
    // 照搬后端 bills /month-detail 输出（与网页端同口径），离线版
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(ym);
    if (m == null) return {'year': 0, 'month': 0, 'ym': ym};
    final yy = int.parse(m.group(1)!);
    final mm = int.parse(m.group(2)!);
    final bookId = await _curBook();
    final all = await LocalDb.instance.allFlows(bookId);
    final now = DateTime.now();
    final isCurrent = yy == now.year && mm == now.month;
    final monthLastDay = DateTime(yy, mm + 1, 0).day;
    final elapsed = isCurrent ? (now.day.clamp(1, monthLastDay)) : monthLastDay;

    // 首笔流水（整个账簿最早日）
    final firstFlow = _wholeBookFirstFlow(all);
    final firstDate = firstFlow.isNotEmpty ? DateTime.tryParse(firstFlow) : null;
    int startDayCount = 0;
    if (firstDate != null) {
      final ref = isCurrent ? now : DateTime(yy, mm, monthLastDay);
      if (!ref.isBefore(firstDate)) startDayCount = ref.difference(firstDate).inDays + 1;
    }

    // 本月 / 上一月 / 整体聚合
    final thisRows = <Map<String, Object?>>[];
    final prevRows = <Map<String, Object?>>[];
    for (final f in all) {
      final ft = (f['flow_time'] as String? ?? '');
      if (!ft.startsWith(ym)) {
        final py = yy * 12 + mm - 1;
        final fy = int.tryParse(ft.substring(0, 4)) ?? 0;
        final fm = int.tryParse(ft.substring(5, 7)) ?? 0;
        if (fy * 12 + fm == py) prevRows.add(f);
        continue;
      }
      thisRows.add(f);
    }
    double monthIncome = 0, monthExpense = 0;
    final cat = <String, double>{};
    final dayExpense = <String, double>{};
    for (final f in thisRows) {
      final t = (f['type'] ?? '') as String;
      final amt = ((f['amount'] as num?) ?? 0).toDouble();
      final c = ((f['category'] as String?) ?? '未标注');
      if (t == 'income') monthIncome += amt;
      else { monthExpense += amt; cat[c] = (cat[c] ?? 0) + amt; }
      final d = (f['flow_time'] as String).substring(0, 10);
      dayExpense[d] = (dayExpense[d] ?? 0) + (t == 'expense' ? amt : 0);
    }
    double lastMonthBalance = 0;
    for (final f in prevRows) {
      final t = (f['type'] ?? '') as String;
      final amt = ((f['amount'] as num?) ?? 0).toDouble();
      lastMonthBalance += (t == 'income' ? amt : -amt);
    }

    // 支出分类（含 percent）+ 收入/支出 top3
    final expenseByCategory = cat.entries
        .map((e) => {
              'category': e.key,
              'amount': e.value,
              'percent': monthExpense > 0 ? (e.value / monthExpense * 1000).round() / 10 : 0,
            })
        .toList()
      ..sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    Map<String, Object?> _flowRowToMap(Map<String, Object?> f) => {
          'id': f['id'],
          'flow_time': f['flow_time'],
          'amount': f['amount'],
          'category': f['category'],
          'description': f['description'],
          'payment_method': f['payment_method'],
        };
    final expenseList = thisRows.where((f) => (f['type'] ?? '') == 'expense').toList()
      ..sort((a, b) => ((b['amount'] as num?) ?? 0).compareTo((a['amount'] as num?) ?? 0));
    final topExpenses = expenseList.take(3).map(_flowRowToMap).toList();
    final incomeList = thisRows.where((f) => (f['type'] ?? '') == 'income').toList()
      ..sort((a, b) => ((b['amount'] as num?) ?? 0).compareTo((a['amount'] as num?) ?? 0));
    final topIncomes = incomeList.take(3).map(_flowRowToMap).toList();

    // 单日最高支出 + 日均
    final sortedDays = dayExpense.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final highestDay = sortedDays.isNotEmpty
        ? {'date': sortedDays.first.key, 'amount': sortedDays.first.value}
        : {'date': '', 'amount': 0};
    final dailyAvgExpense = elapsed > 0 ? monthExpense / elapsed : 0;

    // 对比窗口（前后各 2 月）
    final allMonths = <String>{};
    for (final f in all) {
      final ft = (f['flow_time'] as String? ?? '');
      if (ft.length >= 7) allMonths.add(ft.substring(0, 7));
    }
    final sortedMonths = allMonths.toList()..sort();
    final idx = sortedMonths.indexOf(ym);
    Map<String, double> _monthAgg(String m) {
      double i = 0, e = 0;
      for (final f in all) {
        final ft = (f['flow_time'] as String? ?? '');
        if (!ft.startsWith(m)) continue;
        final t = (f['type'] ?? '') as String;
        final a = ((f['amount'] as num?) ?? 0).toDouble();
        if (t == 'income') i += a; else e += a;
      }
      return {'income': i, 'expense': e};
    }

    List<Map<String, Object?>> compare;
    if (idx < 0) {
      compare = [];
    } else {
      int lo = idx - 2, hi = idx + 2;
      if (hi > sortedMonths.length - 1) {
        hi = sortedMonths.length - 1;
        lo = (hi - 4).clamp(0, hi);
      }
      lo = lo.clamp(0, hi);
      compare = sortedMonths.sublist(lo, hi + 1).map((m) {
        final a = _monthAgg(m);
        return {
          'ym': m,
          'label': m.substring(5, 7),
          'income': a['income'] ?? 0,
          'expense': a['expense'] ?? 0,
        };
      }).toList();
    }

    // 对比上月分类变化 top3
    Map<String, double> _catSums(String m, String type) {
      final r = <String, double>{};
      for (final f in all) {
        final ft = (f['flow_time'] as String? ?? '');
        if (!ft.startsWith(m)) continue;
        if ((f['type'] ?? '') != type) continue;
        final c = ((f['category'] as String?) ?? '未标注');
        r[c] = (r[c] ?? 0) + ((f['amount'] as num?) ?? 0).toDouble();
      }
      return r;
    }

    List<Map<String, Object?>> diffTop(String type) {
      if (idx < 1) return [];
      final prev = _catSums(sortedMonths[idx - 1], type);
      final cur = _catSums(ym, type);
      final names = <String>{...prev.keys, ...cur.keys};
      final list = <Map<String, Object?>>[];
      for (final c in names) {
        final p = prev[c] ?? 0;
        final k = cur[c] ?? 0;
        final delta = (k - p).round() / 100;
        if (delta.abs() < 0.005) continue;
        list.add({
          'category': c,
          'prev': p,
          'cur': k,
          'delta': delta,
          'dir': delta > 0 ? 'up' : 'down',
        });
      }
      list.sort((a, b) => ((b['delta'] as double).abs()).compareTo((a['delta'] as double).abs()));
      return list.take(3).toList();
    }

    return {
      'year': yy,
      'month': mm,
      'ym': ym,
      'isYear': false,
      'startDayCount': startDayCount,
      'firstFlow': firstFlow,
      'thisMonth': {
        'income': monthIncome,
        'expense': monthExpense,
        'balance': monthIncome - monthExpense,
      },
      'lastMonthBalance': lastMonthBalance,
      'expenseByCategory': expenseByCategory,
      'topExpenses': topExpenses,
      'highestDayExpense': highestDay,
      'dailyAvgExpense': dailyAvgExpense,
      'expenseCompare': compare,
      'expenseChangeVsPrev': diffTop('expense'),
      'monthIncome': monthIncome,
      'topIncomes': topIncomes,
      'incomeCompare': compare,
      'incomeChangeVsPrev': diffTop('income'),
    };
  }

  Future<Map<String, dynamic>> getBillYearDetail(int year) async {
    final bookId = await _curBook();
    final all = await LocalDb.instance.allFlows(bookId);
    final now = DateTime.now();
    final isCurrent = year == now.year;
    final elapsedMonths = isCurrent ? now.month + 1 : 12;

    // 首笔流水（整个账簿最早日）
    final firstFlow = _wholeBookFirstFlow(all);
    final firstDate = firstFlow.isNotEmpty ? DateTime.tryParse(firstFlow) : null;
    int startDayCount = 0;
    if (firstDate != null) {
      final ref = isCurrent ? now : DateTime(year, 12, 31);
      if (!ref.isBefore(firstDate)) startDayCount = ref.difference(firstDate).inDays + 1;
    }

    // 全年 / 上年聚合
    final yearRows = <Map<String, Object?>>[];
    final prevYearRows = <Map<String, Object?>>[];
    for (final f in all) {
      final ft = (f['flow_time'] as String? ?? '');
      if (!ft.startsWith('$year')) {
        if (ft.startsWith('${year - 1}')) prevYearRows.add(f);
        continue;
      }
      yearRows.add(f);
    }
    double yearIncome = 0, yearExpense = 0;
    final cat = <String, double>{};
    final monthExpense = <String, double>{};
    for (final f in yearRows) {
      final t = (f['type'] ?? '') as String;
      final amt = ((f['amount'] as num?) ?? 0).toDouble();
      final c = ((f['category'] as String?) ?? '未标注');
      if (t == 'income') yearIncome += amt;
      else { yearExpense += amt; cat[c] = (cat[c] ?? 0) + amt; }
      final m = (f['flow_time'] as String).substring(0, 7);
      monthExpense[m] = (monthExpense[m] ?? 0) + (t == 'expense' ? amt : 0);
    }
    double lastYearBalance = 0;
    for (final f in prevYearRows) {
      final t = (f['type'] ?? '') as String;
      final amt = ((f['amount'] as num?) ?? 0).toDouble();
      lastYearBalance += (t == 'income' ? amt : -amt);
    }

    final expenseByCategory = cat.entries
        .map((e) => {
              'category': e.key,
              'amount': e.value,
              'percent': yearExpense > 0 ? (e.value / yearExpense * 1000).round() / 10 : 0,
            })
        .toList()
      ..sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    Map<String, Object?> _flowRowToMap(Map<String, Object?> f) => {
          'id': f['id'],
          'flow_time': f['flow_time'],
          'amount': f['amount'],
          'category': f['category'],
          'description': f['description'],
          'payment_method': f['payment_method'],
        };
    final expenseList = yearRows.where((f) => (f['type'] ?? '') == 'expense').toList()
      ..sort((a, b) => ((b['amount'] as num?) ?? 0).compareTo((a['amount'] as num?) ?? 0));
    final topExpenses = expenseList.take(3).map(_flowRowToMap).toList();
    final incomeList = yearRows.where((f) => (f['type'] ?? '') == 'income').toList()
      ..sort((a, b) => ((b['amount'] as num?) ?? 0).compareTo((a['amount'] as num?) ?? 0));
    final topIncomes = incomeList.take(3).map(_flowRowToMap).toList();

    final sortedMonths = monthExpense.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final highestMonth = sortedMonths.isNotEmpty
        ? {'date': sortedMonths.first.key, 'amount': sortedMonths.first.value}
        : {'date': '', 'amount': 0};
    final monthlyAvgExpense = elapsedMonths > 0 ? yearExpense / elapsedMonths : 0;

    final compare = List.generate(12, (m) {
      final k = '$year-${(m + 1).toString().padLeft(2, '0')}';
      double i = 0, e = 0;
      for (final f in yearRows) {
        if (!(f['flow_time'] as String).startsWith(k)) continue;
        final t = (f['type'] ?? '') as String;
        final a = ((f['amount'] as num?) ?? 0).toDouble();
        if (t == 'income') i += a; else e += a;
      }
      return {'ym': k, 'label': (m + 1).toString(), 'income': i, 'expense': e};
    });

    Map<String, double> _catSums(int y, String type) {
      final r = <String, double>{};
      for (final f in all) {
        final ft = (f['flow_time'] as String? ?? '');
        if (!ft.startsWith('$y')) continue;
        if ((f['type'] ?? '') != type) continue;
        final c = ((f['category'] as String?) ?? '未标注');
        r[c] = (r[c] ?? 0) + ((f['amount'] as num?) ?? 0).toDouble();
      }
      return r;
    }

    List<Map<String, Object?>> diffTop(String type) {
      final prev = _catSums(year - 1, type);
      final cur = _catSums(year, type);
      final names = <String>{...prev.keys, ...cur.keys};
      final list = <Map<String, Object?>>[];
      for (final c in names) {
        final p = prev[c] ?? 0;
        final k = cur[c] ?? 0;
        final delta = (k - p).round() / 100;
        if (delta.abs() < 0.005) continue;
        list.add({
          'category': c,
          'prev': p,
          'cur': k,
          'delta': delta,
          'dir': delta > 0 ? 'up' : 'down',
        });
      }
      list.sort((a, b) => ((b['delta'] as double).abs()).compareTo((a['delta'] as double).abs()));
      return list.take(3).toList();
    }

    return {
      'year': year,
      'month': 0,
      'ym': '$year',
      'isYear': true,
      'startDayCount': startDayCount,
      'firstFlow': firstFlow,
      'thisMonth': {
        'income': yearIncome,
        'expense': yearExpense,
        'balance': yearIncome - yearExpense,
      },
      'lastMonthBalance': lastYearBalance,
      'expenseByCategory': expenseByCategory,
      'topExpenses': topExpenses,
      'highestDayExpense': highestMonth,
      'dailyAvgExpense': monthlyAvgExpense,
      'expenseCompare': compare,
      'expenseChangeVsPrev': diffTop('expense'),
      'monthIncome': yearIncome,
      'topIncomes': topIncomes,
      'incomeCompare': compare,
      'incomeChangeVsPrev': diffTop('income'),
    };
  }

  Future<AiStatus> getAiStatus() => _api.getAiStatus();
  Future<AiParseResult> parseText(String text) => _api.parseText(text);
  Future<AiAnalyze> analyzeMonth({String? month}) =>
      _api.analyzeMonth(month: month);
  Future<FlowQuery> queryFlows(
          {required String category, String period = 'this_month'}) =>
      _api.queryFlows(category: category, period: period);
  Future<List<AiModel>> getAiModels() => _api.getAiModels();
  Future<Map<String, dynamic>> getSavingsMonthItems(String ym) =>
      _api.getSavingsMonthItems(ym);
  Future<Meta> getMeta() => _api.getMeta();
  Future<List<Map<String, dynamic>>> getOpLogs({int limit = 50}) =>
      _api.getOpLogs(limit: limit);
  Future<int> ping() => _api.ping();
  Future<LoginResult> login(String username, String password) =>
      _api.login(username, password);
  Future<Book> createBook(String name) => _api.createBook(name);

  Map<String, Object?> _rowFromBody(int bookId, int id, Map<String, dynamic> b,
          {String? uuid, bool dirty = false}) =>
      {
        'id': id,
        'book_id': bookId,
        'user_id': _user?.id ?? 0,
        'type': b['type'] ?? 'expense',
        'amount': (b['amount'] as num?)?.toDouble() ?? 0,
        'category': b['category'] ?? '',
        'payment_method': b['payment_method'] ?? '',
        'description': b['description'] ?? '',
        'flow_time': b['flow_time'] ?? '',
        'source': b['source'] ?? '',
        'attribution': b['attribution'] ?? '',
        'attribution_uid': b['attribution_uid'],
        'attribution_color': null,
        'client_uuid': uuid,
        'dirty': dirty ? 1 : 0,
      };

  bool _isNetworkErr(Object e) {
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('Connection') ||
        s.contains('timed out') ||
        s.contains('TimeoutException') ||
        s.contains('HandshakeException') ||
        s.contains('Failed host lookup') ||
        s.contains('网络');
  }
}

/// 页面统一使用的数据入口（离线优先）
final localApiProvider = Provider<LocalFirstApi>((ref) {
  final api = ref.watch(apiProvider);
  SyncEngine.instance.bind(api);
  final lfa = LocalFirstApi(api);
  lfa.currentUser = ref.watch(sessionProvider).user;
  return lfa;

});
