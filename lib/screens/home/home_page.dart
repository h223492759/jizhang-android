import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/core/owner_color.dart';
import 'package:jizhang_android/core/category_icon.dart';
import 'package:jizhang_android/components/flow_row.dart';
import 'package:jizhang_android/components/simple_date_picker.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/bills/bills_page.dart';
import 'package:jizhang_android/screens/budget/budget_page.dart';
import 'package:jizhang_android/screens/assets/assets_page.dart';
import 'package:jizhang_android/screens/me/me_page.dart';
import 'package:jizhang_android/screens/record/record_page.dart';
import 'package:jizhang_android/screens/record/flow_detail_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late DateTime _month;
  Overview? _overview;
  List<Flow> _flows = [];
  List<Category> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month);
    ref.listenManual(dataVersionProvider, (_, __) => _load());
    _load();
  }

  String _rangeStart() => DateFormat('yyyy-MM-01').format(_month);
  String _rangeEnd() {
    final next = DateTime(_month.year, _month.month + 1, 1).subtract(const Duration(days: 1));
    return DateFormat('yyyy-MM-dd').format(next);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final ov = await api.getOverview(start: _rangeStart(), end: _rangeEnd());
      final fp = await api.getFlows(start: _rangeStart(), end: _rangeEnd(), pageSize: 500);
      final cats = await api.getCategories();
      if (mounted) {
        setState(() {
          _overview = ov;
          _flows = fp.list;
          _cats = cats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(e.toString().replaceFirst('ApiException: ', ''));
      }
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _YearMonthPicker(initial: _month),
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month));
      _load();
    }
  }

  Map<String, String> get _iconMap => buildCatIconMap(_cats);

  Future<void> _update(Flow f, Map<String, dynamic> body) async {
    try {
      await ref.read(apiProvider).updateFlow(f.id, body);
      ref.read(dataVersionProvider.notifier).state++;
      toast('已更新');
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  // ============ 顶部第一区域：黄底，日期 + 支出 + 收入，高度与第二区域接近 ============
  // 顶部 SafeArea 留出手机状态栏（信号/WIFI）的高度
  Widget _headerRegion() {
    final ov = _overview;
    return Container(
      color: AppColors.primary,
      child: SafeArea(
        bottom: false,
        top: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: _pickMonth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_month.year}',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    Text('${_month.month}月',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 28),
              _headStat('支出', ov?.expense ?? 0, AppColors.expense),
              _headStat('收入', ov?.income ?? 0, AppColors.income),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headStat(String label, double v, Color c) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(fmtMoney(v),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c)),
          ],
        ),
      );

  // ============ 第二区域：5 个图标不用圆形底色，压缩高度 ============
  Widget _quickModules() {
    final items = [
      ('账单', Icons.receipt_long, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BillsPage()))),
      ('预算', Icons.savings, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetPage()))),
      ('存款目标', Icons.flag, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AssetsPage(initialTab: 0)))),
      ('分类钱包', Icons.account_balance_wallet, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AssetsPage(initialTab: 1)))),
      ('更多', Icons.grid_view, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MePage()))),
    ];
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: items
              .map((e) => InkWell(
                    onTap: e.$3,
                    child: Column(
                      children: [
                        Icon(e.$2, color: AppColors.primaryDark, size: 24),
                        const SizedBox(height: 4),
                        Text(e.$1, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _flowList(Map<String, String> overrides, User? user) {
    if (_flows.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(40), child: Center(child: Text('本月暂无记录'))),
      );
    }
    final widgets = buildGroupedFlows(
      flows: _flows,
      tileBuilder: (f) => compactFlowTile(
        f: f,
        iconBg: ownerColorFor(f, overrides, user),
        iconChar: catIconOf(_iconMap, f.category),
        onIconTap: () => _editCategory(f),
        onNameTap: () => _editName(f),
        onAmountTap: () => _editAmount(f),
        onLongPress: () => _showFlowMenu(f),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FlowDetailPage(flow: f)),
        ),
      ),
    );
    return SliverList(delegate: SliverChildListDelegate(widgets));
  }

  // ============ 长按弹窗 ============
  Future<void> _showFlowMenu(Flow f) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _menuItem('删除', Icons.delete_outline, AppColors.expense, 'delete'),
              _menuItem('修改', Icons.edit_outlined, AppColors.text, 'edit'),
              _menuItem('更换归属人', Icons.swap_horiz, AppColors.text, 'owner'),
              _menuItem('查看明细', Icons.visibility_outlined, AppColors.text, 'detail'),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认删除'),
          content: const Text('删除后不可恢复，确定删除这条明细吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: AppColors.expense)),
            ),
          ],
        ),
      );
      if (ok == true) {
        try {
          await ref.read(apiProvider).deleteFlow(f.id);
          ref.read(dataVersionProvider.notifier).state++;
          toast('已删除');
        } catch (e) {
          toast(e.toString().replaceFirst('ApiException: ', ''));
        }
      }
    } else if (action == 'edit') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RecordPage(initialFlow: f)),
      );
    } else if (action == 'owner') {
      if (!mounted) return;
      _changeOwner(f);
    } else if (action == 'detail') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FlowDetailPage(flow: f)),
      );
    }
  }

  Future<void> _changeOwner(Flow f) async {
    final owners = _flows.map((e) => e.attribution).where((a) => a.isNotEmpty).toSet().toList();
    final ctrl = TextEditingController(text: f.attribution);
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更换归属人'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (owners.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: owners
                    .map((o) => ActionChip(
                          label: Text(o),
                          backgroundColor: Colors.grey.shade200,
                          onPressed: () => Navigator.pop(ctx, o),
                        ))
                    .toList(),
              ),
            if (owners.isNotEmpty) const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: '归属人名称',
                hintText: '输入或选择归属人',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (picked == null || picked.isEmpty) return;
    _update(f, {'attribution': picked});
  }

  Widget _menuItem(String label, IconData icon, Color color, String value) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      onTap: () => Navigator.pop(context, value),
    );
  }

  // ============ 点图标改分类 ============
  Future<void> _editCategory(Flow f) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CategoryPickerSheet(cats: _cats, type: f.type),
    );
    if (name != null && name.isNotEmpty) {
      _update(f, {'category': name});
    }
  }

  // ============ 点名称改名 ============
  Future<void> _editName(Flow f) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _NameEditorSheet(flow: f),
    );
    if (name != null && name.isNotEmpty) {
      _update(f, {'description': name});
    }
  }

  // ============ 点金额改金额 + 日期 ============
  Future<void> _editAmount(Flow f) async {
    final res = await showModalBottomSheet<_AmountResult>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AmountEditorSheet(flow: f),
    );
    if (res != null) {
      _update(f, {'amount': res.amount, 'flow_time': res.ymd});
    }
  }

  @override
  Widget build(BuildContext context) {
    final overrides = ref.watch(ownerColorsProvider);
    final user = ref.watch(sessionProvider).user;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _headerRegion()),
          SliverToBoxAdapter(child: _quickModules()),
          _loading
              ? const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())))
              : _flowList(overrides, user),
        ],
      ),
    );
  }
}

