import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:jizhang_android/core/local_first_api.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/screens/utility/utility_common.dart';
import 'package:jizhang_android/screens/utility/utility_rules_page.dart';

/// 水电气物业每月用量
/// - 顶部固定两行：类型 seg + 视图 seg（按月/按年，复用账单页交互）+ 年份切换，下方滚动（v2.2.0 固定头约定）
/// - 趋势图（金额柱状，第2档橙/第3档红着色）
/// - 高亮：第2档橙黄（浅底+左条+badge），第3档及以上红色强警示
/// - 详情弹层：录入实际账单金额 / 改用量（保存后服务端重算档位与状态）、删除账单
/// - 数据纯在线（服务端 utility_records，无本地镜像）
class UtilityPage extends ConsumerStatefulWidget {
  const UtilityPage({super.key});
  @override
  ConsumerState<UtilityPage> createState() => _UtilityPageState();
}

double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;
int _tier(dynamic v) => (v as num?)?.toInt() ?? 1;

class _UtilityPageState extends ConsumerState<UtilityPage> {
  String _type = 'electric';
  int _year = DateTime.now().year;
  bool _yearMode = false; // v260908：false=按月（某年12个月） true=按年（历年汇总）
  List<dynamic> _rules = [];
  List<dynamic> _records = [];
  List<dynamic> _months = [];
  List<dynamic> _years = [];
  int _minYear = 0; // v260910：规则起点前年份不可切换（/years 升序首年；0=未加载/不限）
  bool _loading = true;
  bool _offlineCache = false; // 本批数据来自本地缓存（断网回退）

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  bool get _hasRule => _rules.any((r) => (r as Map)['type'] == _type);

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final api = ref.read(localApiProvider);
    api.lastUsedCache = false;
    try {
      final r1 = await api.getUtilityRules();
      final r2 = await api.getUtilityRecords(type: _type, year: _year);
      // 始终拉 years：v260910 翻年下限 = /years 升序首年（规则起点前不可切换）
      final rY = await api.getUtilityYears(type: _type);
      if (!_yearMode) {
        final minY = rY.isEmpty ? null : ((rY.first as Map)['year'] as num?)?.toInt();
        if (minY != null && _year < minY) {
          _year = minY; // 切到规则起点更晚的类型时钳制，避免停在不可达年份
        }
      }
      if (_yearMode) {
        if (!mounted) return;
        setState(() {
          _rules = r1;
          _records = r2;
          _years = rY;
          _minYear = rY.isEmpty ? _minYear : ((rY.first as Map)['year'] as num?)?.toInt() ?? _minYear;
          _loading = false;
          _offlineCache = api.lastUsedCache;
        });
      } else {
        final r3 = await api.getUtilityMonths(type: _type, year: _year);
        if (!mounted) return;
        setState(() {
          _rules = r1;
          _records = r2;
          _years = rY;
          _minYear = rY.isEmpty ? _minYear : ((rY.first as Map)['year'] as num?)?.toInt() ?? _minYear;
          _months = ((r3['months'] as List<dynamic>?) ?? []);
          _loading = false;
          _offlineCache = api.lastUsedCache;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offlineCache = false;
      });
      toast('加载失败：$e');
    }
  }

  Future<void> _loadRulesOnly() async {
    try {
      final r = await ref.read(localApiProvider).getUtilityRules();
      if (mounted) setState(() => _rules = r);
    } catch (_) {}
  }

