import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/core/owner_color.dart';
import 'package:jizhang_android/core/category_icon.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/flows/owner_flow_page.dart';
import 'package:jizhang_android/screens/charts/category_detail_page.dart';

class ChartsPage extends ConsumerStatefulWidget {
  const ChartsPage({super.key});
  @override
  ConsumerState<ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends ConsumerState<ChartsPage> {
  bool _yearMode = false;
  String _type = 'expense';
  late DateTime _period;
  List<CatStat> _cats = [];
  List<DailyStat> _daily = [];
  List<MonthlyStat> _monthly = [];
  List<Flow> _flows = [];
  List<Category> _catMeta = [];
  bool _loading = true;
  final ScrollController _periodScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _period = DateTime(DateTime.now().year, DateTime.now().month);
    _load();
  }

  @override
  void dispose() {
    _periodScroll.dispose();
    super.dispose();
  }

  String _start() => _yearMode
      ? DateFormat('yyyy-01-01').format(_period)
      : DateFormat('yyyy-MM-01').format(_period);
  String _end() => _yearMode
      ? DateFormat('yyyy-12-31').format(_period)
      : DateFormat('yyyy-MM-dd').format(DateTime(_period.year, _period.month + 1, 0));

  int get _daysInPeriod {
    final s = parseYmd(_start());
    final e = parseYmd(_end());
    return e.difference(s).inDays + 1;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final cats = await api.getCategoryStat(type: _type, start: _start(), end: _end());
      final catMeta = await api.getCategories();
      final flows = await api.getFlows(start: _start(), end: _end(), pageSize: 2000);
      if (_yearMode) {
        _monthly = await api.getMonthly(year: _period.year);
        _daily = [];
      } else {
        _daily = await api.getDaily(start: _start(), end: _end());
        _monthly = [];
      }
      if (mounted) {
        setState(() {
          _cats = cats;
          _catMeta = catMeta;
          _flows = flows.list;
        });
      }
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _max => _yearMode
      ? (_monthly.isEmpty ? 1 : _monthly.map((e) => _val(e)).reduce((a, b) => a > b ? a : b))
      : (_daily.isEmpty ? 1 : _daily.map((e) => _val(e)).reduce((a, b) => a > b ? a : b));

  double _val(dynamic e) => _type == 'expense'
      ? (e is DailyStat ? e.expense : (e as MonthlyStat).expense)
      : (e is DailyStat ? e.income : (e as MonthlyStat).income);

  // 当前周期内的总支出/总收入
  double get _periodTotal {
    final t = _type;
    double s = 0;
    for (final f in _flows) {
      if (f.type == t) s += f.amount;
    }
    return s;
  }

  // 归属人占比（仅统计当前 type）
  List<_OwnerSeg> get _ownerSegs {
    final user = ref.read(sessionProvider).user;
    final map = <String, double>{};
    final sample = <String, Flow>{};
    for (final f in _flows) {
      if (f.type != _type) continue;
      map[f.attribution] = (map[f.attribution] ?? 0) + f.amount;
      sample.putIfAbsent(f.attribution, () => f);
    }
    final segs = <_OwnerSeg>[];
    map.forEach((attr, v) {
      final f = sample[attr]!;
      segs.add(_OwnerSeg(
        attr: attr,
        value: v,
        color: ownerColorFor(f, ref.read(ownerColorsProvider), user),
        isSelf: isSelfAttribution(attr, user),
      ));
    });
    segs.sort((a, b) => b.value.compareTo(a.value));
    return segs;
  }

  @override
  Widget build(BuildContext context) {
    final color = _type == 'expense' ? AppColors.expense : AppColors.income;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  _modeAndTypeBar(color),
                  const SizedBox(height: 8),
                  _periodSelector(),
                  const Divider(height: 1, thickness: 1, color: AppColors.divider),
                  const SizedBox(height: 10),
                  _totalRow(color),
                  const SizedBox(height: 12),
                  Container(
                    height: 220,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: _barChart(color),
                  ),
                  const SizedBox(height: 16),
                  _ownerProportion(color),
                  const SizedBox(height: 16),
                  const Text('分类排行', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  ..._catRows(color),
                ],
              ),
      ),
    );
  }

  Widget _modeAndTypeBar(Color color) {
    return Row(
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

  // 左右滑动的日期选择器（无框、小字、选中黑字+黑色下划线、其他灰字；
  // 未来月/年不显示；非特殊的选中项居中）
  List<_PeriodOpt> _buildPeriodOpts() {
    final now = DateTime.now();
    final opts = <_PeriodOpt>[];
    if (_yearMode) {
      for (int y = now.year - 3; y <= now.year; y++) {
        String label;
        bool special;
        if (y == now.year) {
          label = '今年';
          special = true;
        } else if (y == now.year - 1) {
          label = '去年';
          special = true;
        } else {
          label = '${y}年';
          special = false;
        }
        opts.add(_PeriodOpt(
            label: label, year: y, month: 1, special: special, selected: y == _period.year));
      }
    } else {
      final startY = now.year - 2;
      for (int y = startY; y <= now.year; y++) {
        final maxM = y == now.year ? now.month : 12; // 未来的月份不显示
        for (int m = 1; m <= maxM; m++) {
          String label;
          bool special;
          if (y == now.year && m == now.month) {
            label = '本月';
            special = true;
          } else if (y == now.year && m == now.month - 1) {
            label = '上月';
            special = true;
          } else {
            label = '${m}月';
            special = false;
          }
          opts.add(_PeriodOpt(
              label: label,
              year: y,
              month: m,
              special: special,
              selected: y == _period.year && m == _period.month));
        }
      }
    }
    return opts;
  }

  void _centerSelected() {
    final opts = _buildPeriodOpts();
    final idx = opts.indexWhere((o) => o.selected);
    if (idx < 0 || opts[idx].special || !_periodScroll.hasClients) return;
    const chipW = 64.0;
    final max = _periodScroll.position.maxScrollExtent;
    final target = (idx * (chipW + 8) - (_periodScroll.position.viewportDimension / 2 - chipW / 2))
        .clamp(0.0, max);
    _periodScroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  Widget _periodSelector() {
    final opts = _buildPeriodOpts();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _periodScroll,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: opts.map((o) {
          return GestureDetector(
            onTap: () {
              setState(() => _period = DateTime(o.year, o.month));
              _load();
              WidgetsBinding.instance.addPostFrameCallback((_) => _centerSelected());
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(o.label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: o.selected ? FontWeight.bold : FontWeight.normal,
                          color: o.selected ? AppColors.text : AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Container(
                    height: 3,
                    width: 18,
                    decoration: BoxDecoration(
                      color: o.selected ? AppColors.text : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _totalRow(Color color) {
    final total = _periodTotal;
    final avg = _daysInPeriod > 0 ? total / _daysInPeriod : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text('总${_type == 'expense' ? '支出' : '收入'}：¥${fmtMoney(total)}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const Spacer(),
          Text('平均值：¥${fmtMoney(avg)}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _barChart(Color color) {
    if (_yearMode) {
      if (_monthly.isEmpty) return const Center(child: Text('暂无数据'));
    } else {
      if (_daily.isEmpty) return const Center(child: Text('暂无数据'));
    }
    final data = _yearMode ? _monthly : _daily;
    return BarChart(
      BarChartData(
        barGroups: data.asMap().entries.map((e) {
          return BarChartGroupData(x: e.key, barRods: [
            BarChartRodData(
              toY: _val(e.value),
              color: color,
              width: _yearMode ? 14 : 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ]);
        }).toList(),
        barTouchData: BarTouchData(
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response != null && response.spot != null) {
              _onBarTap(response.spot!.touchedBarGroupIndex);
            }
          },
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (_yearMode) {
                if (i % 2 != 0) return const Text('');
                return Text('${i + 1}月', style: const TextStyle(fontSize: 10));
              } else {
                final days = data.length;
                if (i % (days > 15 ? 5 : 3) != 0) return const Text('');
                return Text('${i + 1}', style: const TextStyle(fontSize: 10));
              }
            },
          )),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
        ),
      ),
    );
  }

  String _catIcon(String name) {
    final c = _catMeta.cast<Category?>().firstWhere(
          (c) => c?.name == name,
          orElse: () => null,
        );
    return c?.icon ?? '💰';
  }

  Future<void> _onBarTap(int index) async {
    List<_TopItem> top;
    double barTotal;
    String dateLabel;
    if (_yearMode) {
      final m = index + 1;
      dateLabel = '${_period.year}年$m月';
      final s = DateFormat('yyyy-MM-01').format(DateTime(_period.year, m));
      final e = DateFormat('yyyy-MM-dd').format(DateTime(_period.year, m + 1, 0));
      final fp = await ref.read(apiProvider).getFlows(start: s, end: e, pageSize: 2000);
      final list = fp.list.where((f) => f.type == _type).toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
      top = list.take(3).map((f) => _TopItem(f)).toList();
      barTotal = list.fold(0.0, (s, f) => s + f.amount);
    } else {
      final d = _daily[index];
      dateLabel = d.date;
      barTotal = _type == 'expense' ? d.expense : d.income;
      final items = <DailyTopItem>[];
      d.top.forEach((_, v) => items.addAll(v));
      items.sort((a, b) => b.amount.compareTo(a.amount));
      top = items.take(3).map((i) => _TopItem.fromDaily(i)).toList();
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(dateLabel),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('总${_type == 'expense' ? '支出' : '收入'}：¥${fmtMoney(barTotal)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('最大 3 笔：', style: TextStyle(color: AppColors.textSecondary)),
              ...top.map((t) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('${t.date}  ${t.name}  ¥${fmtMoney(t.amount)}',
                        style: const TextStyle(fontSize: 13)),
                  )),
              if (top.isEmpty) const Text('无', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  // 归属人占比：横向堆叠条（自己灰色，其他按底色）
  Widget _ownerProportion(Color color) {
    final segs = _ownerSegs;
    final total = segs.fold(0.0, (s, e) => s + e.value);
    if (total <= 0) return const SizedBox.shrink();
    final self = segs.where((s) => s.isSelf).toList();
    final others = segs.where((s) => !s.isSelf).toList();
    final selfVal = self.fold(0.0, (s, e) => s + e.value);
    final otherVal = others.fold(0.0, (s, e) => s + e.value);
    final topOther = others.isNotEmpty ? others.first : null;
    final leftSeg = self.isNotEmpty ? self.first : segs.first;
    final rightSeg = others.isNotEmpty
        ? others.first
        : (segs.length > 1 ? segs[1] : segs.first);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (segs.length == 1) ...[
            Text(
              '${_ownerLabel(segs.first)}  ¥${fmtMoney(segs.first.value)}  ${(segs.first.value / total * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_ownerLabel(leftSeg)}  ¥${fmtMoney(leftSeg.value)}  ${(leftSeg.value / total * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${(rightSeg.value / total * 100).toStringAsFixed(0)}%  ¥${fmtMoney(rightSeg.value)}  ${rightSeg.attr.isEmpty ? '其他' : rightSeg.attr}',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 18,
            child: Row(
              children: [
                if (self.isNotEmpty)
                  Expanded(
                    flex: selfVal.round(),
                    child: GestureDetector(
                      onTap: () => _openOwner(self.first, isSelf: true),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6), bottomLeft: Radius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                ...others.map((o) => Expanded(
                      flex: o.value.round(),
                      child: GestureDetector(
                        onTap: () => _openOwner(o, isSelf: false),
                        child: Container(color: o.color),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _ownerLabel(_OwnerSeg s) => s.isSelf ? '我' : (s.attr.isEmpty ? '我' : s.attr);

  void _openOwner(_OwnerSeg seg, {required bool isSelf}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerFlowPage(
          attribution: seg.attr.isEmpty ? (ref.read(sessionProvider).user?.nickname ?? '') : seg.attr,
          title: seg.attr.isEmpty ? '我' : seg.attr,
          start: _start(),
          end: _end(),
          isSelf: isSelf,
        ),
      ),
    );
  }

  List<Widget> _catRows(Color color) {
    final catTotal = _cats.fold(0.0, (s, c) => s + c.value);
    final maxVal = _cats.fold(0.0, (s, c) => c.value > s ? c.value : s);
    final iconMap = <String, String>{};
    for (final c in _catMeta) iconMap[c.name] = c.icon;
    return _cats.map((c) {
      final pct = catTotal > 0 ? c.value / catTotal : 0.0;
      final barPct = maxVal > 0 ? c.value / maxVal : 0.0; // 首条顶格，其余按比例
      return InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryDetailPage(
              category: c.name,
              type: _type,
              start: _start(),
              end: _end(),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySoft,
                child: Text(catIconOf(iconMap, c.name), style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('${c.name}    ${(pct * 100).toStringAsFixed(0)}%')),
                        Text('¥${fmtMoney(c.value)}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: barPct,
                      minHeight: 6,
                      backgroundColor: AppColors.background,
                      valueColor: AlwaysStoppedAnimation(color),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}

class _PeriodOpt {
  final String label;
  final int year;
  final int month;
  final bool selected;
  final bool special;
  _PeriodOpt(
      {required this.label,
      required this.year,
      required this.month,
      required this.selected,
      this.special = false});
}

class _OwnerSeg {
  final String attr;
  final double value;
  final Color color;
  final bool isSelf;
  _OwnerSeg({required this.attr, required this.value, required this.color, required this.isSelf});
}

class _TopItem {
  final String date;
  final String name;
  final double amount;
  _TopItem(Flow f)
      : date = datePart(f.flowTime),
        name = f.description.isNotEmpty ? f.description : f.category,
        amount = f.amount;
  _TopItem.fromDaily(DailyTopItem i)
      : date = '',
        name = i.description?.isNotEmpty == true ? i.description! : (i.category ?? ''),
        amount = i.amount;
}
