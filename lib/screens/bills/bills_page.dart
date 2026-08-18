import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/bills/bill_month_detail_page.dart';

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
    // 只选年份：自建年份网格，避免 showDatePicker 落到具体日期
    final now = DateTime.now();
    final years = <int>[for (var y = now.year; y >= 2000; y--) y];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('选择年份',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8),
                  itemCount: years.length,
                  itemBuilder: (_, i) {
                    final y = years[i];
                    final active = y == _year;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.pop(ctx, y),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: active ? AppColors.primary : AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$y',
                            style: TextStyle(
                                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                color: active ? AppColors.text : AppColors.textSecondary)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != _year) {
      setState(() => _year = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _yearMode ? _yearly?.summary : _monthly?.summary;
    final sourceRows = _yearMode ? _yearly?.rows ?? [] : _monthly?.rows ?? [];
    // 月账单：月份由高到低显示，未到的月份不显示
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final rows = _yearMode
        ? sourceRows
        : sourceRows.where((r) {
            if (r.year == now.year && r.month.compareTo(curYm) > 0) return false;
            return true;
          }).toList()
      ..sort((a, b) => b.month.compareTo(a.month));
    final head = _yearMode
        ? ['年份', '年收入', '年支出', '年结余']
        : ['月份', '月收入', '月支出', '月结余'];
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
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text('$_year'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (summary != null) _summary(summary),
                const SizedBox(height: 12),
                // 表头
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 56,
                          child: Text(head[0], style: _headStyle())),
                      Expanded(
                          child: Text(head[1],
                              style: _headStyle(), textAlign: TextAlign.right)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(head[2],
                              style: _headStyle(), textAlign: TextAlign.right)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(head[3],
                              style: _headStyle(), textAlign: TextAlign.right)),
                      const SizedBox(width: 22),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                ...rows.map((r) => _row(r)),
              ],
            ),
    );
  }

  TextStyle _headStyle() => const TextStyle(
      fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold);

  Widget _summary(BillRow s) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _col('收入', s.income, AppColors.income),
            _col('支出', s.expense, AppColors.expense),
            _col('结余', s.balance, AppColors.text),
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

  // 月份/年份只显示数字：后端 label 是 "8月"/"2026年"，剥掉后缀
  String _trimLabel(BillRow r) {
    final s = r.label.isEmpty ? '${r.year}' : r.label;
    return s.replaceAll('月', '').replaceAll('年', '');
  }

  Widget _row(BillRow r) => Card(
        child: InkWell(
          onTap: () {
            if (_yearMode) {
              if (r.year > 0) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => BillMonthDetailPage(isYear: true, year: r.year)),
                );
              }
            } else if (r.month.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => BillMonthDetailPage(ym: r.month)),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    _trimLabel(r),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(fmtMoney(r.income),
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.income,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(fmtMoney(r.expense),
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.expense,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(fmtMoney(r.balance),
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.text,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20, color: AppColors.textSecondary),
              ],
            ),
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
