import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/core/build_info.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/me/settings_page.dart';
import 'package:jizhang_android/screens/server/server_list_page.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final user = s.user;
    Book? book;
    for (final b in s.books) {
      if (b.id == s.bookId) {
        book = b;
        break;
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primaryDark,
                  child: Builder(builder: (context) {
                    final display = user?.nickname.isNotEmpty == true
                        ? user!.nickname
                        : (user?.username ?? '?');
                    final initial = display.isNotEmpty ? display[0] : '?';
                    return Text(initial,
                        style: const TextStyle(color: Colors.white, fontSize: 24));
                  }),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.nickname ?? user?.username ?? '未登录',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('@${user?.username ?? ''}', style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          _tile(Icons.settings, '设置', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
          _tile(Icons.book, '当前账本', null, subtitle: book?.name ?? '未选择'),
          _tile(Icons.link, '服务器', null, subtitle: s.serverUrl ?? ''),
          _tile(Icons.swap_horiz, '切换服务器', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServerListPage()))),
          const SizedBox(height: 12),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (ctx, snap) {
              final version = snap.data?.version ?? BuildInfo.version;
              final build = snap.data?.buildNumber ?? BuildInfo.buildNumber;
              return _tile(
                Icons.info_outline,
                '版本信息',
                null,
                subtitle: 'v$version ($build) · 构建 ${BuildInfo.buildTime}',
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('退出登录'),
                    content: const Text('确定退出当前账号？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(sessionProvider.notifier).logout();
                  if (context.mounted) toast('已退出登录');
                }
              },
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('退出登录'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String title, VoidCallback? onTap, {String? subtitle}) => Card(
        child: ListTile(
          leading: Icon(icon, color: AppColors.primaryDark),
          title: Text(title),
          subtitle: subtitle != null ? Text(subtitle) : null,
          trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
          onTap: onTap,
        ),
      );
}
