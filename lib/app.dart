import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/screens/server/server_list_page.dart';
import 'package:jizhang_android/screens/auth/login_page.dart';
import 'package:jizhang_android/screens/book/book_picker_page.dart';
import 'package:jizhang_android/screens/home/home_page.dart';
import 'package:jizhang_android/screens/charts/charts_page.dart';
import 'package:jizhang_android/screens/discover/discover_page.dart';
import 'package:jizhang_android/screens/me/me_page.dart';
import 'package:jizhang_android/screens/record/record_page.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '记账本',
      theme: AppTheme.light,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootRouter(),
    );
  }
}

class RootRouter extends ConsumerWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    if (!s.hasServer) return const ServerListPage();
    if (!s.hasToken) return const LoginPage();
    if (!s.hasBook) return const BookPickerPage();
    return const MainShell();
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _idx = 0;
  final _pages = const [HomePage(), ChartsPage(), DiscoverPage(), MePage()];

  void _openRecord() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecordPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 明确不延伸主体到底栏后面：避免 body 内容偶尔穿透 BottomAppBar 的 notch
      // 导致 FAB 看起来跑到屏幕中间并被 body 文字覆盖的问题。
      extendBody: false,
      body: _pages[_idx],
      floatingActionButton: FloatingActionButton(
        onPressed: _openRecord,
        tooltip: '记一笔',
        shape: const CircleBorder(),
        elevation: 4,
        child: const Icon(Icons.add, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButtonAnimator: FloatingActionButtonAnimator.noAnimation,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.receipt_long, '明细'),
              _navItem(1, Icons.pie_chart, '图表'),
              const SizedBox(width: 56),
              _navItem(2, Icons.auto_awesome, '发现'),
              _navItem(3, Icons.person_outline, '我的'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    final active = _idx == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _idx = i),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: active ? AppColors.primaryDark : AppColors.textSecondary),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: active ? AppColors.primaryDark : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
