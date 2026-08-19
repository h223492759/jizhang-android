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
import 'package:jizhang_android/core/local_first_api.dart';

/// 某个归属人（账户）的流水明细：
/// - 顶部 3 行固定：月/年模式 + 年月选择器 + 总额/平均值
/// - 下方可滚动：按金额/按时间排行榜切换 + 流水明细（左图标按归属底色 + 右三行）
/// - 列表默认按金额降序
class OwnerFlowPage extends ConsumerStatefulWidget {
  final String attribution;
  final String title;
  final String start;
  final String end;
  final bool isSelf;
  /// 'expense' / 'income' / null（两种都显示）。从图表页带过来时通常取图表当前 type。
  final String? type;
  /// 进入时默认选中的 period（年月）；不传则按 start 解析。
  final DateTime? initialPeriod;
  /// 可选：限定到某个分类（分类详情页点归属人时传，实现"该分类+该归属人+当期"过滤）。
  final String? category;
  /// 进入时默认的模式（月/年）；不传则默认月模式。
  final bool initialYearMode;
  const OwnerFlowPage({
    super.key,
    required this.attribution,
    required this.title,
    required this.start,
    required this.end,
    this.isSelf = false,
    this.type,
    this.initialPeriod,
    this.category,
    this.initialYearMode = false,
  });

  @override
  ConsumerState<OwnerFlowPage> createState() => _OwnerFlowPageState();
}

class _OwnerFlowPageState extends ConsumerState<OwnerFlowPage> {
  late DateTime _period;
  late String _typeFilter; // expense | income | all
  bool _yearMode = false;
  List<Flow> _flows = [];
  List<Category> _cats = [];
  bool _loading = true;
  String _sortBy = 'amount'; // amount | time
  final ScrollController _periodScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.type ?? 'all';
    _yearMode = widget.initialYearMode;
    final init = widget.initialPeriod;
    if (init != null) {
      _period = DateTime(init.year, init.month);
    } else {
      try {
        _period = DateTime.parse(widget.start);
      } catch (_) {
        final n = DateTime.now();
        _period = DateTime(n.year, n.month);
      }
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
      final api = ref.read(localApiProvider);
      final fp = await api.getFlows(
        start: _start(),
        end: _end(),
        pageSize: 2000,
        category: widget.category,
      );
      final cats = await api.getCategories();
      var matched = fp.list.where((f) => f.attribution == widget.attribution).toList();
      if (_typeFilter != 'all') {
        matched = matched.where((f) => f.type == _typeFilter).toList();
      }
      if (mounted) {
        setState(() {
          _flows = matched;
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

  // 当前周期内（已按归属人 + type 过滤）的金额合计
  double get _periodTotal {
    if (_typeFilter == 'expense') {
      return _flows.fold(0.0, (s, f) => s + f.amount); // 已是过滤后的支出
    }
    if (_typeFilter == 'income') {
      return _flows.fold(0.0, (s, f) => s + f.amount);
    }
    final exp = _flows.where((f) => f.isExpense).fold(0.0, (s, f) => s + f.amount);
    final inc = _flows.where((f) => !f.isExpense).fold(0.0, (s, f) => s + f.amount);
    return exp + inc;
  }

  int get _daysInPeriod {
    final s = parseYmd(_start());
    final e = parseYmd(_end());
    return e.difference(s).inDays + 1;
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

  // 周期选择器（月模式：近 3 年逐月；年模式：近 4 年；未来不显示）
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
            label: label,
            year: y,
            month: 1,
            special: special,
            selected: y == _period.year));
      }
      return opts;
    }
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
          label = '$m月';
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
    return opts;
  }

  void _centerSelected() {
    final opts = _buildPeriodOpts();
    final idx = opts.indexWhere((o) => o.selected);
    if (idx < 0 || !_periodScroll.hasClients) return;
    const chipW = 64.0;
    final max = _periodScroll.position.maxScrollExtent;
    final target = (idx * (chipW + 8) - (_periodScroll.position.viewportDimension / 2 - chipW / 2))
        .clamp(0.0, max);
    _periodScroll.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeFilter == 'income' ? AppColors.income : AppColors.expense;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.category != null ? '${widget.category} · ${widget.title}' : '${widget.title}的流水')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // PIN 1a: 月/年 单选
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: _modeBar(),
                ),
                // PIN 1b: 周期选择器
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _periodSelector(),
                ),
                // PIN 2: 总额/平均值
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: _summaryRow(),
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      _rankingHeader(),
                      const SizedBox(height: 8),
                      ..._rankRows(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summaryRow() {
    final total = _periodTotal;
    final avg = _daysInPeriod > 0 ? total / _daysInPeriod : 0.0;
    final label = _typeFilter == 'income' ? '总收入' : (_typeFilter == 'expense' ? '总支出' : '合计');
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

  Widget _modeBar() {
    return Row(
      children: [
        _seg(['月', '年'], _yearMode ? 1 : 0, (i) {
          setState(() => _yearMode = i == 1);
          _load();
          WidgetsBinding.instance.addPostFrameCallback((_) => _centerSelected());
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
        const Text('流水排行', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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

  List<Widget> _rankRows() {
    final list = _sorted;
    if (list.isEmpty) {
      return [const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('暂无记录')))];
    }
    final total = _periodTotal;
    final maxVal = list.map((f) => f.amount).fold(0.0, (a, b) => b > a ? b : a);
    final iconMap = buildCatIconMap(_cats);
    final overrides = ref.watch(ownerColorsProvider);
    final user = ref.watch(sessionProvider).user;
    return list.map((f) {
      final pct = total > 0 ? f.amount / total : 0.0;
      final barPct = maxVal > 0 ? f.amount / maxVal : 0.0;
      final dt = parseYmd(datePart(f.flowTime));
      final color = f.isExpense ? AppColors.expense : AppColors.income;
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
                        Expanded(
                          child: Text(
                            '${f.description.isNotEmpty ? f.description : f.category}   ${(pct * 100).toStringAsFixed(0)}%',
                          ),
                        ),
                        Text('¥${fmtMoney(f.amount)}',
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
