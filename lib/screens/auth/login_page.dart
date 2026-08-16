import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/server/server_list_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _user.text.trim();
    final password = _pass.text;
    if (username.isEmpty || password.isEmpty) {
      toast('请输入账号和密码');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(sessionProvider.notifier).login(username, password);
      toast('登录成功');
      // RootRouter 会自动按状态跳转到账本选择页
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(sessionProvider).serverUrl ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.account_balance_wallet, size: 64, color: AppColors.primaryDark),
            const SizedBox(height: 8),
            const Center(child: Text('记账本', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primarySoft, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.link, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(server, style: const TextStyle(fontSize: 13))),
                TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ServerListPage())),
                  child: const Text('切换'),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _user,
              decoration: const InputDecoration(labelText: '账号', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.text,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('登录', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
