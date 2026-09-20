import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/storage.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';

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
    // v2.2.25：删除服务器后会再调一次 _load()，中间隔了 await（可能已 pop 出页面）
    // → 不加 mounted 守卫会触发 setState() called after dispose
    if (!mounted) return;
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
              final int? editing = index;
              // 改的是不是「正在使用」那台？必须在 setState 之前判断
              var wasActive = false;
              if (editing != null) {
                wasActive = !ref
                    .read(sessionProvider.notifier)
                    .isDifferentServer(_servers[editing]);
              }
              setState(() {
                if (editing == null) {
                  if (!_servers.contains(v)) _servers.add(v);
                } else {
                  _servers[editing] = v;
                }
                if (wasActive) _active = v;
              });
              await _saveList();
              if (editing == null && _active == null) {
                await ref.read(sessionProvider.notifier).selectServer(v);
              } else if (wasActive) {
                // v2.2.25：给「正在使用」那台改地址（例如后端换了 IP/端口）→ 只换地址、
                // **保留登录态**。以前这里不改 _active，列表上看不出哪台在用，
                // 用户再点一下那行就会走「切换」把 token 清掉 → 莫名登出。
                await ref.read(sessionProvider.notifier).updateServerAddress(v);
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
    // 用地址归一化后的比较判断「是不是正在用的那台」（尾部斜杠等写法差异不能算两台）
    final isActive = !ref.read(sessionProvider.notifier).isDifferentServer(removed);
    // v2.2.25：删掉「正在使用」的那台会连带清掉登录态（token 与服务器绑定），
    // 必须让用户明确知道后果，不能静默登出
    if (isActive) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除服务器'),
          content: Text('「$removed」正在使用中，删除后需要重新选择服务器并登录，确定删除？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }
    setState(() => _servers.removeAt(index));
    await _saveList();
    if (isActive) {
      if (_servers.isEmpty) {
        await ref.read(sessionProvider.notifier).clearServer();
      } else {
        await ref.read(sessionProvider.notifier).selectServer(_servers.first);
      }
      await _load();
    }
  }

  Future<void> _select(String url) async {
    final notifier = ref.read(sessionProvider.notifier);
    // v2.2.25：同一台服务器不再「切换」
    // （以前点一下当前正在用的那台也会清登录态 → 立刻登出，就是用户报的「账户会登出」；
    //   「我的」页第二行宫格就有「切换服务器」入口，点进去顺手点一下当前那行就中招）
    if (!notifier.isDifferentServer(url)) {
      toast('当前已在使用该服务器');
      return;
    }
    // 换到另一台 = 必须重新登录（token 与服务器绑定）。已登录时先说清楚，避免「莫名被登出」。
    if (ref.read(sessionProvider).hasToken) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('切换服务器'),
          content: Text('切换到「$url」后，当前账号需要重新登录，确定切换？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('切换')),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }
    final changed = await notifier.selectServer(url);
    if (!mounted) return;
    if (!changed) {
      toast('当前已在使用该服务器');
      return;
    }
    await _load();
    if (mounted) toast('已切换到 $url，请登录');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器')),
      body: ListView(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text('选择记账服务器（连接同一后端）',
                style: TextStyle(color: AppPalette.textSecondary(context))),
          ),
          // 离线模式（暂未开放）
          ListTile(
            leading: Icon(Icons.cloud_off, color: AppPalette.textSecondary(context)),
            title: const Text('离线记账模式'),
            subtitle: const Text('无需连接服务器，本地记账（暂未开放）'),
            trailing: Switch(value: false, onChanged: (_) => toast('离线模式暂未开放')),
          ),
          const Divider(),
          ..._servers.asMap().entries.map((e) {
            final url = e.value;
            // v2.2.25：用**地址归一化**后的比较判断「是不是当前正在使用的那台」。
            // 以前是裸字符串比较 `url == _active`，写法差异（尾部斜杠等）会让当前那台
            // 看起来不像「当前」，点它就走「切换」把 token 清掉 → 莫名登出。
            final active =
                !ref.read(sessionProvider.notifier).isDifferentServer(url);
            return ListTile(
              leading: Radio<String>(
                value: url,
                // 只有一个 active，直接用 url 当选中值，避免写法差异导致 radio 无选中项
                groupValue: active ? url : null,
                activeColor: AppColors.primaryDark,
                // v2.2.25：**当前正在使用的那台不可再点**（点它以前会清登录态 → 立刻登出）。
                // 这是 UI 层纵深防御：即便将来 selectServer 的守卫被改坏，也误触不到。
                onChanged: active ? null : (_) => _select(url),
              ),
              title: Text(url),
              subtitle: active ? const Text('使用中', style: TextStyle(color: AppColors.income)) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _showEdit(initial: url, index: e.key)),
                  IconButton(
                      icon: Icon(Icons.delete, size: 20, color: Colors.red),
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
