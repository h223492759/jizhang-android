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

  Future<PresetsData> getPresets({required String type, int limit = 12}) async {
    final bookId = await _curBook();
    final db = LocalDb.instance;
    final presetRows = await db.getPresets(bookId, type);
    final presets = presetRows
        .map((r) => PresetName(
              name: (r['name'] ?? '') as String,
              category: r['category'] as String?,
              paymentMethod: r['payment_method'] as String?,
              amount: (r['amount'] as num?)?.toDouble(),
            ))
        .toList();
    // frequent / recent：本地从流水统计（与后端同口径，排除收藏名）
    final presetNames = presets.map((p) => p.name).toSet();
    final flows = await db.allFlows(bookId);
    final byName = <String, List<Map<String, Object?>>>{};
    for (final f in flows) {
      if (f['type'] != type) continue;
      final n = ((f['description'] as String?) ?? '').trim();
      if (n.isEmpty || presetNames.contains(n)) continue;
      byName.putIfAbsent(n, () => []).add(f);
    }
    PresetName fromGroup(List<Map<String, Object?>> g) {
      g.sort((a, b) => ((b['flow_time'] ?? '') as String)
          .compareTo((a['flow_time'] ?? '') as String));
      final latest = g.first;
      final sum = g.fold<double>(0,
          (s, f) => s + (((f['amount'] as num?) ?? 0).toDouble()));
      return PresetName(
        name: (latest['description'] ?? '') as String,
        category: latest['category'] as String?,
        paymentMethod: latest['payment_method'] as String?,
        amount: g.isEmpty ? null : sum / g.length,
      );
    }

    final groups = byName.values.toList();
    final frequent = groups
        .where((g) => g.length >= 2)
        .toList()
      ..sort((a, b) {
        final c = b.length.compareTo(a.length);
        if (c != 0) return c;
        return ((b.first['flow_time'] ?? '') as String)
            .compareTo((a.first['flow_time'] ?? '') as String);
      });
    final freqList = frequent.take(limit).map(fromGroup).toList();
    final freqNames = freqList.map((p) => p.name).toSet();
    final recent = groups
        .where((g) => !freqNames.contains(g.first['description']))
        .toList()
      ..sort((a, b) => ((b.first['flow_time'] ?? '') as String)
          .compareTo((a.first['flow_time'] ?? '') as String));
    final recentList = recent.take(limit).map(fromGroup).toList();
    return PresetsData(
        presets: presets, frequent: freqList, recent: recentList);
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

  Future<void> updateFlow(int id, Map<String, dynamic> body) async {
    final db = LocalDb.instance;
    final existing = await db.flowById(id);
    try {
      await _api.updateFlow(id, body);
      if (existing != null) await db.markDirty(id, false);
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
    } catch (e) {
      if (_isNetworkErr(e)) {
        await db.deleteFlowById(id);
        await db.enqueue('delete', 'flow', entityId: id);
        return;
      }
      rethrow;
    }
  }

  // ================= 储蓄（目标）写操作：在线 + 刷新本地镜像 =================

  Future<void> _savWrite(Future<void> Function() fn) async {
    await fn();
    await _refreshSavings();
  }

  Future<void> setSavingsGoal({required double target, String? note}) =>
      _savWrite(() => _api.setSavingsGoal(target: target, note: note));

  Future<void> addSavingsItem({
    required String name,
    required double amount,
    required int sign,
    String? asOf,
    String? asOfEnd,
    String? note,
  }) =>
      _savWrite(() => _api.addSavingsItem(
          name: name, amount: amount, sign: sign, asOf: asOf, asOfEnd: asOfEnd, note: note));

  Future<void> updateSavingsItem({
    required int id,
    required String name,
    required double amount,
    required int sign,
    String? asOf,
    String? asOfEnd,
    String? note,
  }) =>
      _savWrite(() => _api.updateSavingsItem(
          id: id, name: name, amount: amount, sign: sign, asOf: asOf, asOfEnd: asOfEnd, note: note));

  Future<void> deleteSavingsItem(int id) =>
      _savWrite(() => _api.deleteSavingsItem(id));

  Future<void> reorderSavingsItems(List<int> ids) =>
      _savWrite(() => _api.reorderSavingsItems(ids));

  Future<void> bulkUpdateSavingsItems({
    required List<Map<String, dynamic>> items,
    String? ymd,
    String? mode,
  }) =>
      _savWrite(() => _api.bulkUpdateSavingsItems(items: items, ymd: ymd, mode: mode));

  Future<void> setSavingsItemAmount(int id,
          {required double amount, String note = '', String ymd = ''}) =>
      _savWrite(() =>
          _api.setSavingsItemAmount(id, amount: amount, note: note, ymd: ymd));

  Future<void> updateSavingsItemHistory(int id, int hid,
          {required double amount, String note = ''}) =>
      _savWrite(() => _api.updateSavingsItemHistory(id, hid,
          amount: amount, note: note));

  Future<void> deleteSavingsItemHistory(int id, int hid) =>
      _savWrite(() => _api.deleteSavingsItemHistory(id, hid));

  Future<void> deleteSavingsHistory(String ymd) =>
      _savWrite(() => _api.deleteSavingsHistory(ymd));

  Future<void> updateSavingsHistory({
    required String ymd,
    required double asset,
    required double liability,
  }) =>
      _savWrite(() => _api.updateSavingsHistory(
          ymd: ymd, asset: asset, liability: liability));

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
  Future<List<Recurring>> getRecurring() => _api.getRecurring();
  Future<int> addRecurring(Map<String, dynamic> body) =>
      _api.addRecurring(body);
  Future<void> updateRecurring(int id, Map<String, dynamic> body) =>
      _api.updateRecurring(id, body);
  Future<void> deleteRecurring(int id) => _api.deleteRecurring(id);
  Future<int> generateRecurring() => _api.generateRecurring();
  Future<List<AttributionMember>> getAttributions() =>
      _api.getAttributions();
  Future<List<CatStat>> getCategoryStat(
          {String? start, String? end, String? type}) =>
      _api.getCategoryStat(start: start, end: end, type: type);
  Future<List<DailyStat>> getDaily({String? start, String? end}) =>
      _api.getDaily(start: start, end: end);
  Future<List<MonthlyStat>> getMonthly({int? year, String? category}) =>
      _api.getMonthly(year: year, category: category);
  Future<BudgetData> getBudgets({int? year}) => _api.getBudgets(year: year);
  Future<void> setBudget({
    required int year,
    String? category,
    required double amount,
    String? expression,
    List<String>? categories,
  }) =>
      _api.setBudget(
          year: year,
          category: category,
          amount: amount,
          expression: expression,
          categories: categories);
  Future<void> deleteBudget({required int year, String category = ''}) =>
      _api.deleteBudget(year: year, category: category);
  Future<BillMonthly> getBillMonthly({int? year}) =>
      _api.getBillMonthly(year: year);
  Future<BillYearly> getBillYearly() => _api.getBillYearly();
  Future<Map<String, dynamic>> getBillMonthDetail(String ym) =>
      _api.getBillMonthDetail(ym);
  Future<Map<String, dynamic>> getBillYearDetail(int year) =>
      _api.getBillYearDetail(year);
  Future<Map<String, dynamic>> getSavingsItemHistory(int id) =>
      _api.getSavingsItemHistory(id);
  Future<Map<String, dynamic>> getWalletTxns(int id) =>
      _api.getWalletTxns(id);
  Future<WalletsData> getWallets() => _api.getWallets();
  Future<void> addWalletTxn(int id,
          {required double amount,
          required String direction,
          required String ymd,
          String note = ''}) =>
      _api.addWalletTxn(id,
          amount: amount, direction: direction, ymd: ymd, note: note);
  Future<int> addWallet({
    required String name,
    String icon = '👛',
    double target = 0,
    String linkCategory = '',
    String linkFrom = '',
    String note = '',
  }) =>
      _api.addWallet(
          name: name,
          icon: icon,
          target: target,
          linkCategory: linkCategory,
          linkFrom: linkFrom,
          note: note);
  Future<void> updateWallet({
    required int id,
    required String name,
    String icon = '👛',
    double target = 0,
    String note = '',
    String linkCategory = '',
    String linkFrom = '',
  }) =>
      _api.updateWallet(
          id: id,
          name: name,
          icon: icon,
          target: target,
          note: note,
          linkCategory: linkCategory,
          linkFrom: linkFrom);
  Future<void> deleteWallet(int id) => _api.deleteWallet(id);
  Future<void> updateWalletTxn(int id,
          {required double amount,
          required String direction,
          required String ymd,
          String note = ''}) =>
      _api.updateWalletTxn(id,
          amount: amount, direction: direction, ymd: ymd, note: note);
  Future<void> deleteWalletTxn(int id) => _api.deleteWalletTxn(id);
  Future<AiStatus> getAiStatus() => _api.getAiStatus();
  Future<AiParseResult> parseText(String text) => _api.parseText(text);
  Future<AiAnalyze> analyzeMonth({String? month}) =>
      _api.analyzeMonth(month: month);
  Future<List<AiModel>> getAiModels() => _api.getAiModels();
  Future<Map<String, dynamic>> getSavingsMonthItems(String ym) =>
      _api.getSavingsMonthItems(ym);
  Future<Meta> getMeta() => _api.getMeta();
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
