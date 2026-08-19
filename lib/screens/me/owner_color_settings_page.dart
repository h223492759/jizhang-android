import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/owner_color.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/core/local_first_api.dart';

/// 归属人底色设置：在「我的」里为其他归属人设置填充颜色，
/// 首页/图表会把对应流水图标的底色显示为这里设置的颜色（自己始终是灰色）。
class OwnerColorSettingsPage extends ConsumerStatefulWidget {
  const OwnerColorSettingsPage({super.key});
  @override
  ConsumerState<OwnerColorSettingsPage> createState() => _OwnerColorSettingsPageState();
}

class _OwnerColorSettingsPageState extends ConsumerState<OwnerColorSettingsPage> {
  List<String> _owners = [];
  bool _loading = true;
  final _nameCtl = TextEditingController();
  String _picked = '#7c8cff';

  static const _palette = [
    '#7c8cff', '#2BA471', '#F04438', '#F7B500', '#3A7BFF',
    '#E64980', '#12B886', '#F76707', '#7048E8', '#0CA678',
  ];

  @override
  void initState() {
    super.initState();
    _loadOwners();
  }

  Future<void> _loadOwners() async {
    try {
      final fp = await ref.read(localApiProvider).getFlows(pageSize: 1000);
      final set = <String>{};
      for (final f in fp.list) {
        if (f.attribution.isNotEmpty) set.add(f.attribution);
      }
      // 合并已设置的
      final overrides = ref.read(ownerColorsProvider);
      set.addAll(overrides.keys);
      if (mounted) {
        setState(() {
          _owners = set.toList()..sort();
          _loading = false;
        });
      }
    } catch (_) {
      // 拉取失败也能看到已手动添加的
      final overrides = ref.read(ownerColorsProvider);
      if (mounted) {
        setState(() {
          _owners = overrides.keys.toList()..sort();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final overrides = ref.watch(ownerColorsProvider);
    final user = ref.watch(sessionProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('归属人底色')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('自己始终显示为灰色；其他归属人可在此设置填充底色。',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 12),
                ..._owners.map((name) {
                  final isSelf = isSelfAttribution(name, user);
                  final hex = overrides[name];
                  return _ownerRow(name, hex, isSelf);
                }),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text('手动添加归属人', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtl,
                        decoration: const InputDecoration(
                          labelText: '归属人名称',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final n = _nameCtl.text.trim();
                        if (n.isEmpty) return;
                        ref.read(ownerColorsProvider.notifier).setColor(n, _picked);
                        if (!_owners.contains(n)) setState(() => _owners.add(n));
                        _nameCtl.clear();
                      },
                      child: const Text('添加'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _palette
                      .map((c) => GestureDetector(
                            onTap: () => setState(() => _picked = c),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: parseColor(c),
                                shape: BoxShape.circle,
                                border: _picked == c
                                    ? Border.all(color: AppColors.text, width: 2)
                                    : null,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
    );
  }

  Widget _ownerRow(String name, String? hex, bool isSelf) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name.isEmpty ? '(未归属)' : name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              if (isSelf)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                  child: const Text('我自己', style: TextStyle(fontSize: 12)),
                )
              else if (hex != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => ref.read(ownerColorsProvider.notifier).remove(name),
                ),
            ],
          ),
          if (!isSelf)
            const SizedBox(height: 6),
          if (!isSelf)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _palette
                  .map((c) => GestureDetector(
                        onTap: () => ref.read(ownerColorsProvider.notifier).setColor(name, c),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: parseColor(c),
                            shape: BoxShape.circle,
                            border: hex == c
                                ? Border.all(color: AppColors.text, width: 2)
                                : null,
                          ),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}