  Future<void> _goRules() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const UtilityRulesPage()));
    await _loadRulesOnly();
    if (mounted) await _refresh();
  }

  Future<void> _scan() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('扫描历史流水'),
        content: Text('按当前「${utilityLabel(_type)}」规则生效后的历史流水生成/并入账单？\n（已生成的不会重复）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('扫描')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final n = await ref.read(localApiProvider).scanUtilityFlows(_type);
      if (mounted) toast('扫描完成：$n 笔流水已处理');
      await _refresh();
    } catch (e) {
      toast('扫描失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background(context),
      extendBody: false,
      appBar: AppBar(
        title: const Text('水电气用量'),
        actions: [
          IconButton(
            tooltip: '手动添加账单',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _openAddDialog,
          ),
          if (_hasRule)
            IconButton(
              tooltip: '扫描历史',
              icon: const Icon(Icons.sync),
              onPressed: _scan,
            ),
          IconButton(
            tooltip: '规则设置',
            icon: const Icon(Icons.tune),
            onPressed: _goRules,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 离线缓存提示条（断网时本页数据来自本地缓存）
            if (_offlineCache)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppPalette.cardSubtle(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off,
                        size: 14, color: AppPalette.textSecondary(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('网络不可用，显示上次缓存数据',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppPalette.textSecondary(context))),
                    ),
                  ],
                ),
              ),
            // PIN 1: 类型（水/电/燃气/物业）
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: _segRow(),
            ),
            // PIN 2: 月/年视图 seg（复用账单页交互）+ 年份切换（月模式）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                _seg(['按月', '按年'], _yearMode ? 1 : 0, (i) {
                  setState(() => _yearMode = i == 1);
                  _refresh();
                }),
                const Spacer(),
                if (!_yearMode) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left),
                    // v260910：规则起点前的年份不可切换（下限 = /years 升序首年）
                    onPressed: _minYear > 0 && _year <= _minYear
                        ? null
                        : () {
                            setState(() => _year -= 1);
                            _refresh();
                          },
                  ),
                  Text('$_year 年',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_right),
                    // v2.2.17：未来年份不可切换（上限=当前年，与网页端一致；原为 +3 年）
                    onPressed: _year < DateTime.now().year
                        ? () {
                            setState(() => _year += 1);
                            _refresh();
                          }
                        : null,
                  ),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Divider(
                  height: 1, thickness: 1, color: AppPalette.divider(context)),
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _segRow() {
    return Container(
      decoration: BoxDecoration(
          color: AppPalette.background(context),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: kUtilityTypes.map((t) {
          final type = t['type']!;
          final active = type == _type;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (type == _type) return;
                setState(() => _type = type);
                _refresh();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${t['icon']}${t['label']}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active
                        ? AppPalette.onPrimary(context)
                        : AppPalette.textSecondary(context),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (!_hasRule) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border(
                left: BorderSide(color: AppColors.primaryDark, width: 4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('「${utilityLabel(_type)}」还没有计价规则',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('规则带生效时间，生效日期之前的流水不会自动计入；'
                '添加规则后，新保存的流水会自动生成账单，也可在右上角用「扫描历史」回填。',
                style: TextStyle(
                    fontSize: 12, color: AppPalette.textSecondary(context))),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _goRules, child: const Text('去添加规则')),
          ]),
        ),
        const SizedBox(height: 12),
        Text('说明：第2档起橙黄高亮，第3档及以上红色警示',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, color: AppPalette.textSecondary(context))),
      ]);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // 按年视图：历年汇总行 + 跨年趋势
    if (_yearMode) {
      final hasData = _years.any((y) => (y as Map)['hasBill'] == true);
      if (_years.isEmpty) {
        return const Center(
            child: Text('暂无数据', style: TextStyle(color: AppColors.textSecondary)));
      }
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (hasData) _trendCard(context, yearMode: true),
          ..._years.map((y) => _yearRow(context, y as Map)),
        ],
      );
    }
    // 按月视图：趋势图 + 12 个月行
    if (_months.isEmpty) {
      return const Center(
          child: Text('暂无数据', style: TextStyle(color: AppColors.textSecondary)));
    }
    final hasData =
        _months.any((m) => (m as Map)['hasBill'] == true);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (hasData) _trendCard(context, yearMode: false),
        ..._months.map((m) {
          final mm = m as Map;
          final month = (mm['month'] as num?)?.toInt() ?? 1;
          final hasBill = (mm['hasBill'] as bool?) ?? false;
          final tier = _tier(mm['tier']);
          final note = (mm['note'] as String?) ?? '';
          return _monthRow(context, month, hasBill, tier, note, _num(mm['usage']),
              _num(mm['amountAvg']), _num(mm['amount']));
        }),
      ],
    );
  }

  // 月/年切换 seg（与账单页一致）
  Widget _seg(List<String> labels, int sel, void Function(int) onTap) {
    return Container(
      decoration: BoxDecoration(
          color: AppPalette.background(context),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: labels.asMap().entries.map((e) {
          final active = e.key == sel;
          return GestureDetector(
            onTap: () => onTap(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(e.value,
                  style: TextStyle(
                      fontSize: 13,
                      color: active
                          ? AppPalette.onPrimary(context)
                          : AppPalette.textSecondary(context))),
            ),
          );
        }).toList(),
      ),
    );
  }

  double _axisMax(double v) {
    if (v <= 0) return 1;
    final m = (v * 1.15);
    return m > 0 ? m : 1;
  }

  // 趋势图（v2.2.6 改造）：
  //  - 物业 = 金额柱（蓝）；水/电/燃气 = 用量柱（绿）
  //  - 档位虚线（无档位/物业费不画）
  //  - 触摸/悬浮 tooltip 与柱对应（物业只显金额；水电气只显用量；档位仍提示）
  Widget _trendCard(BuildContext context, {required bool yearMode}) {
    List<Map> rows;
    if (yearMode) {
      rows = _years
          .map((e) => e as Map)
          .where((y) => y['hasBill'] == true)
          .toList()
        ..sort((a, b) => ((a['year'] as num?)?.toInt() ?? 0)
            .compareTo((b['year'] as num?)?.toInt() ?? 0));
    } else {
      rows = _months.map((e) => e as Map).toList();
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final isProperty = _type == 'property';
    // v2.2.13：柱值字段——物业取 amountAvg（均摊月金额，如 3月一交→每月82）；
    // 水/电/燃气取 usage（均摊用量）。_num 返回 double，声明成 double 避免 num 宽化。
    final double Function(Map) colVal = isProperty
        ? (m) => _num(m['amountAvg'] ?? m['amount'])
        : (m) => _num(m['usage']);
    double maxV = 0;
    for (final r in rows) {
      final has = yearMode || (r['hasBill'] == true);
      final double v = has ? colVal(r) : 0.0;
      if (v > maxV) maxV = v;
    }
    final barColor = isProperty ? const Color(0xFF6366F1) : const Color(0xFF10B981);
    // v2.2.13：柱按行 tier 着色（1档=主色/2档=橙/3档+=红）；物业统一蓝（无档位）
    final Color tier1 = barColor;
    final Color tier2 = const Color(0xFFF59E0B);
    final Color tier3Plus = const Color(0xFFEF4444);
    Color barColorOf(Map r) {
      if (isProperty) return barColor;
      final t = (r['tier'] as num?)?.toInt() ?? 1;
      if (t >= 3) return tier3Plus;
      if (t == 2) return tier2;
      return tier1;
    }
    // v2.2.13：取消档位虚线（服务端不再下发 tierThresholds）
    final double yMax = _axisMax(maxV);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('${yearMode ? '历年' : '$_year 年'}${isProperty ? "金额" : "用量"}趋势',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(isProperty ? '月均金额' : '第2档起橙/第3档红',
                style: TextStyle(
                    fontSize: 10, color: AppPalette.textSecondary(context))),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                maxY: yMax,
                alignment: BarChartAlignment.spaceAround,
                // v2.2.13：取消档位虚线 → extraLinesData 省略
                gridData: const FlGridData(
                    show: false, drawVerticalLine: false),
                barGroups: rows.asMap().entries.map((e) {
                  final i = e.key;
                  final m = e.value;
                  final has = yearMode || (m['hasBill'] == true);
                  final double v = has ? colVal(m) : 0.0;
                  return BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: v,
                      // v260911-12：柱按行 tier 着色（1档主色、2档橙、3档+=红）
                      color: barColorOf(m),
                      width: yearMode ? 20 : 10,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3)),
                    ),
                  ]);
                }).toList(),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (g, gi, rod, ri) {
                      final m = rows[g.x];
                      final has = yearMode || (m['hasBill'] == true);
                      if (!has || rod.toY <= 0) return null;
                      final lbl = yearMode
                          ? '${m['year']}年'
                          : '${(m['month'] as num?)?.toInt() ?? g.x + 1}月';
                      final u = _num(m['usage']);
                      final a = _num(m['amountAvg'] ?? m['amount']);
                      final tier = _tier(m['tier']);
                      // v2.2.13：物业 tooltip 显示均摊月金额；水电气显示均摊用量
                      final body = isProperty
                          ? '$lbl\n¥${fmtMoney2(a)}'
                          : '$lbl\n用量 ${u.round()} ${utilityUnitOf(_type)}';
                      final tail = (tier >= 2) ? '\n第$tier档' : '';
                      return BarTooltipItem(
                        '$body$tail',
                        TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppPalette.card(context)),
                      );
                    },
                  ),
                ),
                // gridData 在前面已设 show:false（Dart 重复 field 会编译错误，故删除此处）
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= rows.length) return const Text('');
                        final label = yearMode
                            ? '${rows[i]['year']}'
                            : '${i + 1}';
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(label,
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: AppColors.textSecondary)),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 按年：历年汇总行（v2.2.6：4 列等距 grid，年份-用量-档位-金额）
  Widget _yearRow(BuildContext context, Map y) {
    final year = (y['year'] as num?)?.toInt() ?? 0;
    final hasBill = (y['hasBill'] as bool?) ?? false;
    final tier = _tier(y['tier']);
    final usage = _num(y['usage']);
    final amount = _num(y['amount']);
    final base = AppPalette.card(context);
    Color bg;
    Color? left;
    if (tier >= 3) {
      bg = Color.alphaBlend(const Color(0x21F04438), base);
      left = AppColors.expense;
    } else if (tier == 2) {
      bg = Color.alphaBlend(const Color(0x1CF59E0B), base);
      left = const Color(0xFFF59E0B);
    } else {
      bg = base;
    }
    final usageText = (!hasBill || usage <= 0) ? '—' : '${usage.round()}';
    // v2.2.13：数值为 "—" 时不带单位尾巴（避免物业年视图 "-- 元" 观感）
    final unit = usageText == '—' ? '' : utilityUnitOf(_type);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: left != null
            ? Border(left: BorderSide(color: left, width: 3.5))
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: hasBill
            ? () {
                setState(() {
                  _year = year;
                  _yearMode = false;
                });
                _refresh();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(children: [
            // col 1: 年份（等距）
            Expanded(
              flex: 10,
              child: Text('$year年',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            // col 2: 用量
            Expanded(
              flex: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(usageText,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: tier >= 3 ? AppColors.expense : AppPalette.text(context),
                      )),
                  if (unit.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 3, bottom: 2),
                      child: Text(unit,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppPalette.textSecondary(context))),
                    ),
                ],
              ),
            ),
            // col 3: 档位（占位）
            Expanded(
              flex: 10,
              child: Center(
                child: tier >= 2
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: tier >= 3 ? AppColors.expense : const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('第$tier档',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      )
                    : Text('—',
                        style: TextStyle(
                            color: Colors.transparent, fontSize: 12)),
              ),
            ),
            // col 4: 金额
            Expanded(
              flex: 14,
              child: Text(
                amount > 0 ? '¥${fmtMoney2(amount)}' : '—',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: tier >= 3 ? AppColors.expense : AppPalette.text(context),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _monthRow(BuildContext context, int month, bool hasBill, int tier,
      String note, double usage, double amountAvg, double amount) {
    final base = AppPalette.card(context);
    Color bg;
    Color? left;
    if (tier >= 3) {
      bg = Color.alphaBlend(const Color(0x21F04438), base);
      left = AppColors.expense;
    } else if (tier == 2) {
      bg = Color.alphaBlend(const Color(0x1CF59E0B), base);
      left = const Color(0xFFF59E0B);
    } else {
      bg = base;
    }
    // v2.2.13：物业无用量 → 中间列显示「均摊月金额」（amountAvg，如 82元/月）；
    // 水电气 → 均摊用量。金额列(最右) v2.2.17 起在账期末月全额显示（amount）。
    final isProperty = _type == 'property';
    final midVal = isProperty ? amountAvg : usage;
    final usageText = (!hasBill || midVal <= 0) ? '—' : '${midVal.round()}';
    final unit = hasBill ? utilityUnitOf(_type) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border:
            left != null ? Border(left: BorderSide(color: left, width: 3.5)) : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: hasBill ? () => _openDetail(month) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(children: [
            // col 1: 月份
            Expanded(
              flex: 10,
              child: Text('$month月',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            // col 2: 用量（物业=均摊月金额 amountAvg；水电气=均摊用量 usage）
            Expanded(
              flex: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(usageText,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: tier >= 3
                            ? AppColors.expense
                            : AppPalette.text(context),
                      )),
                  if (unit.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 3, bottom: 2),
                      child: Text(unit,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppPalette.textSecondary(context))),
                    ),
                ],
              ),
            ),
            // col 3: 档位（占位）
            Expanded(
              flex: 10,
              child: Center(
                child: tier >= 2
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: tier >= 3 ? AppColors.expense : const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('第$tier档',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      )
                    : note.isNotEmpty
                        ? Text(note,
                            style: const TextStyle(
                                color: AppColors.expense,
                                fontSize: 12,
                                fontWeight: FontWeight.w600))
                        : Text('—',
                            style: TextStyle(
                                color: Colors.transparent, fontSize: 12)),
              ),
            ),
            // col 4: 金额（v2.2.17 起在「账期末月」全额显示 amount；双月/季度只期末月有值）
            Expanded(
              flex: 14,
              child: Text(
                amount > 0 ? '¥${fmtMoney2(amount)}' : '—',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: tier >= 3 ? AppColors.expense : AppPalette.text(context),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ================= 详情（补优惠/改用量/删除） =================
  // 弹窗命中：仅「账单覆盖该月」（用户 2026-09-10 第 6 轮定论）。
  // 缴费月命中曾用于支持「燃气 2 月 ¥219.52 点开对应账期 12~01 的账单」，但带来
  // 弹窗合并错位（账期跨月覆盖、缴费月与覆盖月错位时两张账单进同一弹窗）。
  // 现在改严格覆盖——账期右端 ≥ 账期左端 ≤ 该月 的账单才进入弹窗。
  List<Map> _billsOf(String ym) {
    return _records
        .where((r) {
          final m = r as Map;
          final bs = m['bill_start'] as String?;
          final be = m['bill_end'] as String?;
          return bs != null &&
              be != null &&
              bs.compareTo(ym) <= 0 &&
              be.compareTo(ym) >= 0;
        })
        .cast<Map>()
        .toList();
  }

  Future<void> _openDetail(int month) async {
    final ym = '$_year-${month.toString().padLeft(2, '0')}';
    final bills = _billsOf(ym);
    if (bills.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _DetailSheet(
        monthLabel: '$ym ${utilityLabel(_type)}',
        unit: utilityUnitOf(_type),
        bills: bills,
        onChanged: () async {
          // 校正/删除成功后：刷新外层数据并关闭弹层
          if (mounted) await _refresh();
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }

  // ================= 手动添加账单 =================
  Future<void> _openAddDialog() async {
    final now = DateTime.now();
    var bStart = ym2(now);
    var bEnd = ym2(now);
    final usageCtrl = TextEditingController();
    final paidCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();
    final label = utilityLabel(_type);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('手动添加$label账单',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    _fieldLabel('覆盖起始月'),
                    _ymField(ctx, bStart, (v) => setSt(() => bStart = v)),
                    const SizedBox(height: 8),
                    _fieldLabel('覆盖结束月'),
                    _ymField(ctx, bEnd, (v) => setSt(() => bEnd = v)),
                    const SizedBox(height: 12),
                    _fieldLabel('本期用量 ${utilityUnitOf(_type)}（选填，抄表数差值）'),
                    TextField(
                      controller: usageCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _dec('留空则按实付金额反推'),
                    ),
                    const SizedBox(height: 12),
                    _fieldLabel('实付金额（选填）'),
                    TextField(
                      controller: paidCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _dec('如 246'),
                    ),
                    const SizedBox(height: 12),
                    _fieldLabel('备注（选填）'),
                    TextField(controller: remarkCtrl, decoration: _dec('')),
                    const SizedBox(height: 6),
                    Text('平时由流水自动生成，此入口用于抄表补录 / 一笔合并缴费等特殊情况。',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppPalette.textSecondary(ctx))),
                    const SizedBox(height: 14),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消')),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppPalette.onPrimary(ctx)),
                        onPressed: () async {
                          final body = <String, dynamic>{
                            'type': _type,
                            'bill_start': bStart,
                            'bill_end': bEnd,
                            'remark': remarkCtrl.text.trim(),
                          };
                          final u = double.tryParse(usageCtrl.text.trim());
                          final p = double.tryParse(paidCtrl.text.trim());
                          if (u != null) body['usage'] = u;
                          if (p != null) body['paid'] = p;
                          if (!body.containsKey('usage') &&
                              !body.containsKey('paid')) {
                            toast('请填写用量或金额至少一项');
                            return;
                          }
                          try {
                            await ref
                                .read(localApiProvider)
                                .createUtilityRecord(body);
                            if (ctx.mounted) Navigator.pop(ctx);
                            toast('已添加');
                            await _refresh();
                          } catch (e) {
                            toast('添加失败：$e');
                          }
                        },
                        child: const Text('保存'),
                      ),
                    ]),
                  ]),
            ),
          );
        });
      },
    );
    usageCtrl.dispose();
    paidCtrl.dispose();
    remarkCtrl.dispose();
  }

  Widget _ymField(
      BuildContext ctx, String val, ValueChanged<String> onPick) {
    return InkWell(
      onTap: () async {
        final p = await pickMonth(ctx, initial: val);
        if (p != null) onPick(p);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.background(ctx),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(Icons.calendar_month,
              size: 16, color: AppPalette.textSecondary(ctx)),
          const SizedBox(width: 8),
          Text(val, style: const TextStyle(fontSize: 14)),
        ]),
      ),
    );
  }

  Widget _fieldLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(s,
            style:
                TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );
}

