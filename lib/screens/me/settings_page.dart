import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _version = '';
  bool _aiEnabled = false;
  String? _aiModel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiProvider);
      final meta = await api.getMeta();
      AiStatus ai;
      try {
        ai = await api.getAiStatus();
      } catch (_) {
        ai = AiStatus(enabled: false);
      }
      if (mounted) {
        setState(() {
          _version = meta.version;
          _aiEnabled = ai.enabled;
          _aiModel = ai.model;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 12),
          const Center(child: Icon(Icons.account_balance_wallet, size: 56, color: AppColors.primaryDark)),
          const SizedBox(height: 8),
          const Center(child: Text('记账本', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          if (_version.isNotEmpty)
            Center(child: Text('版本 $_version', style: const TextStyle(color: AppColors.textSecondary))),
          const SizedBox(height: 20),
          _row('服务器', s.serverUrl ?? ''),
          _row('当前账号', s.user?.nickname ?? s.user?.username ?? ''),
          _row('AI 记账', _aiEnabled ? '已开启（${_aiModel ?? ''}）' : '未配置'),
          const SizedBox(height: 16),
          const Text('说明', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('本 App 为「记账本」安卓客户端，UI 参考鲨鱼记账的交互设计，'
              '后端对接 jizhang 服务。数据均存储在你自己的服务器上。',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          const Center(
            child: Text('© 记账本', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
          Expanded(child: Text(value.isEmpty ? '-' : value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ]),
      );
}
