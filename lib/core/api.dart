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

  Future<void> createFlow(Map<String, dynamic> body) async {
    await _req(() => _dio.post('/flows', data: body));
  }

  Future<void> updateFlow(int id, Map<String, dynamic> body) async {
    await _req(() => _dio.put('/flows/$id', data: body));
  }

  Future<void> deleteFlow(int id) async {
    await _req(() => _dio.delete('/flows/$id'));
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

  Future<BillRow> getMonthDetail(String ym) async {
    final d = await _req(
        () => _dio.get('/bills/month-detail', queryParameters: {'ym': ym}));
    return BillRow.fromJson(d);
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

  Future<void> addWallet({
    required String name,
    double target = 0,
    String linkCategory = '',
    String linkFrom = '',
  }) async {
    final body = {
      'name': name,
      'target': target,
      'link_category': linkCategory,
      'link_from': linkFrom,
    };
    await _req(() => _dio.post('/wallets', data: body));
  }

  Future<AiStatus> getAiStatus() async {
    final d = await _req(() => _dio.get('/ai/status'));
    return AiStatus.fromJson(d);
  }

  Future<AiParseResult> parseText(String text) async {
    final d = await _req(() => _dio.post('/ai/parse', data: {'text': text}));
    return AiParseResult.fromJson(d);
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
}

class LoginResult {
  final String token;
  final User user;
  LoginResult({required this.token, required this.user});
}
