import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/auth_trace.dart';
import 'package:jizhang_android/core/db.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/storage.dart';

class SessionState {
  final String? serverUrl;
  final String? token;
  final User? user;
  final int? bookId;
  final List<Book> books;

  /// v2.2.25：是否还在恢复本地登录态（读 SharedPreferences / 镜像文件）。
  /// 恢复完成前 RootRouter 不渲染「服务器 / 登录」页 —— 以前是同步判 hasServer/hasToken，
  /// 而登录态要异步读盘，冷启动会先闪一下登录页，看起来像「打开就被登出了」。
  final bool restoring;

  SessionState({
    this.serverUrl,
    this.token,
    this.user,
    this.bookId,
    this.books = const [],
    this.restoring = true,
  });

  SessionState copyWith({
    String? serverUrl,
    String? token,
    User? user,
    int? bookId,
    List<Book>? books,
    bool? restoring,
    bool clearToken = false,
    bool clearUser = false,
    bool clearBook = false,
  }) =>
      SessionState(
        serverUrl: serverUrl ?? this.serverUrl,
        token: clearToken ? null : (token ?? this.token),
        user: clearUser ? null : (user ?? this.user),
        bookId: clearBook ? null : (bookId ?? this.bookId),
        books: books ?? this.books,
        restoring: restoring ?? this.restoring,
      );

  ApiClient get api =>
      ApiClient(serverUrl: serverUrl ?? '', token: token, bookId: bookId);

