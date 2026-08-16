import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/record/flow_detail_page.dart';

class BillMonthDetailPage extends ConsumerStatefulWidget {
  final String ym;
  const BillMonthDetailPage({super.key, required this.ym});

  @override
  ConsumerState<BillMonthDetailPage> createState() => _BillMonthDetailPageState();
}

class _BillMonthDetailPageState extends ConsumerState<BillMonthDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(apiProvider).getBillMonthDetail(widget.ym);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final thisMonth = d?['thisMonth'] as Map? ?? {};
    return Scaffold(
      appBar: AppBar(title: Text('${widget.ym} 账单详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summary(thisMonth),
                const SizedBox(height: 16),
                _sectionTitle('支出分类'),
                const SizedBox(height: 8),
                ..._expenseCats(d?['expenseByCategory'] as List? ?? []),
                const SizedBox(height: 16),
                _sectionTitle('最高支出'),
                const SizedBox(height: 8),
                ..._topFlows(d?['topExpenses'] as List? ?? [], isExpense: true),
                const SizedBox(height: 16),
                _sectionTitle('最高收入'),
                const SizedBox(height: 8),
                ..._topFlows(d?['topIncomes'] as List? ?? [], isExpense: false),
              ],
            ),
    );
  }

  Widget _summary(Map m) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _col('收入', (m['income'] ?? 0).toDouble(), AppColors.income),
            _col('支出', (m['expense'] ?? 0).toDouble(), AppColors.expense),
            _col('结余', (m['balance'] ?? 0).toDouble(), AppColors.text),
          ],
        ),
      );

  Widget _col(String l, double v, Color c) => Expanded(
        child: Column(children: [
          Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(fmtMoney(v), style: TextStyle(color: c, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold));

  List<Widget> _expenseCats(List list) {
    if (list.isEmpty) return [const Text('无支出记录', style: TextStyle(color: AppColors.textSecondary))];
    return list.map((x) {
      final cat = x['category'] ?? '';
      final amt = (x['amount'] ?? 0).toDouble();
      final pct = (x['percent'] ?? 0).toDouble();
      return Card(
        child: ListTile(
          title: Text(cat),
          trailing: Text('${fmtMoney(amt)} · ${pct.toStringAsFixed(pct == pct.toInt() ? 0 : 1)}%'),
        ),
      );
    }).toList();
  }

  List<Widget> _topFlows(List list, {required bool isExpense}) {
    if (list.isEmpty) return [const Text('无记录', style: TextStyle(color: AppColors.textSecondary))];
    return list.map((x) {
      final f = Flow.fromJson(x as Map<String, dynamic>);
      return Card(
        child: ListTile(
          title: Text('${f.category} ${f.description.isNotEmpty ? '· ${f.description}' : ''}'),
          subtitle: Text(f.flowTime),
          trailing: Text('${isExpense ? '-' : '+'}${fmtMoney(f.amount)}',
              style: TextStyle(
                  color: isExpense ? AppColors.expense : AppColors.income,
                  fontWeight: FontWeight.bold)),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FlowDetailPage(flow: f)),
          ),
        ),
      );
    }).toList();
  }
}
