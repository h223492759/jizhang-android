import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/screens/record/flow_detail_page.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/core/local_first_api.dart';

class BillMonthDetailPage extends ConsumerStatefulWidget {
  /// 月份场景：传 ym（如 "2026-08"），isYear=false
  final String ym;
  /// 年份场景：传 year，isYear=true
  final int? year;
  final bool isYear;
  const BillMonthDetailPage({super.key, this.ym = '', this.year, this.isYear = false});

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
      final api = ref.read(localApiProvider);
      final d = widget.isYear
          ? await api.getBillYearDetail(widget.year!)
          : await api.getBillMonthDetail(widget.ym);
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
    final isYear = widget.isYear;
    final thisMonth = d?['thisMonth'] as Map? ?? {};
    final title = isYear
        ? '${widget.year} 年 · 年度账单总结'
        : '${widget.ym} · 月度账单总结';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? const Center(child: Text('加载失败'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 区域①：开篇说明
                    _regionIntro(d, isYear),
                    const SizedBox(height: 12),
                    // 区域②：结余概览
                    _summary(thisMonth, d, isYear),
                    const SizedBox(height: 16),
                    // 区域③：支出分类
                    _sectionTitle('支出分类'),
                    const SizedBox(height: 8),
                    ..._expenseCats(d?['expenseByCategory'] as List? ?? []),
                    const SizedBox(height: 16),
                    // 区域④：单笔最高 / 均值 / 当月支出
                    _sectionTitle(isYear ? '年度支出概览' : '月度支出概览'),
                    const SizedBox(height: 8),
                    _statRow(d, isYear),
                    const SizedBox(height: 16),
                    // 区域⑤：各月支出对比
                    _sectionTitle(isYear ? '各月支出对比' : '相邻月份支出对比'),
                    const SizedBox(height: 8),
                    _compareBar(d?['expenseCompare'] as List? ?? [], true),
                    const SizedBox(height: 16),
                    // 区域⑥：最高收入
                    _sectionTitle('最高收入'),
                    const SizedBox(height: 8),
                    ..._topFlows(d?['topIncomes'] as List? ?? [], isExpense: false),
                    const SizedBox(height: 16),
                    // 区域⑦：各月收入对比
                    _sectionTitle(isYear ? '各月收入对比' : '相邻月份收入对比'),
                    const SizedBox(height: 8),
                    _compareBar(d?['incomeCompare'] as List? ?? [], false),
                  ],
                ),
    );
  }

  Widget _regionIntro(Map d, bool isYear) {
    final sc = (d['startDayCount'] ?? 0);
    final first = (d['firstFlow'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isYear
                ? '这是 ${d['year']} 年的年度账单'
                : '这是 ${d['year']} 年 ${d['month']} 月的月度账单',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.text(context)),
          ),
          if (first.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('从 $first 起已记账 $sc 天',
                style: TextStyle(fontSize: 13, color: AppPalette.text(context))),
          ],
        ],
      ),
    );
  }

  Widget _summary(Map m, Map d, bool isYear) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isYear ? '上年结余' : '上月结余',
              style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(fmtMoney2((d['lastMonthBalance'] ?? 0).toDouble()),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _col(isYear ? '年收入' : '月收入',
                    (m['income'] ?? 0).toDouble(), AppColors.income),
                _col(isYear ? '年支出' : '月支出',
                    (m['expense'] ?? 0).toDouble(), AppColors.expense),
                _col(isYear ? '年结余' : '月结余',
                    (m['balance'] ?? 0).toDouble(), AppPalette.text(context)),
              ],
            ),
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
                style: TextStyle(
                    color: c, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ]),
      );

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold));

  List<Widget> _expenseCats(List list) {
    if (list.isEmpty) {
      return [Text('无支出记录', style: TextStyle(color: AppPalette.textSecondary(context)))];
    }
    return list.map((x) {
      final cat = x['category'] ?? '';
      final amt = (x['amount'] ?? 0).toDouble();
      final pct = (x['percent'] ?? 0).toDouble();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(cat, style: const TextStyle(fontWeight: FontWeight.bold))),
                  Text('${fmtMoney2(amt)} · ${pct.toStringAsFixed(1)}%',
                      style: TextStyle(color: AppPalette.textSecondary(context), fontSize: 13)),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (pct / 100).clamp(0, 1),
                backgroundColor: AppPalette.background(context),
                color: AppPalette.isDark(context) ? AppColors.primary : AppColors.primary,
                minHeight: 6,
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _statRow(Map d, bool isYear) {
    final hi = d['highestDayExpense'] as Map? ?? {};
    final hiAmt = (hi['amount'] ?? 0).toDouble();
    final hiDate = (hi['date'] ?? '').toString();
    final avg = (d['dailyAvgExpense'] ?? 0).toDouble();
    final thisMonth = d['thisMonth'] as Map? ?? {};
    final total = (thisMonth['expense'] ?? 0).toDouble();
    return Row(
      children: [
        Expanded(
          child: _statCard(
            isYear ? '单月最高支出' : '单日最高支出',
            fmtMoney2(hiAmt),
            hiDate.isNotEmpty ? hiDate : '',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            isYear ? '月均支出' : '日均支出',
            fmtMoney2(avg),
            '',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            isYear ? '年支出' : '月支出',
            fmtMoney2(total),
            '',
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, String sub) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.expense)),
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(fontSize: 11, color: AppPalette.textSecondary(context))),
            ],
          ],
        ),
      );

  // 年账单的「各月对比」只显示已到月份：现在是 2026-08 时，9-12 月不显示（历史年份不受影响）
  List _futureFiltered(List list) {
    if (!widget.isYear) return list;
    final now = DateTime.now();
    final curYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return list.where((m) {
      final ym = (m as Map?)?['ym']?.toString() ?? '';
      return ym.isEmpty || ym.compareTo(curYm) <= 0;
    }).toList();
  }

  Widget _compareBar(List rawList, bool isExpense) {
    final list = _futureFiltered(rawList);
    if (list.isEmpty) {
      return Text('暂无数据', style: TextStyle(color: AppPalette.textSecondary(context)));
    }
    final color = isExpense ? AppColors.expense : AppColors.income;
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          barGroups: list.asMap().entries.map((e) {
            final m = e.value as Map;
            final v = ((isExpense ? m['expense'] : m['income']) ?? 0).toDouble();
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: v,
                  color: color,
                  width: widget.isYear ? 14 : 10,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= list.length) return const Text('');
                  final m = list[i] as Map;
                  return Text('${m['label']}', style: const TextStyle(fontSize: 10));
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(
            show: true,
            border: Border(bottom: BorderSide(color: AppPalette.divider(context), width: 1)),
          ),
          // 触摸提示：用 fmtMoney 格式化，避免裸 double 显示很多位小数
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final m = list[group.x.toInt()] as Map;
                final label = (m['label'] ?? '').toString();
                return BarTooltipItem(
                  '$label  ¥${fmtMoney2(rod.toY)}',
                  TextStyle(color: AppPalette.card(context), fontSize: 12),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _topFlows(List list, {required bool isExpense}) {
    if (list.isEmpty) {
      return [Text('无记录', style: TextStyle(color: AppPalette.textSecondary(context)))];
    }
    return list.map((x) {
      final f = Flow.fromJson(x as Map<String, dynamic>);
      return Card(
        child: ListTile(
          title: Row(
            children: [
              if (f.isAiSource) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('AI',
                      style: TextStyle(fontSize: 9, color: AppPalette.card(context), fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                    '${f.category} ${f.description.isNotEmpty ? '· ${f.description}' : ''}',
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          subtitle: Text(f.flowTime),
          trailing: Text('${isExpense ? '-' : '+'}${fmtMoney2(f.amount)}',
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
