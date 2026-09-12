import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/core/build_info.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/me/owner_color_settings_page.dart';
import 'package:jizhang_android/screens/record/auto_record_settings_page.dart';
import 'package:jizhang_android/screens/utility/utility_page.dart';
import 'package:jizhang_android/screens/server/server_list_page.dart';
import 'package:jizhang_android/screens/me/op_logs_page.dart';
import 'package:jizhang_android/screens/me/trash_page.dart';
import 'package:jizhang_android/core/local_first_api.dart';
import 'package:jizhang_android/core/sync_engine.dart';
import 'package:jizhang_android/core/storage.dart';

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
                        style: TextStyle(color: AppPalette.card(context), fontSize: 24));
                  }),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.nickname ?? user?.username ?? '未登录',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('@${user?.username ?? ''}', style: TextStyle(color: AppPalette.textSecondary(context))),
                      const SizedBox(height: 6),
                      // v2.2.17：昵称下方两行统计（第一行首次记账时间 / 第二行流水总笔数）
                      FutureBuilder<({String? firstTime, int total})>(
                        future: ref.read(localApiProvider).getFlowSummary(),
                        builder: (ctx, snap) {
                          final first = snap.data?.firstTime;
                          final total = snap.data?.total;
                          final st = TextStyle(
                              fontSize: 12, color: AppPalette.textSecondary(ctx));
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('首次记账：${first ?? '—'}', style: st),
                              Text('流水总笔数：${total == null ? '—' : '$total 笔'}', style: st),
                            ],
                          );
                        },
                      ),
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
          // v2.2.17：常用功能改为「一行 4 个图标 + 文字」×2 行（原竖排 9 个 ListTile 太长）
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(
                      child: _gridItem(context, Icons.palette, '归属人底色',
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerColorSettingsPage()))),
                    ),
                    Expanded(
                      child: _gridItem(context, Icons.book, '当前账本',
                          () => _switchBook(context, ref, s), subtitle: book?.name),
                    ),
                    Expanded(
                      child: _gridItem(context, Icons.auto_awesome, '自动记账',
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AutoRecordSettingsPage()))),
                    ),
                    Expanded(
                      child: _gridItem(context, Icons.water_drop, '水电气',
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UtilityPage()))),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _gridItem(context, Icons.restore_from_trash, '回收站',
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashPage()))),
                    ),
                    // 同步：状态文字放图标下方，点击立即同步
                    Expanded(
                      child: AnimatedBuilder(
                        animation: SyncEngine.instance,
                        builder: (context, _) =>
                            _gridItem(context, Icons.sync, '同步', () => _syncNow(context, ref)),
                      ),
                    ),
                    Expanded(
                      child: _gridItem(context, Icons.history, '操作日志',
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OpLogsPage()))),
                    ),
                    Expanded(
                      child: _gridItem(context, Icons.swap_horiz, '切换服务器',
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServerListPage()))),
                    ),
                  ]),
                  // 同步状态一行（保留「上次同步 xx」信息，原 ListTile 副标题）
                  AnimatedBuilder(
                    animation: SyncEngine.instance,
                    builder: (context, _) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        _syncStatusText(context),
                        style: TextStyle(fontSize: 11, color: AppPalette.textSecondary(context)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 版本信息 + 设置信息合并展示
          _versionCard(context, ref, s),
        ],
      ),
    );
  }

  // 手动触发一次同步（成功后刷新 watch 数据版本的页面）
  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final bookId = await Storage.getBookId();
    if (bookId == null) {
      toast('尚未选择账本');
      return;
    }
    final ok = await SyncEngine.instance.syncNow(bookId);
    if (ok) {
      ref.read(dataVersionProvider.notifier).state++;
      toast('同步完成');
    } else {
      toast('离线或同步失败，本地数据仍可正常使用');
    }
  }

  // 切换账本
  Future<void> _switchBook(BuildContext context, WidgetRef ref, SessionState s) async {    if (s.books.isEmpty) {
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
                      color: b.id == s.bookId ? AppColors.primaryDark : AppPalette.textSecondary(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(b.name,
                        style: TextStyle(
                            fontWeight: b.id == s.bookId ? FontWeight.bold : FontWeight.normal,
                            color: b.id == s.bookId ? AppPalette.text(context) : AppPalette.textSecondary(context))),
                  ),
                  if (b.id == s.bookId) Text('当前', style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
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

  // 开源地址：复制到剪贴板（避免额外引入 url_launcher 依赖）
  Future<void> _copyRepo(BuildContext context) async {
    const url = 'https://github.com/h223492759/jizhang-android';
    await Clipboard.setData(const ClipboardData(text: url));
    if (context.mounted) toast('已复制开源地址：$url');
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
          decoration: BoxDecoration(color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
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
              // v2.2.17：开源地址从独立列表项移入版本信息（AI 记账下面一行，右侧蓝色下划线，点击复制）
              _linkRow(context, '开源地址', 'github.com/h223492759/jizhang-android',
                  () => _copyRepo(context)),
              const Divider(height: 20),
              Text('本 App 为「记账本」安卓客户端，UI 参考鲨鱼记账的交互设计，'
                  '后端对接 jizhang 服务。数据均存储在你自己的服务器上。',
                  style: TextStyle(color: AppPalette.textSecondary(context), fontSize: 13)),
              const SizedBox(height: 8),
              Center(
                child: Text('© 记账本', style: TextStyle(color: AppPalette.textSecondary(context), fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) => Builder(
        builder: (ctx) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 80,
              child: Text(label, style: TextStyle(color: AppPalette.textSecondary(ctx), fontSize: 13)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          ]),
        ),
      );

  // v2.2.17：带链接样式的信息行（右对齐、蓝色、下划线、点击可复制）
  Widget _linkRow(BuildContext context, String label, String value, VoidCallback onTap) =>
      Builder(
        builder: (ctx) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: TextStyle(color: AppPalette.textSecondary(ctx), fontSize: 13)),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _aiRow(WidgetRef ref) {    return FutureBuilder<AiStatus>(
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
      return await ref.read(localApiProvider).getAiStatus();
    } catch (_) {
      return AiStatus(enabled: false);
    }
  }

  // v2.2.17：同步状态文案（原 ListTile 副标题，现作为网格下方一行小字）
  String _syncStatusText(BuildContext context) {
    final se = SyncEngine.instance;
    if (se.status == SyncStatus.syncing) return '同步中…';
    if (se.status == SyncStatus.offline) return '离线 · 本地数据可用（点「同步」重试）';
    final t = se.lastSyncAt;
    if (t == null) return '点「同步」立即同步';
    return '上次同步 ${t.month}月${t.day}日 '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // 网格单元：图标 + 文字（可选第二行小字）
  Widget _gridItem(BuildContext context, IconData icon, String label, VoidCallback? onTap,
          {String? subtitle}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.primaryDark, size: 24),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (subtitle != null && subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle,
                      style: TextStyle(fontSize: 10, color: AppPalette.textSecondary(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      );
}
