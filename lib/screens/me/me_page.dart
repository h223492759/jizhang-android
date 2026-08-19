import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/core/build_info.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/me/owner_color_settings_page.dart';
import 'package:jizhang_android/screens/record/auto_record_settings_page.dart';
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
          // 头像卡：头像 + 昵称 + 右侧「退出」按钮
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                // 退出按钮移到头像右侧，名称「退出」防误触
                TextButton(
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
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('退出'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          _tile(Icons.palette, '归属人底色', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerColorSettingsPage()))),
          // 当前账本：点击切换
          _tile(Icons.book, '当前账本', () => _switchBook(context, ref, s), subtitle: book?.name ?? '未选择'),
          _tile(Icons.auto_awesome, '自动记账', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AutoRecordSettingsPage()))),
          _tile(Icons.swap_horiz, '切换服务器', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServerListPage()))),
          const SizedBox(height: 12),
          // 版本信息 + 设置信息合并展示
          _versionCard(context, ref, s),
        ],
      ),
    );
  }

  // 切换账本
  Future<void> _switchBook(BuildContext context, WidgetRef ref, SessionState s) async {
    if (s.books.isEmpty) {
      toast('暂无可切换的账本');
      return;
    }
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('切换账本'),
        children: [
          ...s.books.map((b) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, b.id),
                child: Row(children: [
                  Icon(Icons.book,
                      size: 18,
                      color: b.id == s.bookId ? AppColors.primaryDark : AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(b.name,
                        style: TextStyle(
                            fontWeight: b.id == s.bookId ? FontWeight.bold : FontWeight.normal,
                            color: b.id == s.bookId ? AppColors.text : AppColors.textSecondary)),
                  ),
                  if (b.id == s.bookId) const Text('当前', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ]),
              )),
        ],
      ),
    );
    if (picked != null && picked != s.bookId) {
      await ref.read(sessionProvider.notifier).selectBook(picked);
      toast('已切换到当前账本');
    }
  }

  // 版本信息 + 服务器 + 账号 + AI（设置页信息合并到此）
  Widget _versionCard(BuildContext context, WidgetRef ref, SessionState s) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (ctx, snap) {
        final version = snap.data?.version ?? BuildInfo.version;
        final build = snap.data?.buildNumber ?? BuildInfo.buildNumber;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.primaryDark),
                SizedBox(width: 8),
                Text('版本信息', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
              const SizedBox(height: 10),
              _infoRow('版本', 'v$version ($build) · 构建 ${BuildInfo.buildTime}'),
              _infoRow('服务器', s.serverUrl ?? '-'),
              _infoRow('当前账号', s.user?.nickname ?? s.user?.username ?? '-'),
              _aiRow(ref),
              const Divider(height: 20),
              const Text('本 App 为「记账本」安卓客户端，UI 参考鲨鱼记账的交互设计，'
                  '后端对接 jizhang 服务。数据均存储在你自己的服务器上。',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              const Center(
                child: Text('© 记账本', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );

  Widget _aiRow(WidgetRef ref) {
    return FutureBuilder<AiStatus>(
      future: _aiStatus(ref),
      builder: (ctx, snap) {
        final ai = snap.data;
        final text = ai == null
            ? '未知'
            : ai.enabled
                ? '已开启（${ai.model ?? ai.provider ?? ''}）'
                : '未配置';
        return _infoRow('AI 记账', text);
      },
    );
  }

  Future<AiStatus> _aiStatus(WidgetRef ref) async {
    try {
      return await ref.read(apiProvider).getAiStatus();
    } catch (_) {
      return AiStatus(enabled: false);
    }
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