/// 账单详情弹层（补优惠 / 改用量 / 删除）
class _DetailSheet extends ConsumerStatefulWidget {
  final String monthLabel;
  final String unit;
  final List<Map> bills;
  final VoidCallback onChanged;
  const _DetailSheet(
      {required this.monthLabel,
      required this.unit,
      required this.bills,
      required this.onChanged});
  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<_DetailSheet> {
  late Map _sel;
  // v260908：录入「实际账单金额」（账单应缴原价）；优惠 = 该金额 − 实付，前端换算后仍走 discount 字段
  late TextEditingController _actualCtrl;
  late TextEditingController _usageCtrl;

  @override
  void initState() {
    super.initState();
    _sel = widget.bills.first;
    _resetCtrls();
  }

  void _resetCtrls() {
    final paid = (_sel['paid'] as num?)?.toDouble() ?? 0;
    final disc = (_sel['discount'] as num?)?.toDouble() ?? 0;
    _actualCtrl = TextEditingController(
        text: paid + disc > 0 ? '${(paid + disc).toStringAsFixed(2)}' : '');
    final u = _sel['usage_total'];
    _usageCtrl =
        TextEditingController(text: u == null ? '' : '${(u as num).toDouble()}');
  }

  @override
  void dispose() {
    _actualCtrl.dispose();
    _usageCtrl.dispose();
    super.dispose();
  }

  void _pick(Map b) {
    setState(() {
      _sel = b;
      _resetCtrls();
    });
  }

  String _tierText() {
    final t = (_sel['tier_level'] as num?)?.toInt() ?? 1;
    return t >= 2 ? '第$t档' : '第1档（正常）';
  }

  Color _tierColor() {
    final t = (_sel['tier_level'] as num?)?.toInt() ?? 1;
    if (t >= 3) return AppColors.expense;
    if (t == 2) return const Color(0xFFF59E0B);
    return AppPalette.textSecondary(context);
  }

  String _statusText() {
    const map = {'auto': '自动', 'pending': '待校正', 'corrected': '已校正', 'manual': '手动'};
    return map[_sel['status'] as String?] ?? '${_sel['status']}';
  }

  String _money(dynamic v) => '¥${fmtMoney2((v as num?)?.toDouble() ?? 0)}';

  String _d10(String? iso) {
    if (iso == null || iso.length < 10) return iso ?? '';
    return iso.substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    final List flows = ((_sel['flows'] as List?) ?? []);
    final status = (_sel['status'] as String?) ?? 'auto';
    final discount = (_sel['discount'] as num?)?.toDouble() ?? 0;
    final usageTotal = _sel['usage_total'];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.monthLabel,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (widget.bills.length > 1) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: widget.bills.map((b) {
                  final on = b['id'] == _sel['id'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _pick(b),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: on
                              ? AppColors.primary
                              : AppPalette.background(context),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${b['bill_start']}~${b['bill_end']}',
                          style: TextStyle(
                              fontSize: 12,
                              color: on
                                  ? AppPalette.onPrimary(context)
                                  : AppPalette.textSecondary(context)),
                        ),
                      ),
                    ),
                  );
                }).toList()),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppPalette.background(context),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kv('账单区间', '${_sel['bill_start']} ~ ${_sel['bill_end']}'),
                          _kv(
                              '本期用量',
                              usageTotal == null
                                  ? '—'
                                  : '${(usageTotal as num).toDouble()} ${widget.unit}'),
                          _kvColor('用量档位', _tierText(), _tierColor()),
                        ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    _kv('应缴', _money(_sel['charge'])),
                    _kv('优惠', '−${_money(discount)}'),
                    _kv('实付', _money(_sel['paid'])),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Text('状态：',
                  style: TextStyle(
                      fontSize: 13, color: AppPalette.textSecondary(context))),
              Text(_statusText(),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: status == 'pending'
                          ? AppColors.expense
                          : const Color(0xFF10B981))),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  status == 'pending'
                      ? '实付与规则应缴不一致（可能有优惠），请核对实际账单金额或用量'
                      : discount > 0
                          ? '已含优惠 $discount 元'
                          : '',
                  style: TextStyle(
                      fontSize: 11, color: AppPalette.textSecondary(context)),
                ),
              ),
            ]),
            Divider(height: 22, color: AppPalette.divider(context)),
            Text('实际账单金额（账单上应缴金额；优惠 = 该金额 − 实付，自动计算）',
                style: TextStyle(
                    fontSize: 12, color: AppPalette.textSecondary(context))),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _actualCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      isDense: true, hintText: '0.00'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppPalette.onPrimary(context)),
                onPressed: () => _save(actual: _actualCtrl.text),
                child: const Text('保存金额'),
              ),
            ]),
            const SizedBox(height: 12),
            Text('用量修正（按实际填写后自动重算应缴）',
                style: TextStyle(
                    fontSize: 12, color: AppPalette.textSecondary(context))),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _usageCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(isDense: true, hintText: '实际用量'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _save(usage: _usageCtrl.text),
                child: const Text('保存用量'),
              ),
            ]),
            if (flows.isNotEmpty) ...[
              Divider(height: 22, color: AppPalette.divider(context)),
              Text('关联流水（${flows.length}笔）',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final f in flows) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Text('${_d10(f['flow_time'] as String?)}  ',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppPalette.textSecondary(context))),
                    Expanded(
                      child: Text('${f['description'] ?? ''}',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                        '¥${fmtMoney2((f['amount'] as num?)?.toDouble() ?? 0)}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ],
            Divider(height: 24, color: AppPalette.divider(context)),
            Row(children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.expense),
                onPressed: () => _delete(),
                child: const Text('删除此账单'),
              ),
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$k  ',
              style: TextStyle(
                  fontSize: 12, color: AppPalette.textSecondary(context))),
          Text(v,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _kvColor(String k, String v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$k  ',
              style: TextStyle(
                  fontSize: 12, color: AppPalette.textSecondary(context))),
          Text(v,
              style:
                  TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c)),
        ]),
      );

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账单'),
        content: Text('删除这张账单（${_sel['bill_start']}~${_sel['bill_end']}）？关联流水不会删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(localApiProvider)
          .deleteUtilityRecord((_sel['id'] as num).toInt());
      toast('已删除');
      if (mounted) widget.onChanged();
    } catch (e) {
      toast('删除失败：$e');
    }
  }

  Future<void> _save({String? actual, String? usage}) async {
    final payload = <String, dynamic>{};
    if (actual != null && actual.trim().isNotEmpty) {
      final v = double.tryParse(actual.trim());
      if (v == null || v < 0) {
        toast('金额格式不对');
        return;
      }
      final paid = (_sel['paid'] as num?)?.toDouble() ?? 0;
      if (v + 0.005 < paid) {
        toast('实际账单金额不能小于实付合计 ¥${paid.toStringAsFixed(2)}（无优惠时填实付金额本身）');
        return;
      }
      // 优惠 = 实际账单金额 − 实付合计（服务端按 实付+优惠 反推用量并校验，保证计算正确）
      payload['discount'] = ((v - paid) * 100).roundToDouble() / 100;
    }
    if (usage != null && usage.trim().isNotEmpty) {
      final v = double.tryParse(usage.trim());
      if (v == null) {
        toast('用量格式不对');
        return;
      }
      payload['usage'] = v;
    }
    if (payload.isEmpty) {
      toast('没有可保存的内容');
      return;
    }
    try {
      await ref.read(localApiProvider).saveUtilityRecord(
          (_sel['id'] as num).toInt(),
          discount: payload['discount'] as double?,
          usage: payload['usage'] as double?);
      toast('已保存');
      if (mounted) widget.onChanged();
    } catch (e) {
      toast('保存失败：$e');
    }
  }
}
