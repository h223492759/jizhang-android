import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/local_first_api.dart';
import 'package:jizhang_android/core/storage.dart';
import 'package:jizhang_android/core/sync_engine.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';

/// 回收站：已删除的流水快照（谁删的 + 删除时间）。
/// 数据在服务端（flows_trash），按账本隔离 → 共享账本全员可见/可恢复；
/// 恢复后服务端增量同步会把流水重新推给所有成员（本端需同步一次才会在列表出现）。
class TrashPage extends ConsumerStatefulWidget {
  const TrashPage({super.key});
  @override
  ConsumerState<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends ConsumerState<TrashPage> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final api = ref.read(localApiProvider);
      final l = await api.fetchTrashFlows();
      if (mounted) {
        setState(() {
          _list = l;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(e.toString().replaceFirst('ApiException: ', ''));
      }
    }
  }

  Future<void> _restore(Map<String, dynamic> it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复这笔流水？'),
        content: Text(
            '「${it['description'] ?? it['category']}」¥${_money(it['amount'])}\n恢复后将重新出现在流水列表（共享账本全员同步可见）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复', style: TextStyle(color: AppColors.income)),
          ),
        ],
      ),
    );
    if (ok != true || _busy) return;
    _busy = true;
    try {
      final api = ref.read(localApiProvider);
      await api.restoreTrashFlow((it['id'] as num).toInt());
      // 同步一次：让恢复的流水重新出现在本端列表
      final bookId = await Storage.getBookId();
      if (bookId != null) {
        await SyncEngine.instance.syncNow(bookId).catchError((_) {});
      }
      ref.read(dataVersionProvider.notifier).state++;
      toast('已恢复');
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      _busy = false;
      await _load();
    }
  }

  Future<void> _purge(Map<String, dynamic> it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除？'),
        content: Text(
            '「${it['description'] ?? it['category']}」¥${_money(it['amount'])}\n此操作不可恢复！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (ok != true || _busy) return;
    _busy = true;
    try {
      await ref.read(localApiProvider).purgeTrashFlow((it['id'] as num).toInt());
      toast('已彻底删除');
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      _busy = false;
      await _load();
    }
  }

  String _money(Object? v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    return n.toStringAsFixed(2);
  }

  String _ts(String s, {bool withDate = true}) {
    final t = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (t == null) return s;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return withDate ? '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} $hh:$mm' : '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text(
                    '删除的流水保留在此。共享账本中全员可见，恢复后所有成员同步可见。',
                    style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
                  ),
                ),
                Expanded(
                  child: _list.isEmpty
                      ? Center(
                          child: Text('回收站是空的',
                              style: TextStyle(color: AppPalette.textSecondary(context))))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                            itemCount: _list.length,
                            itemBuilder: (_, i) {
                              final it = _list[i];
                              final expense = it['type'] == 'expense';
                              final color = expense ? AppColors.expense : AppColors.income;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Text(
                                                '${it['category'] ?? ''}'
                                                ' · ${it['description'] ?? it['category'] ?? ''}',
                                                style: const TextStyle(
                                                    fontSize: 15, fontWeight: FontWeight.w600),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ]),
                                            const SizedBox(height: 3),
                                            Text(
                                              '${_ts('${it['flow_time'] ?? ''}')} · '
                                              '删除人：${it['deleted_by'] ?? '—'} · '
                                              '${_ts('${it['deleted_at'] ?? ''}')}',
                                              style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: AppPalette.textSecondary(context)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text('¥${_money(it['amount'])}',
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: color)),
                                      IconButton(
                                        tooltip: '恢复',
                                        icon: const Icon(Icons.restore,
                                            size: 22, color: AppColors.income),
                                        onPressed: _busy ? null : () => _restore(it),
                                      ),
                                      IconButton(
                                        tooltip: '彻底删除',
                                        icon: const Icon(Icons.delete_forever,
                                            size: 22, color: AppColors.expense),
                                        onPressed: _busy ? null : () => _purge(it),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