class _YearMonthPicker extends StatefulWidget {
  final DateTime initial;
  const _YearMonthPicker({required this.initial});
  @override
  State<_YearMonthPicker> createState() => _YearMonthPickerState();
}

class _YearMonthPickerState extends State<_YearMonthPicker> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year;
    _month = widget.initial.month;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _year--),
                ),
                Expanded(
                  child: Text(
                    '$_year年',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _year++),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              childAspectRatio: 1.4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: List.generate(12, (i) {
                final m = i + 1;
                final sel = _month == m;
                return InkWell(
                  onTap: () => Navigator.pop(context, DateTime(_year, m)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$m月',
                      style: TextStyle(
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        color: sel ? AppColors.text : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPickerSheet extends ConsumerStatefulWidget {
  final List<Category> cats;
  final String type;
  const _CategoryPickerSheet({required this.cats, required this.type});

  @override
  ConsumerState<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends ConsumerState<_CategoryPickerSheet> {
  @override
  Widget build(BuildContext context) {
    final cats = widget.cats.where((c) => c.type == widget.type).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('选择分类', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 1.05,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: cats.length,
                itemBuilder: (ctx, i) {
                  final c = cats[i];
                  // 点击任意分类即直接落库并关闭弹窗（无需再点"确定"）
                  return InkWell(
                    onTap: () => Navigator.pop(context, c.name),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(10),
                          child: Text(c.icon, style: const TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(height: 4),
                        Text(c.name,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _NameEditorSheet extends ConsumerStatefulWidget {
  final Flow flow;
  const _NameEditorSheet({required this.flow});

  @override
  ConsumerState<_NameEditorSheet> createState() => _NameEditorSheetState();
}

class _NameEditorSheetState extends ConsumerState<_NameEditorSheet> {
  late final TextEditingController _name;
  PresetsData _presets = PresetsData(presets: [], frequent: [], recent: []);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.flow.description);
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    try {
      _presets = await ref.read(apiProvider).getPresets(type: widget.flow.type, limit: 12);
    } catch (_) {
      _presets = PresetsData(presets: [], frequent: [], recent: []);
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chips = <PresetName>[
      ..._presets.presets,
      ..._presets.frequent,
      ..._presets.recent,
    ];
    final unique = <String, PresetName>{};
    for (final p in chips.where((p) => p.name.isNotEmpty)) {
      unique.putIfAbsent(p.name, () => p);
    }
    final display = unique.values.take(10).toList();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('修改名称', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '请输入名称',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          if (_loaded && display.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('常用名称', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: display
                    .map((p) => Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(p.name, style: const TextStyle(fontSize: 12)),
                            backgroundColor: Colors.grey.shade200,
                            side: BorderSide.none,
                            onPressed: () => _name.text = p.name,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _name.text.trim()),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AmountResult {
  final double amount;
  final String ymd;
  _AmountResult(this.amount, this.ymd);
}

class _AmountEditorSheet extends ConsumerStatefulWidget {
  final Flow flow;
  const _AmountEditorSheet({required this.flow});

  @override
  ConsumerState<_AmountEditorSheet> createState() => _AmountEditorSheetState();
}

class _AmountEditorSheetState extends ConsumerState<_AmountEditorSheet> {
  late String _expression;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _expression = _formatComputed(widget.flow.amount);
    _date = parseYmd(datePart(widget.flow.flowTime));
  }

  bool get _hasOperator => _expression.contains('+') || _expression.contains('-');

  double? _compute(String expr) {
    if (expr.isEmpty) return null;
    try {
      final tokens = <String>[];
      int i = 0;
      while (i < expr.length) {
        if (expr[i] == '+' || expr[i] == '-') {
          tokens.add(expr[i]);
          i++;
        } else {
          int j = i;
          while (j < expr.length && expr[j] != '+' && expr[j] != '-') j++;
          tokens.add(expr.substring(i, j));
          i = j;
        }
      }
      double result = 0;
      String op = '+';
      for (final t in tokens) {
        if (t == '+' || t == '-') {
          op = t;
        } else if (t.isNotEmpty) {
          final v = double.tryParse(t);
          if (v == null) return null;
          result = op == '+' ? result + v : result - v;
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  double? get _computedAmount => _compute(_expression);

  void _tapDigit(String d) {
    if (d == '.') {
      final lastOp = _expression.lastIndexOf(RegExp(r'[+-]'));
      final current = lastOp == -1 ? _expression : _expression.substring(lastOp + 1);
      if (current.contains('.')) return;
      if (current.isEmpty) {
        setState(() => _expression += '0.');
        return;
      }
    }
    if (_expression == '0' && d != '.') {
      setState(() => _expression = d);
      return;
    }
    if (_expression.length >= 12) return;
    setState(() => _expression += d);
  }

  void _tapOperator(String op) {
    if (_expression.isEmpty) return;
    final last = _expression[_expression.length - 1];
    if (last == '+' || last == '-') {
      setState(() => _expression = _expression.substring(0, _expression.length - 1) + op);
      return;
    }
    if (_hasOperator) {
      final val = _computedAmount;
      if (val == null) return;
      setState(() => _expression = '${_formatComputed(val)}$op');
      return;
    }
    setState(() => _expression += op);
  }

  void _backspace() {
    if (_expression.isNotEmpty) {
      setState(() => _expression = _expression.substring(0, _expression.length - 1));
    }
  }

  void _clearAll() {
    if (_expression.isNotEmpty) {
      setState(() => _expression = '');
    }
  }

  String _formatComputed(double v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Future<void> _pickDate() async {
    final picked = await pickSimpleDate(
      context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    var expr = _expression;
    if (expr.isNotEmpty) {
      final last = expr[expr.length - 1];
      if (last == '+' || last == '-') expr = expr.substring(0, expr.length - 1);
    }
    final amt = expr.contains('+') || expr.contains('-')
        ? _compute(expr)
        : double.tryParse(expr);
    if (amt == null || amt <= 0) {
      toast('请输入金额');
      return;
    }
    Navigator.pop(context, _AmountResult(amt, ymd(_date)));
  }

  @override
  Widget build(BuildContext context) {
    final display = _expression.isEmpty ? '0' : _expression;
    final rows = [
      ['7', '8', '9', 'date'],
      ['4', '5', '6', 'back'],
      ['1', '2', '3', '-'],
      ['.', '0', 'del', 'save'],
    ];
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 0,
        right: 0,
        top: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            color: AppColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('¥ $display',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.text)),
                if (_hasOperator && _computedAmount != null)
                  Text('= ${_formatComputed(_computedAmount!)}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          SizedBox(
            height: 260,
            child: Column(
              children: rows
                  .map((row) => Expanded(
                        child: Row(
                          children: row.map((k) => Expanded(child: _numKey(k))).toList(),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numKey(String key) {
    String label;
    VoidCallback? onTap;
    bool primary = false;
    switch (key) {
      case 'date':
        label = '${_date.month}/${_date.day}';
        onTap = _pickDate;
        break;
      case 'back':
        label = '«';
        onTap = _backspace;
        break;
      case '-':
        label = '-';
        onTap = () => _tapOperator('-');
        break;
      case 'del':
        label = '删除';
        onTap = _clearAll;
        break;
      case 'save':
        label = '保存';
        primary = true;
        onTap = _save;
        break;
      default:
        label = key;
        onTap = () => _tapDigit(key);
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(0.5),
        decoration: BoxDecoration(
          color: primary ? AppColors.primaryDark : Colors.white,
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: primary ? 18 : 20,
                  fontWeight: FontWeight.bold,
                  color: primary ? Colors.white : AppColors.text)),
        ),
      ),
    );
  }
}
