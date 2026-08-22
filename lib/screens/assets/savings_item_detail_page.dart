import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/core/local_first_api.dart';

class SavingsItemDetailPage extends ConsumerStatefulWidget {
  final SavingsItem item;
  const SavingsItemDetailPage({super.key, required this.item});

  @override
  ConsumerState<SavingsItemDetailPage> createState() => _SavingsItemDetailPageState();
}

class _SavingsItemDetailPageState extends ConsumerState<SavingsItemDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(localApiProvider).getSavingsItemHistory(widget.item.id);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final histories = (_data?['history'] as List? ?? [])
        .map((x) => _History.fromJson(x))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Text('¥${fmtMoney(item.amount)}',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(item.isLiability ? '负债' : '资产',
                          style: TextStyle(color: item.isLiability ? AppColors.expense : AppColors.income)),
                      if (item.note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(item.note, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('历史记录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (histories.isEmpty)
                  const Text('无历史记录', style: TextStyle(color: AppColors.textSecondary))
                else
                  ...histories.map((h) => Card(
                        child: ListTile(
                          title: Text(h.ymd),
                          trailing: Text('¥${fmtMoney(h.amount)}',
                              style: TextStyle(
                                  color: h.amount >= 0 ? AppColors.income : AppColors.expense,
                                  fontWeight: FontWeight.bold)),
                          subtitle: h.note.isNotEmpty ? Text(h.note) : null,
                        ),
                      )),
              ],
            ),
    );
  }
}

class _History {
  final String ymd;
  final double amount;
  final String note;
  _History({required this.ymd, required this.amount, required this.note});
  factory _History.fromJson(Map<String, dynamic> j) => _History(
        ymd: j['ymd'] ?? '',
        amount: (j['amount'] ?? 0).toDouble(),
        note: j['note'] ?? '',
      );
}
