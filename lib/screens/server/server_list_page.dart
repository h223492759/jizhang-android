import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'core/util.dart';
import 'state/session.dart';

class ServerListPage extends ConsumerStatefulWidget {
  const ServerListPage({super.key});
  @override
  ConsumerState<ServerListPage> createState() => _ServerListPageState();
}

class _ServerListPageState extends ConsumerState<ServerListPage> {
  List<String> _servers = [];
  String? _active;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await Storage.getServers();
    final active = await Storage.getServerUrl();
    setState(() {
      _servers = list;
      _active = active;
    });
  }

  Future<void> _saveList() async {
    await Storage.setServers(_servers);
  }

  void _showEdit({String? initial, int? index}) {
    final ctrl = TextEditingController(text: initial ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? '添加服务器' : '编辑服务器'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'http://192.168.50.50:9600',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final v = ctrl.text.trim();
              if (v.isEmpty) {
                toast('地址不能为空');
                return;
              }
              setState(() {
                if (index == null) {
                  if (!_servers.contains(v)) _servers.add(v);
                } else {
                  _servers[index] = v;
                }
              });
              await _saveList();
              if (index == null && _active == null) {
                await ref.read(sessionProvider.notifier).selectServer(v);
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(int index) async {
    final removed = _servers[index];
    setState(() => _servers.removeAt(index));
    await _saveList();
    if (removed == _active) {
      await ref.read(sessionProvider.notifier).selectServer(_servers.first);
    }
  }

  Future<void> _select(String url) async {
    await ref.read(sessionProvider.notifier).selectServer(url);
    if (mounted) toast('已切换到 $url，请登录');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('选择记账服务器（连接同一后端）',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          // 离线模式（暂未开放）
          ListTile(
            leading: const Icon(Icons.cloud_off, color: AppColors.textSecondary),
            title: const Text('离线记账模式'),
            subtitle: const Text('无需连接服务器，本地记账（暂未开放）'),
            trailing: Switch(value: false, onChanged: (_) => toast('离线模式暂未开放')),
          ),
          const Divider(),
          ..._servers.asMap().entries.map((e) {
            final url = e.value;
            final active = url == _active;
            return ListTile(
              leading: Radio<String>(
                value: url,
                groupValue: _active,
                activeColor: AppColors.primaryDark,
                onChanged: (_) => _select(url),
              ),
              title: Text(url),
              subtitle: active ? const Text('当前已选', style: TextStyle(color: AppColors.income)) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _showEdit(initial: url, index: e.key)),
                  IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                      onPressed: () => _delete(e.key)),
                ],
              ),
              onTap: () => _select(url),
            );
          }),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
