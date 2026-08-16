import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/record/flow_detail_page.dart';

class WalletDetailPage extends ConsumerStatefulWidget {
  final Wallet wallet;
  const WalletDetailPage({super.key, required this.wallet});

  @override
  ConsumerState<WalletDetailPage> createState() => _WalletDetailPageState();
}

class _WalletDetailPageState extends ConsumerState<WalletDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(apiProvider).getWalletTxns(widget.wallet.id);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wallet;
    final txns = (_data?['txns'] as List? ?? []).map((x) => _Txn.fromJson(x)).toList();
    final flows = (_data?['flows'] as List? ?? []).map((x) => Flow.fromJson(x)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(w.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      Text('¥${fmtMoney(w.balance)}',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      if (w.target > 0)
                        Text('目标 ¥${fmtMoney(w.target)}', style: const TextStyle(color: AppColors.textSecondary)),
                      if (w.linkCategory.isNotEmpty)
                        Text('关联分类「${w.linkCategory}」自 ${w.linkFrom}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (txns.isNotEmpty) ...[
                  const Text('资金记录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...txns.map((t) => Card(
                        child: ListTile(
                          title: Text(t.ymd),
                          trailing: Text('¥${fmtMoney(t.amount)}',
                              style: TextStyle(
                                  color: t.amount >= 0 ? AppColors.income : AppColors.expense,
                                  fontWeight: FontWeight.bold)),
                          subtitle: t.note.isNotEmpty ? Text(t.note) : null,
                        ),
                      )),
                ],
                if (flows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('关联流水', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...flows.map((f) {
                    final expense = f.isExpense;
                    return Card(
                      child: ListTile(
                        title: Text(f.category),
                        subtitle: Text('${datePart(f.flowTime)} ${f.description}'),
                        trailing: Text('${expense ? '-' : '+'}${fmtMoney(f.amount)}',
                            style: TextStyle(
                                color: expense ? AppColors.expense : AppColors.income,
                                fontWeight: FontWeight.bold)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FlowDetailPage(flow: f)),
                        ),
                      ),
                    );
                  }),
                ],
                if (txns.isEmpty && flows.isEmpty)
                  const Text('暂无记录', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
    );
  }
}

class _Txn {
  final String ymd;
  final double amount;
  final String note;
  _Txn({required this.ymd, required this.amount, required this.note});
  factory _Txn.fromJson(Map<String, dynamic> j) => _Txn(
        ymd: j['ymd'] ?? '',
        amount: (j['amount'] ?? 0).toDouble(),
        note: j['note'] ?? '',
      );
}
