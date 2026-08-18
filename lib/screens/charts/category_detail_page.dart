import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/core/owner_color.dart';
import 'package:jizhang_android/core/category_icon.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/record/flow_detail_page.dart';
import 'package:jizhang_android/screens/flows/owner_flow_page.dart';

/// 分类详情页：用于图表页「分类排行」点击进入。
/// - 顶部 3 行固定（始终可见）：
///   - 行 1：月/年 模式切换
///   - 行 2：年月滑动选择器（跨月/跨年对比）
///   - 行 3：总支出/总收入 + 平均值
/// - 下方滚动区：本分类的归属人横向占比条 + 支出排行榜（按金额/按时间）+ 流水明细
class CategoryDetailPage extends ConsumerStatefulWidget {
  final String category;
  final String type;
  final String start;
  final String end;
  /// 由图表页传入的当前选中 period（年月），用于初始化时跳到图表上选中的月/年。
  /// 不传则默认为本月。
  final DateTime? initialPeriod;
  final bool initialYearMode;
  const CategoryDetailPage({
    super.key,
    required this.category,
    required this.type,
    required this.start,
    required this.end,
    this.initialPeriod,
    this.initialYearMode = false,
  });

  @override
  ConsumerState<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends ConsumerState<CategoryDetailPage> {
  late DateTime _period;
  bool _yearMode = false;
  List<Flow> _flows = [];
  List<Category> _cats = [];
  bool _loading = true;
  String _sortBy = 'amount'; // amount | time
  final ScrollController _periodScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final init = widget.initialPeriod;
    if (init != null) {
      _period = DateTime(init.year, init.month);
      _yearMode = widget.initialYearMode;
    } else {
      final now = DateTime.now();
      _period = DateTime(now.year, now.month);
    }
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final fp = await api.getFlows(
          category: widget.category, type: widget.type, start: _start(), end: _end(), pageSize: 2000);
      final cats = await api.getCategories();
      if (mounted) {
        setState(() {
          _flows = fp.list;
          _cats = cats;
        });
      }
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerSelected();
      });
    }
  }

  List<Flow> get _sorted {
    final list = List<Flow>.from(_flows);
    if (_sortBy == 'amount') {
      list.sort((a, b) => b.amount.compareTo(a.amount));
    } else {
      list.sort((a, b) => b.flowTime.compareTo(a.flowTime));
    }
    return list;
  }

  List<_OwnerSeg> get _ownerSegs {
    final user = ref.read(sessionProvider).user;
    final map = <String, double>{};
    final sample = <String, Flow>{};
    for (final f in _flows) {
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
    final color = widget.type == 'expense' ? AppColors.expense : AppColors.income;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.category)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // PIN 1: 月/年 模式切换
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: _modeAndTypeBar(color),
                ),
                // PIN 2: 周期选择器（年/月）
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _periodSelector(),
                ),
                // PIN 3: 总支出/总收入 + 平均值
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: _summaryRow(),
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                // SCROLLABLE: 归属人 + 排行榜 + 流水明细
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      _ownerProportion(color),
                      const SizedBox(height: 16),
                      _rankingHeader(),
                      const SizedBox(height: 8),
                      ..._rankRows(color),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summaryRow() {
    // 在当前周期 + 当前分类 + 当前类型下，所有流水的合计
    double total = 0;
    for (final f in _flows) {
      total += f.amount;
    }
    final days = _daysInPeriod;
    final avg = days > 0 ? total / days : 0.0;
    final label = widget.type == 'expense' ? '总支出' : '总收入';
    return Row(
      children: [
        Text('$label：¥${fmtMoney(total)}',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const Spacer(),
        Text('平均值：¥${fmtMoney(avg)}',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }

  int get _daysInPeriod {
    final s = parseYmd(_start());
    final e = parseYmd(_end());
    return e.difference(s).inDays + 1;
  }

  Widget _modeAndTypeBar(Color color) {
    return Row(
      children: [
        _seg(['月', '年'], _yearMode ? 1 : 0, (i) {
          setState(() => _yearMode = i == 1);
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
        opts.add(_PeriodOpt(label: label, year: y, month: 1, special: special, selected: y == _period.year));
      }
    } else {
      final startY = now.year - 2;
      for (int y = startY; y <= now.year; y++) {
        final maxM = y == now.year ? now.month : 12;
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
    if (idx < 0 || !_periodScroll.hasClients) return;
    const chipW = 64.0;
    final max = _periodScroll.position.maxScrollExtent;
    // 选中项无论是否"special"，一律居中。
    final target = (idx * (chipW + 8) - (_periodScroll.position.viewportDimension / 2 - chipW / 2))
        .clamp(0.0, max);
    // 用 jumpTo 取代 animateTo，避免「先左移再居中」这种先飘再对位的视觉抖动。
    _periodScroll.jumpTo(target);
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

  Widget _rankingHeader() {
    return Row(
      children: [
        const Text('支出排行榜', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const Spacer(),
        _toggleChip('按金额', _sortBy == 'amount', () => setState(() => _sortBy = 'amount')),
        const SizedBox(width: 8),
        _toggleChip('按时间', _sortBy == 'time', () => setState(() => _sortBy = 'time')),
      ],
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, style: TextStyle(color: active ? AppColors.text : AppColors.textSecondary)),
      ),
    );
  }

  List<Widget> _rankRows(Color color) {
    final list = _sorted;
    if (list.isEmpty) return [const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('暂无记录')))];
    final total = list.fold(0.0, (s, f) => s + f.amount);
    final maxVal = list.map((f) => f.amount).fold(0.0, (a, b) => b > a ? b : a);
    final iconMap = buildCatIconMap(_cats);
    final overrides = ref.watch(ownerColorsProvider);
    final user = ref.watch(sessionProvider).user;
    return list.map((f) {
      final pct = total > 0 ? f.amount / total : 0.0;
      final barPct = maxVal > 0 ? f.amount / maxVal : 0.0;
      final dt = parseYmd(datePart(f.flowTime));
      return InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FlowDetailPage(flow: f)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: ownerColorFor(f, overrides, user),
                child: Text(catIconOf(iconMap, f.category), style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('${f.description.isNotEmpty ? f.description : f.category}   ${(pct * 100).toStringAsFixed(0)}%')),
                        Text('¥${fmtMoney(f.amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                    const SizedBox(height: 4),
                    Text('${ymd(dt)} ${weekdayCn(dt)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // 归属人占比（本分类内），格式同图表页第 4 条
  Widget _ownerProportion(Color color) {
    final segs = _ownerSegs;
    final total = segs.fold(0.0, (s, e) => s + e.value);
    if (total <= 0) return const SizedBox.shrink();
    final self = segs.where((s) => s.isSelf).toList();
    final others = segs.where((s) => !s.isSelf).toList();
    final selfVal = self.fold(0.0, (s, e) => s + e.value);
    final otherVal = others.fold(0.0, (s, e) => s + e.value);
    final leftSeg = self.isNotEmpty ? self.first : segs.first;
    final rightSeg = others.isNotEmpty ? others.first : (segs.length > 1 ? segs[1] : segs.first);

    String labelOf(_OwnerSeg s) => s.isSelf ? '我' : (s.attr.isEmpty ? '我' : s.attr);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (segs.length == 1) ...[
            Text(
              '${labelOf(segs.first)}  ¥${fmtMoney(segs.first.value)}  ${(segs.first.value / total * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${labelOf(leftSeg)}  ¥${fmtMoney(leftSeg.value)}  ${(leftSeg.value / total * 100).toStringAsFixed(0)}%',
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
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(6)),
              child: Row(
                children: [
                  if (self.isNotEmpty)
                    Expanded(
                      flex: selfVal.round(),
                      child: GestureDetector(
                        onTap: () => _openOwner(self.first, isSelf: true),
                        child: Container(color: Colors.grey.shade100),
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
          ),
        ],
      ),
    );
  }

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
          type: widget.type, // 与分类详情页当前 type 同步
          initialPeriod: _period,
          category: widget.category, // 限定到当前分类：该分类 + 该归属人 + 当期
        ),
      ),
    );
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
