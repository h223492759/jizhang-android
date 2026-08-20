import 'package:dio/dio.dart';
import 'models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// 对接 jizhang 后端的 HTTP 客户端。
/// - baseUrl = serverUrl + '/api'
/// - 拦截器自动附加 Authorization: Bearer <token>
/// - 拦截器自动附加 ?bookId=<bookId>（后端 requireBook 会读取）
class ApiClient {
  final String serverUrl;
  final String? token;
  final int? bookId;
  late final Dio _dio;

  ApiClient({required this.serverUrl, this.token, this.bookId}) {
    final base = '${serverUrl.replaceAll(RegExp(r'/$'), '')}/api';
    _dio = Dio(BaseOptions(baseUrl: base, connectTimeout: const Duration(seconds: 15)));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (token != null && token!.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        if (bookId != null) {
          final q = Map<String, dynamic>.from(options.queryParameters);
          q['bookId'] = bookId.toString();
          options.queryParameters = q;
        }
        handler.next(options);
      },
    ));
  }

  Future<dynamic> _req(Future<Response> Function() fn) async {
    try {
      final res = await fn();
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw ApiException(data['error'].toString());
      }
      return data;
    } on DioException catch (e) {
      if (e.response?.data is Map && e.response?.data['error'] != null) {
        throw ApiException(e.response!.data['error'].toString());
      }
      final url = e.requestOptions.uri.toString();
      final type = e.type.toString();
      final detail = e.message ?? '无详情';
      final isConn = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      final base = isConn
          ? '连接服务器失败'
          : e.type == DioExceptionType.badCertificate
              ? '证书校验失败'
              : e.type == DioExceptionType.cancel
                  ? '请求被取消'
                  : e.type == DioExceptionType.badResponse
                      ? '服务器返回异常'
                      : '未知网络错误';
      final hint = isConn
          ? '请检查：\n1. 手机与服务器是否同一 WiFi\n2. 应用是否有网络权限\n3. 后端是否监听 0.0.0.0:9600'
          : e.type == DioExceptionType.badCertificate
              ? '如使用自签名 HTTPS，请确认证书域名/有效期正确'
              : '';
      throw ApiException('$base\nURL: $url\n类型: $type\n详情: $detail${hint.isNotEmpty ? '\n$hint' : ''}');
    }
  }

  Future<Meta> getMeta() async {
    final d = await _req(() => _dio.get('/meta'));
    return Meta.fromJson(d);
  }

  /// 测试与后端的连通性，返回耗时（毫秒）或抛出异常。
  Future<int> ping() async {
    final stopwatch = Stopwatch()..start();
    await _req(() => _dio.get('/meta',
        options: Options(sendTimeout: Duration(seconds: 10),
                         receiveTimeout: Duration(seconds: 10))));
    stopwatch.stop();
    return stopwatch.elapsedMilliseconds;
  }

  Future<LoginResult> login(String username, String password) async {
    final d = await _req(() => _dio.post('/auth/login',
        data: {'username': username, 'password': password}));
    return LoginResult(
      token: d['token'], user: User.fromJson(d['user']));
  }

  Future<List<Book>> getBooks() async {
    final d = await _req(() => _dio.get('/books'));
    return Book.listFrom(d);
  }

  Future<Book> createBook(String name) async {
    final d = await _req(() => _dio.post('/books', data: {'name': name}));
    return Book.fromJson(d);
  }

  Future<List<Category>> getCategories() async {
    final d = await _req(() => _dio.get('/categories'));
    return Category.listFrom(d);
  }

  // ---------------- 定期记账 ----------------
  Future<List<Recurring>> getRecurring() async {
    final d = await _req(() => _dio.get('/recurring'));
    return Recurring.listFrom(d);
  }

  Future<int> addRecurring(Map<String, dynamic> body) async {
    final d = await _req(() => _dio.post('/recurring', data: body));
    return (d as Map<String, dynamic>)['id'] as int;
  }

  Future<void> updateRecurring(int id, Map<String, dynamic> body) async {
    await _req(() => _dio.put('/recurring/$id', data: body));
  }

  Future<void> deleteRecurring(int id) async {
    await _req(() => _dio.delete('/recurring/$id'));
  }

  // 把到期待生成的模板落成真实流水，返回生成笔数
  Future<int> generateRecurring() async {
    final d = await _req(() => _dio.post('/recurring/generate'));
    return (d as Map<String, dynamic>)['generated'] as int? ?? 0;
  }

  // 账本成员（定期模板归属下拉用）
  Future<List<AttributionMember>> getAttributions() async {
    final d = await _req(() => _dio.get('/flows/attributions'));
    final m = (d as Map<String, dynamic>)['members'] as List? ?? [];
    return m.map((e) => AttributionMember.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FlowPage> getFlows({
    String? start,
    String? end,
    String? type,
    String? category,
    int page = 1,
    int pageSize = 50,
  }) async {
    final q = <String, dynamic>{
      'page': page,
      'pageSize': pageSize,
      'sortBy': 'flow_time',
      'order': 'desc',
    };
    if (start != null) q['start'] = start;
    if (end != null) q['end'] = end;
    if (type != null) q['type'] = type;
    if (category != null) q['category'] = category;
    final d = await _req(() => _dio.get('/flows', queryParameters: q));
    return FlowPage.fromJson(d);
  }

  Future<int> createFlow(Map<String, dynamic> body) async {
    final d = await _req(() => _dio.post('/flows', data: body));
    return (d is Map && d['id'] != null) ? (d['id'] as num).toInt() : 0;
  }

  Future<void> updateFlow(int id, Map<String, dynamic> body) async {
    await _req(() => _dio.put('/flows/$id', data: body));
  }

  Future<void> deleteFlow(int id) async {
    await _req(() => _dio.delete('/flows/$id'));
  }

  /// 增量同步：返回 {all_ids, changed[], server_time}；不传 since = 全量
  Future<Map<String, dynamic>> fetchFlowsSync({String? since}) async {
    final q = <String, dynamic>{};
    if (since != null && since.isNotEmpty) q['since'] = since;
    final d = await _req(() => _dio.get('/flows/sync', queryParameters: q));
    return d as Map<String, dynamic>;
  }

  /// 预算设置全量（跨年，离线镜像用）
  Future<List<Map<String, dynamic>>> getBudgetSettings() async {
    final d = await _req(() => _dio.get('/budgets/settings'));
    return ((d as Map)['list'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  /// 服务器操作审计日志（最近 N 条）
  Future<List<Map<String, dynamic>>> getOpLogs({int limit = 50}) async {
    final d = await _req(
        () => _dio.get('/oplogs', queryParameters: {'limit': limit}));
    return ((d as Map)['list'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  Future<Overview> getOverview({String? start, String? end}) async {
    final q = <String, dynamic>{};
    if (start != null) q['start'] = start;
    if (end != null) q['end'] = end;
    final d = await _req(() => _dio.get('/stats/overview', queryParameters: q));
    return Overview.fromJson(d);
  }

  Future<List<CatStat>> getCategoryStat(
      {String? type, String? start, String? end}) async {
    final q = <String, dynamic>{};
    if (type != null) q['type'] = type;
    if (start != null) q['start'] = start;
    if (end != null) q['end'] = end;
    final d = await _req(() => _dio.get('/stats/category', queryParameters: q));
    return CatStat.listFrom(d);
  }

  Future<List<DailyStat>> getDaily({String? start, String? end}) async {
    final q = <String, dynamic>{};
    if (start != null) q['start'] = start;
    if (end != null) q['end'] = end;
    final d = await _req(() => _dio.get('/stats/daily', queryParameters: q));
    return DailyStat.listFrom(d);
  }

  Future<List<MonthlyStat>> getMonthly({int? year, String? category}) async {
    final q = <String, dynamic>{};
    if (year != null) q['year'] = year;
    if (category != null) q['category'] = category;
    final d = await _req(() => _dio.get('/stats/monthly', queryParameters: q));
    return MonthlyStat.listFrom(d);
  }

  Future<BudgetData> getBudgets({int? year}) async {
    final q = <String, dynamic>{};
    if (year != null) q['year'] = year;
    final d = await _req(() => _dio.get('/budgets', queryParameters: q));
    return BudgetData.fromJson(d);
  }

  Future<void> setBudget({
    required int year,
    String? category,
    required double amount,
    String? expression,
    List<String>? categories,
  }) async {
    final body = <String, dynamic>{'year': year, 'amount': amount};
    if (category != null) body['category'] = category;
    if (expression != null) body['expression'] = expression;
    if (categories != null) body['categories'] = categories;
    await _req(() => _dio.post('/budgets', data: body));
  }

  Future<void> deleteBudget({required int year, String category = ''}) async {
    await _req(() => _dio
        .delete('/budgets', queryParameters: {'year': year, 'category': category}));
  }

  Future<BillMonthly> getBillMonthly({int? year}) async {
    final q = <String, dynamic>{};
    if (year != null) q['year'] = year;
    final d = await _req(() => _dio.get('/bills/monthly', queryParameters: q));
    return BillMonthly.fromJson(d);
  }

  Future<BillYearly> getBillYearly() async {
    final d = await _req(() => _dio.get('/bills/yearly'));
    return BillYearly.fromJson(d);
  }

  Future<Map<String, dynamic>> getBillMonthDetail(String ym) async {
    final d = await _req(
        () => _dio.get('/bills/month-detail', queryParameters: {'ym': ym}));
    return d as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getBillYearDetail(int year) async {
    final d = await _req(
        () => _dio.get('/bills/year-detail', queryParameters: {'year': year}));
    return d as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSavingsItemHistory(int id) async {
    final d = await _req(() => _dio.get('/savings/items/$id/history'));
    return d as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getWalletTxns(int id) async {
    final d = await _req(() => _dio.get('/wallets/$id/txns'));
    return d as Map<String, dynamic>;
  }

  Future<void> addWalletTxn(int id,
      {required double amount, required String direction, required String ymd, String note = ''}) async {
    await _req(() => _dio.post('/wallets/$id/txns',
        data: {'amount': amount, 'direction': direction, 'ymd': ymd, 'note': note}));
  }

  Future<SavingsOverview> getSavings() async {
    final d = await _req(() => _dio.get('/savings'));
    return SavingsOverview.fromJson(d);
  }

  Future<void> setSavingsGoal({required double target, String? note}) async {
    final body = <String, dynamic>{'target': target};
    if (note != null) body['note'] = note;
    await _req(() => _dio.put('/savings/goal', data: body));
  }

  Future<WalletsData> getWallets() async {
    final d = await _req(() => _dio.get('/wallets'));
    return WalletsData.fromJson(d);
  }

  Future<void> addSavingsItem({
    required String name,
    required double amount,
    required int sign,
    String? asOf,
    String? asOfEnd,
    String? note,
  }) async {
    final body = <String, dynamic>{'name': name, 'amount': amount, 'sign': sign};
    if (asOf != null) body['as_of'] = asOf;
    if (asOfEnd != null) body['as_of_end'] = asOfEnd;
    if (note != null) body['note'] = note;
    await _req(() => _dio.post('/savings/items', data: body));
  }

  Future<void> updateSavingsItem({
    required int id,
    required String name,
    required double amount,
    required int sign,
    String? asOf,
    String? asOfEnd,
    String? note,
  }) async {
    final body = <String, dynamic>{'name': name, 'amount': amount, 'sign': sign};
    if (asOf != null) body['as_of'] = asOf;
    if (asOfEnd != null) body['as_of_end'] = asOfEnd;
    if (note != null) body['note'] = note;
    await _req(() => _dio.put('/savings/items/$id', data: body));
  }

  Future<void> deleteSavingsItem(int id) async {
    await _req(() => _dio.delete('/savings/items/$id'));
  }

  // 资金细则调序：ids 为最新顺序
  Future<void> reorderSavingsItems(List<int> ids) async {
    await _req(() => _dio.post('/savings/items/order', data: {'ids': ids}));
  }

  Future<void> bulkUpdateSavingsItems({
    required List<Map<String, dynamic>> items,
    String? ymd,
    String? mode,
  }) async {
    final body = <String, dynamic>{'items': items};
    if (ymd != null && ymd.isNotEmpty) body['ymd'] = ymd;
    if (mode != null && mode.isNotEmpty) body['mode'] = mode;
    await _req(() => _dio.post('/savings/items/bulk', data: body));
  }

  Future<Map<String, dynamic>> getSavingsMonthItems(String ym) async {
    final d = await _req(
        () => _dio.get('/savings/items/history-month', queryParameters: {'ym': ym}));
    return d as Map<String, dynamic>;
  }

  // 直接设置某细则当前金额并记一条历史（资金细则「新增记录」，可指定日期 ymd）
  Future<void> setSavingsItemAmount(int id,
      {required double amount, String note = '', String ymd = ''}) async {
    await _req(() => _dio.post('/savings/items/$id/set-amount',
        data: {'amount': amount, 'note': note, if (ymd.isNotEmpty) 'ymd': ymd}));
  }

  // 修改某细则的一条历史记录
  Future<void> updateSavingsItemHistory(int id, int hid,
      {required double amount, String note = ''}) async {
    await _req(() => _dio.put('/savings/items/$id/history/$hid',
        data: {'amount': amount, 'note': note}));
  }

  // 删除某细则的一条历史记录
  Future<void> deleteSavingsItemHistory(int id, int hid) async {
    await _req(() => _dio.delete('/savings/items/$id/history/$hid'));
  }

  Future<void> deleteSavingsHistory(String ymd) async {
    await _req(() => _dio.delete('/savings/history/$ymd'));
  }

  Future<void> updateSavingsHistory({
    required String ymd,
    required double asset,
    required double liability,
  }) async {
    await _req(() => _dio.put('/savings/history/$ymd',
        data: {'asset': asset, 'liability': liability}));
  }

  Future<int> addWallet({
    required String name,
    String icon = '👛',
    double target = 0,
    String linkCategory = '',
    String linkFrom = '',
    String note = '',
    List<Map<String, String>>? linkLinks,
  }) async {
    final body = {
      'name': name,
      'icon': icon,
      'target': target,
      'link_category': linkCategory,
      'link_from': linkFrom,
      'note': note,
      if (linkLinks != null) 'link_links': linkLinks,
    };
    final d = await _req(() => _dio.post('/wallets', data: body));
    return (d['id'] as num).toInt();
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
  }) async {
    final body = {
      'name': name,
      'icon': icon,
      'target': target,
      'note': note,
      'link_category': linkCategory,
      'link_from': linkFrom,
      if (linkLinks != null) 'link_links': linkLinks,
    };
    await _req(() => _dio.put('/wallets/$id', data: body));
  }

  Future<void> deleteWallet(int id) async {
    await _req(() => _dio.delete('/wallets/$id'));
  }

  Future<void> updateWalletTxn(int id,
      {required double amount,
      required String direction,
      required String ymd,
      String note = ''}) async {
    await _req(() => _dio.put('/wallets/txns/$id',
        data: {'amount': amount, 'direction': direction, 'ymd': ymd, 'note': note}));
  }

  Future<void> deleteWalletTxn(int id) async {
    await _req(() => _dio.delete('/wallets/txns/$id'));
  }

  Future<AiStatus> getAiStatus() async {
    final d = await _req(() => _dio.get('/ai/status'));
    return AiStatus.fromJson(d);
  }

  Future<AiParseResult> parseText(String text) async {
    final d = await _req(() => _dio.post('/ai/parse', data: {'text': text}));
    return AiParseResult.fromJson(d);
  }

  /// 流水查询（发现页 AI 问账用）：按分类+时段统计合计
  Future<FlowQuery> queryFlows({required String category, String period = 'this_month'}) async {
    final d = await _req(() => _dio.get('/flows/query', queryParameters: {
      'category': category,
      'period': period,
    }));
    return FlowQuery.fromJson(d);
  }

  /// 商户分类（学习闭环）：先查商户→分类映射，命中直接返回；否则 AI 分类
  Future<AiParseResult> classifyMerchant(
      {required String merchant, String text = '', double amount = 0, String type = 'expense', String paymentMethod = ''}) async {
    final d = await _req(() => _dio.post('/merchants/classify', data: {
      'merchant': merchant,
      'text': text,
      'amount': amount,
      'type': type,
      'payment_method': paymentMethod,
    }));
    return AiParseResult.fromJson(d);
  }

  /// 学习：用户确认/修改分类后写入 商户→分类 映射
  Future<void> learnMerchant(String merchant, String category) async {
    await _req(() => _dio.post('/merchants', data: {
      'merchant': merchant,
      'category': category,
    }));
  }

  Future<AiAnalyze> analyzeMonth({String? month}) async {
    final q = <String, dynamic>{};
    if (month != null) q['month'] = month;
    final d = await _req(() => _dio.get('/ai/analyze', queryParameters: q));
    return AiAnalyze.fromJson(d);
  }

  Future<List<AiModel>> getAiModels() async {
    final d = await _req(() => _dio.get('/settings/ai'));
    return AiModel.listFrom(d['models'] ?? []);
  }

  Future<PresetsData> getPresets({required String type, int limit = 12}) async {
    final d = await _req(() => _dio.get('/presets', queryParameters: {
      'type': type,
      'limit': limit,
    }));
    return PresetsData.fromJson(d);
  }

  /// 返回完整原始响应（presets/frequent/recent/hidden/synced_at），
  /// 供本地镜像表全量同步用（不丢失 hidden / count / last_time 等字段）
  Future<Map<String, dynamic>> getPresetsRaw(
      {required String type, int limit = 500}) async {
    final d = await _req(() => _dio.get('/presets', queryParameters: {
      'type': type,
      'limit': limit,
    }));
    return (d as Map).cast<String, dynamic>();
  }

  /// 同步指纹：服务器算所有表数据版本，与客户端上次一致则 unchanged（跳过全量拉取）
  Future<Map<String, dynamic>> getFingerprint({String? lastFp}) async {
    final d = await _req(() => _dio.get('/sync/fingerprint', queryParameters: {
      if (lastFp != null && lastFp.isNotEmpty) 'fp': lastFp,
    }));
    return (d as Map).cast<String, dynamic>();
  }
}

class LoginResult {
  final String token;
  final User user;
  LoginResult({required this.token, required this.user});
}