  bool get hasServer => serverUrl != null && serverUrl!.isNotEmpty;
  bool get hasToken => token != null && token!.isNotEmpty;
  bool get hasBook => bookId != null;
}

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier() : super(SessionState()) {
    _load();
  }

  /// 启动恢复入口：**整体兜底**。
  ///
  /// ⚠️ v2.2.25 起 `restoring` 默认为 true（RootRouter 先渲染过渡页，避免冷启动闪登录页）。
  /// 代价是：只要 `_loadInner()` 里有异常逃逸、而没人把 restoring 置回 false，
  /// App 就会**永远停在过渡页** —— 比「回到登录页」更糟。所以这里 finally 强制收尾。
  Future<void> _load() async {
    try {
      await _loadInner();
    } catch (e) {
      AuthTrace.log('[登录态] 启动恢复异常（已兜底，界面照常渲染）：$e');
    } finally {
      if (state.restoring) state = state.copyWith(restoring: false);
    }
  }

  Future<void> _loadInner() async {
    // ① 逐项读取（Storage 各 getter 内部已各自容错，这里再兜一层）：
    //    v2.2.23：账本列表先用本地兜底（持久化 JSON），再向服务器刷新。
    //    否则「启动瞬间请求失败」会让 books 一直空着 → 「切换账本」里没有可选项，
    //    要重启 App 才恢复（用户报的「账本不可切换」）。
    String? server;
    String? token;
    String? userJson;
    String? booksJson;
    int? bookId;
    try {
      server = await Storage.getServerUrl();
      token = await Storage.getToken();
      userJson = await Storage.getUserJson();
      bookId = await Storage.getBookId();
      booksJson = await Storage.getBooksJson();
    } catch (e) {
      AuthTrace.log('[登录态] 启动读盘异常（沿用已读到的部分）：$e');
    }

    // ② 解析容错：坏掉的 user_json **只丢用户信息**，绝不牵连 token。
    //    ⚠️ 以前这里直接 `User.fromJsonString(userJson)` 裸调，只要它抛异常，
    //    整个 _load() 就从这里中断 —— 后面的镜像恢复根本执行不到，
    //    表现就是「明明有镜像、打开 App 还是登录页」。
    User? user;
    if (userJson != null && userJson.isNotEmpty) {
      try {
        user = User.fromJsonString(userJson);
      } catch (e) {
        AuthTrace.log('[登录态] 用户信息解析失败（不影响登录态）：$e');
      }
    }

    state = state.copyWith(
      restoring: false,
      serverUrl: server,
      token: token,
      user: user,
      bookId: bookId,
      books: _decodeBooks(booksJson),
    );

    // ③ 镜像兜底：独立方法 + 独立 try，**无论上面发生什么都会执行**
    await _restoreFromMirror();

    AuthTrace.log(state.hasToken
        ? '[登录态] 启动：已载入登录态（账本 ${state.bookId ?? "未选"}）'
        : '[登录态] 启动：没有可用登录态，需要重新登录');

    if (!state.hasToken) return;
    if (state.books.isEmpty) {
      // 老版本升上来的：没有持久化 JSON，用本地镜像表兜底（同步时写入）
      try {
        final fallback = await _mirrorBooks();
        if (fallback.isNotEmpty) state = state.copyWith(books: fallback);
      } catch (_) {}
    }
    await refreshBooks();
  }

  /// SP 里没有 token 时，尝试从私有目录的镜像文件恢复登录态。
  ///
  /// ⚠️ 必须是**独立方法 + 独立 try**：以前它写在 `_load()` 的大 try 里、
  /// 位置又在用户 JSON 解析之后，解析一抛异常就永远执行不到 ——
  /// 明明有镜像却恢复不了，用户看到的就是「打开 App 变成登录页」。
  /// 只有用户主动退出登录 / 切换服务器才会删镜像，所以这里能恢复说明不是那两种情况。
  Future<void> _restoreFromMirror() async {
    try {
      if (state.hasToken) return;
      final m = await Storage.readMirror();
      if (m == null) return;
      final t = (m['token'] ?? '').toString();
      // 镜像必须属于**当前这台服务器**（或当前压根没有地址）才允许恢复，
      // 否则换过服务器之后会拿上一台的 token 用（登进错误的账号）。
      final mServer = _normUrl((m['server_url'] ?? '').toString());
      final curServer = _normUrl(state.serverUrl ?? '');
      final sameServer =
          mServer.isEmpty || curServer.isEmpty || mServer == curServer;
      if (t.isEmpty || !sameServer) return;

      final s = (m['server_url'] ?? '').toString();
      final u = (m['user_json'] ?? '').toString();
      final bs = (m['books_json'] ?? '').toString();
      final b = m['book_id'];
      final bid = b is num ? b.toInt() : null;

      // 回写 SP，后续按正常路径走
      if (s.isNotEmpty) await Storage.setServerUrl(s);
      await Storage.setToken(t);
      if (u.isNotEmpty) await Storage.setUserJson(u);
      if (bid != null) await Storage.setBookId(bid);
      if (bs.isNotEmpty) await Storage.setBooksJson(bs);

      // 镜像里的 user_json 坏了也不能让「恢复登录」失败
      User? user;
      if (u.isNotEmpty) {
        try {
          user = User.fromJsonString(u);
        } catch (_) {}
      }

      state = state.copyWith(
        serverUrl: s.isNotEmpty ? s : null,
        token: t,
        user: user,
        bookId: bid,
        books: bs.isNotEmpty ? _decodeBooks(bs) : null,
      );
      AuthTrace.log('[登录态] 本机记录为空 → 已从本地镜像自动恢复登录（未登出）');
    } catch (e) {
      // 恢复失败也只记录，绝不动已有登录态；界面靠调用方已设的 restoring:false 正常渲染
      AuthTrace.log('[登录态] 镜像恢复失败（保留现有登录态）：$e');
    }
  }

  Future<void> setServer(String url) async {
    final u = url.trim();
    await Storage.setServerUrl(u);
    state = state.copyWith(serverUrl: u);
  }

  /// 切换/选择一个服务器地址：设为当前并清空登录态（token 与服务器绑定）。
  ///
  /// v2.2.25：**目标地址与当前相同 → 直接返回，什么都不做**。
  /// 以前在「切换服务器」页点一下当前正在用的那台，也会走到这里把 token 清掉 → 立刻登出，
  /// 就是用户报的「账户会登出」（点进去看一眼地址就掉线了）。
  /// 返回 true = 真的换了服务器（登录态已清空）；false = 同一地址，未做任何改动。
  Future<bool> selectServer(String url) async {
    final u = _normUrl(url);
    if (u.isEmpty) return false;
    if (u == _normUrl(state.serverUrl ?? '')) return false;
    await setServer(u);
    await Storage.clearAuth();
    await Storage.deleteMirror();
    AuthTrace.log('[登录态] 切换到服务器 $u → 清除登录态（需重新登录）');
    state = state.copyWith(
        restoring: false,
        clearToken: true,
        clearUser: true,
        clearBook: true,
        books: const []);
    return true;
  }

  /// 归一化服务器地址：去空白 + 去尾部斜杠 + 统一小写，
  /// 让 `http://a:9600/`、`http://a:9600`、`HTTP://A:9600` 被认成同一台
  /// （避免误判为「切换」→ 清了登录态把人踢下线）
  String _normUrl(String u) => u.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();

  /// 目标地址是否与当前不同（只读判断，不写任何东西）。
  /// UI 用它决定「要不要提醒即将重新登录」，避免在页面里重复一份地址归一化逻辑。
  bool isDifferentServer(String url) {
    final u = _normUrl(url);
    return u.isNotEmpty && u != _normUrl(state.serverUrl ?? '');
  }

  /// 只改服务器地址、**保留登录态**：给「编辑服务器地址」用。
  /// 同一个后端换了 IP / 端口时 token 仍然有效，不该把用户踢下线（用户报的「莫名登出」）。
  Future<void> updateServerAddress(String url) async {
    final u = _normUrl(url);
    if (u.isEmpty) return;
    if (u == _normUrl(state.serverUrl ?? '')) return;
    await setServer(u);
    AuthTrace.log('[登录态] 服务器地址改为 $u（保留登录态）');
  }

  Future<void> login(String username, String password) async {
    final res = await state.api.login(username, password);
    await Storage.setToken(res.token);
    await Storage.setUserJson(res.user.toJsonString());
    state = state.copyWith(token: res.token, user: res.user);
    // v2.2.25：登录成功立刻落一份镜像（哪怕后面拉账本失败也不会丢登录态）
    await _writeMirror();
    AuthTrace.log('[登录态] 登录成功：${res.user.username}');
    final books = await state.api.getBooks();
    await Storage.setBooksJson(_booksToJson(books));
    state = state.copyWith(books: books);
    await _writeMirror();
  }

  Future<void> selectBook(int bookId) async {
    await Storage.setBookId(bookId);
    state = state.copyWith(bookId: bookId);
    await _writeMirror();
  }

  /// v2.2.23：刷新账本列表——成功则落盘持久化；失败保留本地已有列表（绝不清空）。
  /// 回前台也会调用一次，这样启动时那次请求失败能自愈，不需要重启 App。
  Future<void> refreshBooks() async {
    if (!state.hasToken) return;
    try {
      final books = await state.api.getBooks();
      final json = _booksToJson(books);
      await Storage.setBooksJson(json);
      state = state.copyWith(books: books);
      // 镜像里的账本列表只在内容变化时写盘（回前台会频繁调用，避免无谓写文件）
      if (json != _lastMirrorBooks) {
        _lastMirrorBooks = json;
        await _writeMirror();
      }
    } catch (_) {
      if (state.books.isEmpty) {
        final fallback = await _mirrorBooks();
        if (fallback.isNotEmpty) state = state.copyWith(books: fallback);
      }
    }
  }

  /// 把当前登录态写入镜像文件（token 为空时内部会跳过）
  Future<void> _writeMirror() => Storage.writeMirror(
        serverUrl: state.serverUrl,
        token: state.token,
        userJson: state.user?.toJsonString(),
        bookId: state.bookId,
        booksJson: _booksToJson(state.books),
      );

  String? _lastMirrorBooks;

  Future<void> logout() async {
    await Storage.clearAuth();
    await Storage.deleteMirror();
    AuthTrace.log('[登录态] 用户主动退出登录');
    state = SessionState(serverUrl: state.serverUrl, books: const [], restoring: false);
  }

  /// 清掉当前服务器（连同登录态）：只在「把正在使用的服务器删掉、且列表已空」时调用。
  /// 不这么做的话，删完服务器再进 App 会一直停在旧的失效地址上。
  Future<void> clearServer() async {
    await Storage.setServerUrl('');
    await Storage.clearAuth();
    await Storage.deleteMirror();
    AuthTrace.log('[登录态] 删除了正在使用的服务器 → 清除登录态');
    state = SessionState(books: const [], restoring: false);
  }

  String _booksToJson(List<Book> books) =>
      '[' + books.map((b) => b.toJsonString()).join(',') + ']';

  List<Book> _decodeBooks(String? raw) {
    if (raw == null || raw.isEmpty) return const <Book>[];
    try {
      return Book.listFrom(jsonDecode(raw));
    } catch (_) {
      return const <Book>[];
    }
  }

  /// 本地镜像表（SyncEngine 同步时写入），离线时用作账本列表兜底
  Future<List<Book>> _mirrorBooks() async {
    try {
      final rows = await LocalDb.instance.getBooks();
      return rows
          .map((r) => Book(
                id: ((r['id'] ?? 0) as num).toInt(),
                name: (r['name'] ?? '') as String,
                ownerId: ((r['owner_id'] ?? 0) as num).toInt(),
                role: (r['role'] ?? 'editor') as String,
                members: ((r['members'] ?? 0) as num).toInt(),
                flows: ((r['flows'] ?? 0) as num).toInt(),
              ))
          .toList();
    } catch (_) {
      return const <Book>[];
    }
  }
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState>(
  (ref) => SessionNotifier(),
);

final apiProvider = Provider<ApiClient>((ref) => ref.watch(sessionProvider).api);

/// 数据版本计数器：记一笔 / 改删流水后自增，让首页等页面自动刷新。
final dataVersionProvider = StateProvider<int>((ref) => 0);
