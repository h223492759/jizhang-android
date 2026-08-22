import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/bills/bill_month_detail_page.dart';
import 'package:jizhang_android/core/local_first_api.dart';

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
      final api = ref.read(localApiProvider);
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
    // 只选年份：只显示有流水记录的年份（后端 years 字段，倒序），避免无记录年份可选
    final years = (_monthly?.years.isNotEmpty ?? false)
        ? _monthly!.years
        : <int>[DateTime.now().year];
    if (years.length <= 1) return; // 只有一个年份无需选择
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
                          color: active ? AppColors.primary : AppPalette.background(context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$y',
                            style: TextStyle(
                                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                color: active ? AppPalette.text(context) : AppPalette.textSecondary(context))),
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
    // 月账单：月份由高到低显示，未到的月份不显示（month 形如 "2026-08"，字典序即时间序）
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final rows = _yearMode
        ? sourceRows
        : sourceRows.where((r) => r.month.compareTo(curYm) <= 0).toList()
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
                    color: AppPalette.background(context),
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

  TextStyle _headStyle() => TextStyle(
      fontSize: 12, color: AppPalette.textSecondary(context), fontWeight: FontWeight.bold);

  Widget _summary(BillRow s) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _col('收入', s.income, AppColors.income),
            _col('支出', s.expense, AppColors.expense),
            _col('结余', s.balance, AppPalette.text(context)),
          ],
        ),
      );

  Widget _col(String l, double v, Color c) => Expanded(
        child: Column(children: [
          Text(l, style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(fmtMoney2(v),
                style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
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
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.text(context)),
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(fmtMoney2(r.income),
                        style: TextStyle(
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
                    child: Text(fmtMoney2(r.expense),
                        style: TextStyle(
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
                    child: Text(fmtMoney2(r.balance),
                        style: TextStyle(
                            fontSize: 14,
                            color: AppPalette.text(context),
                            fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 20, color: AppPalette.textSecondary(context)),
              ],
            ),
          ),
        ),
      );

  Widget _seg(List<String> labels, int sel, void Function(int) onTap) => Container(
        decoration: BoxDecoration(color: AppPalette.background(context), borderRadius: BorderRadius.circular(20)),
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
                    style: TextStyle(color: active ? AppPalette.text(context) : AppPalette.textSecondary(context))),
              ),
            );
          }).toList(),
        ),
      );
}
