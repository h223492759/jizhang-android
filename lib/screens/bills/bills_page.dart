import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api.dart';
import 'core/models.dart';
import 'core/theme.dart';
import 'core/util.dart';
import 'state/session.dart';

class BillsPage extends ConsumerStatefulWidget {
  const BillsPage({super.key});
  @override
  ConsumerState<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends ConsumerState<BillsPage> {
  bool _yearMode = false;
  int _year = DateTime.now().year;
  BillMonthly? _monthly;
  BillYearly? _yearly;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      if (_yearMode) {
        _yearly = await api.getBillYearly();
      } else {
        _monthly = await api.getBillMonthly(year: _year);
      }
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickYear() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_year),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择年份',
    );
    if (picked != null) {
      setState(() => _year = picked.year);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _yearMode ? _yearly?.summary : _monthly?.summary;
    final rows = _yearMode ? _yearly?.rows ?? [] : _monthly?.rows ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('账单')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _seg(['月账单', '年账单'], _yearMode ? 1 : 0, (i) {
                      setState(() => _yearMode = i == 1);
                      _load();
                    }),
                    const Spacer(),
                    if (!_yearMode)
                      TextButton.icon(
                        onPressed: _pickYear,
                        icon: const Icon(Icons.calendar_today),
                        label: Text('$_year年'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (summary != null) _summary(summary),
                const SizedBox(height: 12),
                ...rows.map((r) => _row(r)),
              ],
            ),
    );
  }

  Widget _summary(BillRow s) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _col('收入', s.income, AppColors.income),
            _col('支出', s.expense, AppColors.expense),
            _col('结余', s.balance, AppColors.text),
            _col('笔数', s.count.toDouble(), AppColors.textSecondary),
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

  Widget _row(BillRow r) => Card(
        child: ListTile(
          title: Text(r.label.isEmpty ? '${r.year}年' : r.label),
          subtitle: Text('${r.count} 笔'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('收 ${fmtMoney(r.income)}', style: TextStyle(color: AppColors.income, fontSize: 12)),
              Text('支 ${fmtMoney(r.expense)}', style: TextStyle(color: AppColors.expense, fontSize: 12)),
            ],
          ),
        ),
      );

  Widget _seg(List<String> labels, int sel, void Function(int) onTap) => Container(
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: labels.asMap().entries.map((e) {
            final active = e.key == sel;
            return GestureDetector(
              onTap: () => onTap(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(e.value,
                    style: TextStyle(color: active ? AppColors.text : AppColors.textSecondary)),
              ),
            );
          }).toList(),
        ),
      );
}
