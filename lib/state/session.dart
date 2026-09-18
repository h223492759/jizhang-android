import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/db.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/storage.dart';

class SessionState {
  final String? serverUrl;
  final String? token;
  final User? user;
  final int? bookId;
  final List<Book> books;

  SessionState({
    this.serverUrl,
    this.token,
    this.user,
    this.bookId,
    this.books = const [],
  });

  SessionState copyWith({
    String? serverUrl,
    String? token,
    User? user,
    int? bookId,
    List<Book>? books,
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

  Future<void> _load() async {
    final server = await Storage.getServerUrl();
    final token = await Storage.getToken();
    final userJson = await Storage.getUserJson();
    final bookId = await Storage.getBookId();
    // v2.2.23：账本列表先用本地兜底（持久化 JSON），再向服务器刷新。
    // 否则「启动瞬间请求失败」会让 books 一直空着 → 「切换账本」里没有可选项，
    // 要重启 App 才恢复（用户报的「账本不可切换」）。
    state = state.copyWith(
      serverUrl: server,
      token: token,
      user: userJson != null ? User.fromJsonString(userJson) : null,
      bookId: bookId,
      books: _decodeBooks(await Storage.getBooksJson()),
    );
    if (!state.hasToken) return;
    if (state.books.isEmpty) {
      // 老版本升上来的：没有持久化 JSON，用本地镜像表兜底（同步时写入）
      state = state.copyWith(books: await _mirrorBooks());
    }
    await refreshBooks();
  }

  Future<void> setServer(String url) async {
    final u = url.trim();
    await Storage.setServerUrl(u);
    state = state.copyWith(serverUrl: u);
  }

  /// 切换/选择一个服务器地址：设为当前并清空登录态（token 与服务器绑定）。
  Future<void> selectServer(String url) async {
    await setServer(url);
    await Storage.clearAuth();
    state = state.copyWith(
        clearToken: true, clearUser: true, clearBook: true, books: const []);
  }

  Future<void> login(String username, String password) async {
    final res = await state.api.login(username, password);
    await Storage.setToken(res.token);
    await Storage.setUserJson(res.user.toJsonString());
    state = state.copyWith(token: res.token, user: res.user);
    final books = await state.api.getBooks();
    await Storage.setBooksJson(_booksToJson(books));
    state = state.copyWith(books: books);
  }

  Future<void> selectBook(int bookId) async {
    await Storage.setBookId(bookId);
    state = state.copyWith(bookId: bookId);
  }

  /// v2.2.23：刷新账本列表——成功则落盘持久化；失败保留本地已有列表（绝不清空）。
  /// 回前台也会调用一次，这样启动时那次请求失败能自愈，不需要重启 App。
  Future<void> refreshBooks() async {
    if (!state.hasToken) return;
    try {
      final books = await state.api.getBooks();
      await Storage.setBooksJson(_booksToJson(books));
      state = state.copyWith(books: books);
    } catch (_) {
      if (state.books.isEmpty) {
        final fallback = await _mirrorBooks();
        if (fallback.isNotEmpty) state = state.copyWith(books: fallback);
      }
    }
  }

  Future<void> logout() async {
    await Storage.clearAuth();
    state = SessionState(serverUrl: state.serverUrl, books: const []);
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
