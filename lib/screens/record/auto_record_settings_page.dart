import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/screens/record/auto_record_service.dart';

/// 自动记账设置页：开关、不记账规则勾选、指定用户名单、权限引导
class AutoRecordSettingsPage extends ConsumerStatefulWidget {
  const AutoRecordSettingsPage({super.key});
  @override
  ConsumerState<AutoRecordSettingsPage> createState() =>
      _AutoRecordSettingsPageState();
}

class _AutoRecordSettingsPageState extends ConsumerState<AutoRecordSettingsPage> {
  bool _enabled = false;
  Map<String, bool> _ex = {
    'repay': false,
    'selfTransfer': false,
    'toUsers': false,
    'fromUsers': false,
  };
  List<String> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = AutoRecordService.instance;
    _enabled = await svc.enabled;
    _ex = await svc.excludes;
    _users = await svc.userList;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveEx() async {
    await AutoRecordService.instance.setExcludes(_ex);
  }

  Future<void> _openNotifAccess() async {
    try {
      await MethodChannel('jizhang/auto_record')
          .invokeMethod('openNotifSettings');
    } catch (_) {
      toast('请在系统设置中找到「通知使用权」开启记账本');
    }
  }

  Future<void> _addUser() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加指定用户'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '输入昵称/名称（如：老婆、老板）',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('添加')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (_users.contains(name)) return;
    setState(() => _users.add(name));
    await AutoRecordService.instance.setUserList(_users);
  }

  Future<void> _removeUser(String name) async {
    setState(() => _users.remove(name));
    await AutoRecordService.instance.setUserList(_users);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自动记账')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 总开关
                Card(
                  child: SwitchListTile(
                    title: const Text('自动记账', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('支付成功后识别通知并弹窗确认记账'),
                    value: _enabled,
                    onChanged: (v) async {
                      setState(() => _enabled = v);
                      await AutoRecordService.instance.setEnabled(v);
                      if (v) {
                        toast('已开启；请在系统「通知使用权」中允许记账本');
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // 权限引导
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notification_important, color: AppColors.primaryDark),
                    title: const Text('开启通知使用权'),
                    subtitle: const Text('系统设置 → 通知使用权 → 允许记账本，才能监听支付通知'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openNotifAccess,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('不记账规则', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('命中任一规则 → 不弹窗、不记账', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Card(
                  child: Column(children: [
                    SwitchListTile(
                      title: const Text('信用卡还款'),
                      subtitle: const Text('通知含「还款/信用卡」时忽略'),
                      value: _ex['repay'] ?? false,
                      onChanged: (v) => setState(() {
                        _ex['repay'] = v;
                        _saveEx();
                      }),
                    ),
                    SwitchListTile(
                      title: const Text('本人银行卡转账'),
                      subtitle: const Text('通知含「转账/转入」时忽略'),
                      value: _ex['selfTransfer'] ?? false,
                      onChanged: (v) => setState(() {
                        _ex['selfTransfer'] = v;
                        _saveEx();
                      }),
                    ),
                    SwitchListTile(
                      title: const Text('转给指定用户'),
                      subtitle: const Text('对方在下方名单中（支出）'),
                      value: _ex['toUsers'] ?? false,
                      onChanged: (v) => setState(() {
                        _ex['toUsers'] = v;
                        _saveEx();
                      }),
                    ),
                    SwitchListTile(
                      title: const Text('指定用户转来'),
                      subtitle: const Text('对方在下方名单中（收入）'),
                      value: _ex['fromUsers'] ?? false,
                      onChanged: (v) => setState(() {
                        _ex['fromUsers'] = v;
                        _saveEx();
                      }),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('指定用户名单', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addUser,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加'),
                  ),
                ]),
                Card(
                  child: _users.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('暂无名单。添加后可在弹窗点「不再记」快速加入。',
                              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        )
                      : Column(
                          children: _users.map((u) => ListTile(
                                dense: true,
                                title: Text(u),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => _removeUser(u),
                                ),
                              )).toList(),
                        ),
                ),
                const SizedBox(height: 16),
                const Text('说明：支付成功通知会被识别为记账候选，弹窗确认后经 AI 自动分类并写入流水（来源标记为 AI 记账）。',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
    );
  }
}
