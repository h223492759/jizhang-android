import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
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
    state = state.copyWith(
      serverUrl: server,
      token: token,
      user: userJson != null ? User.fromJsonString(userJson) : null,
      bookId: bookId,
    );
    if (state.hasToken) {
      try {
        final books = await state.api.getBooks();
        final raw = await Storage.getBooksJson();
        state = state.copyWith(books: books);
        if (raw != null) {
          // 保留持久化的账本列表排序
        }
      } catch (_) {
        // 启动时不因网络失败而退出登录
      }
    }
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

  Future<void> refreshBooks() async {
    if (!state.hasToken) return;
    final books = await state.api.getBooks();
    state = state.copyWith(books: books);
  }

  Future<void> logout() async {
    await Storage.clearAuth();
    state = SessionState(serverUrl: state.serverUrl, books: const []);
  }

  String _booksToJson(List<Book> books) =>
      '[' + books.map((b) => b.toJsonString()).join(',') + ']';
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState>(
  (ref) => SessionNotifier(),
);

final apiProvider = Provider<ApiClient>((ref) => ref.watch(sessionProvider).api);

/// 数据版本计数器：记一笔 / 改删流水后自增，让首页等页面自动刷新。
final dataVersionProvider = StateProvider<int>((ref) => 0);
