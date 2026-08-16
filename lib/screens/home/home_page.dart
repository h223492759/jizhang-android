import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month);
    // 记一笔 / 改删后自动刷新
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
      final fp = await api.getFlows(
          start: _rangeStart(), end: _rangeEnd(), pageSize: 500);
      if (mounted) {
        setState(() {
          _overview = ov;
          _flows = fp.list;
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

  Map<String, List<Flow>> get _grouped {
    final m = <String, List<Flow>>{};
    for (final f in _flows) {
      final d = datePart(f.flowTime);
      (m[d] ??= []).add(f);
    }
    final keys = m.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (var k in keys) k: m[k]!};
  }

  @override
  Widget build(BuildContext context) {
    final ov = _overview;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.primary,
            expandedHeight: 120,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(color: AppColors.primary),
              title: InkWell(
                onTap: _pickMonth,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${_month.year}年${_month.month}月',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
              centerTitle: true,
            ),
            actions: const [],
          ),
          SliverToBoxAdapter(child: _summaryCard(ov)),
          SliverToBoxAdapter(child: _quickModules()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('明细',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          _loading
              ? const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())))
              : _flowList(),
        ],
      ),
    );
  }

  Widget _summaryCard(Overview? ov) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _stat('支出', ov?.expense ?? 0, AppColors.expense),
            _stat('收入', ov?.income ?? 0, AppColors.income),
            _stat('笔数', (ov?.count ?? 0).toDouble(), AppColors.text),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, double value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Text(fmtMoney(value), style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: items
              .map((e) => InkWell(
                    onTap: e.$3,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primarySoft,
                          child: Icon(e.$2, color: AppColors.primaryDark, size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(e.$1, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _flowList() {
    if (_flows.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(40), child: Center(child: Text('本月暂无记录'))),
      );
    }
    final grouped = _grouped;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          final entry = grouped.entries.elementAt(i);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(entry.key,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
              ...entry.value.map((f) => _flowTile(f)),
            ],
          );
        },
        childCount: grouped.length,
      ),
    );
  }

  Widget _flowTile(Flow f) {
    final expense = f.isExpense;
    return GestureDetector(
      onLongPress: () => _showFlowMenu(f),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primarySoft,
          child: Text(f.category.isNotEmpty ? f.category[0] : '·',
              style: const TextStyle(color: AppColors.primaryDark)),
        ),
        title: Text(f.category),
        subtitle: Text(f.description.isNotEmpty ? f.description : (f.attribution.isNotEmpty ? '归属：${f.attribution}' : ''),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: Text(
          '${expense ? '-' : '+'}${fmtMoney(f.amount)}',
          style: TextStyle(color: expense ? AppColors.expense : AppColors.income, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

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
    } else if (action == 'detail') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FlowDetailPage(flow: f)),
      );
    }
  }

  Widget _menuItem(String label, IconData icon, Color color, String value) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      onTap: () => Navigator.pop(context, value),
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
