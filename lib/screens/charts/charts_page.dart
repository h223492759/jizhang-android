import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';

class ChartsPage extends ConsumerStatefulWidget {
  const ChartsPage({super.key});
  @override
  ConsumerState<ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends ConsumerState<ChartsPage> {
  bool _yearMode = false;
  String _type = 'expense';
  late DateTime _period;
  List<DailyStat> _daily = [];
  List<MonthlyStat> _monthly = [];
  List<CatStat> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _period = DateTime(DateTime.now().year, DateTime.now().month);
    _load();
  }

  String _start() => _yearMode
      ? DateFormat('yyyy-01-01').format(_period)
      : DateFormat('yyyy-MM-01').format(_period);
  String _end() => _yearMode
      ? DateFormat('yyyy-12-31').format(_period)
      : DateFormat('yyyy-MM-dd').format(DateTime(_period.year, _period.month + 1, 0));

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final cats = await api.getCategoryStat(type: _type, start: _start(), end: _end());
      if (_yearMode) {
        _monthly = await api.getMonthly(year: _period.year);
        _daily = [];
      } else {
        _daily = await api.getDaily(start: _start(), end: _end());
        _monthly = [];
      }
      if (mounted) setState(() => _cats = cats);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    if (_yearMode) {
      final picked = await showDatePicker(
        context: context,
        initialDate: _period,
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        helpText: '选择年份',
      );
      if (picked != null) setState(() => _period = DateTime(picked.year, 1));
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: _period,
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        helpText: '选择月份',
      );
      if (picked != null) setState(() => _period = DateTime(picked.year, picked.month));
    }
    _load();
  }

  double get _max => _yearMode
      ? (_monthly.isEmpty ? 1 : _monthly.map((e) => e.expense + e.income).reduce((a, b) => a > b ? a : b))
      : (_daily.isEmpty ? 1 : _daily.map((e) => e.expense + e.income).reduce((a, b) => a > b ? a : b));

  @override
  Widget build(BuildContext context) {
    final color = _type == 'expense' ? AppColors.expense : AppColors.income;
    return Scaffold(
      appBar: AppBar(title: const Text('图表')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _seg(['月', '年'], _yearMode ? 1 : 0, (i) {
                      setState(() => _yearMode = i == 1);
                      _load();
                    }),
                    const Spacer(),
                    _seg(['支出', '收入'], _type == 'income' ? 1 : 0, (i) {
                      setState(() => _type = i == 1 ? 'income' : 'expense');
                      _load();
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(Icons.calendar_today, size: 18, color: AppColors.primaryDark),
                      const SizedBox(width: 8),
                      Text(_yearMode ? '${_period.year}年' : '${_period.year}年${_period.month}月',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      const Icon(Icons.arrow_drop_down),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 220,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: _yearMode ? _barChart(color) : _lineChart(color),
                ),
                const SizedBox(height: 20),
                const Text('分类排行', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                ..._cats.map((c) => _catRow(c, color)),
              ],
            ),
    );
  }

  Widget _seg(List<String> labels, int sel, void Function(int) onTap) {
    return Container(
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: labels.asMap().entries.map((e) {
          final active = e.key == sel;
          return GestureDetector(
            onTap: () => onTap(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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

  Widget _lineChart(Color color) {
    if (_daily.isEmpty) return const Center(child: Text('暂无数据'));
    final days = _daily.length;
    final spots = _daily.asMap().entries.map((e) {
      final v = _type == 'expense' ? e.value.expense : e.value.income;
      return FlSpot((e.key + 1).toDouble(), v);
    }).toList();
    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: color.withOpacity(0.12)),
        ),
      ],
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, _) {
            final idx = v.toInt() - 1;
            if (idx < 0 || idx >= days) return const Text('');
            if (idx % (days > 15 ? 5 : 2) != 0) return const Text('');
            return Text('${idx + 1}', style: const TextStyle(fontSize: 10));
          },
        )),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
    ));
  }

  Widget _barChart(Color color) {
    if (_monthly.isEmpty) return const Center(child: Text('暂无数据'));
    return BarChart(BarChartData(
      barGroups: _monthly.asMap().entries.map((e) {
        final v = _type == 'expense' ? e.value.expense : e.value.income;
        return BarChartGroupData(x: e.key, barRods: [
          BarRodData(toY: v, color: color, width: 12, borderRadius: BorderRadius.circular(4)),
        ]);
      }).toList(),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i % 2 != 0) return const Text('');
            return Text('${i + 1}月', style: const TextStyle(fontSize: 10));
          },
        )),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
    ));
  }

  Widget _catRow(CatStat c, Color color) {
    final max = _max <= 0 ? 1 : _max;
    final pct = (c.value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(c.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Expanded(
            child: LinearProgressIndicator(
              value: pct, minHeight: 12,
              backgroundColor: AppColors.background,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: Text('¥${fmtMoney(c.value)}', textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
