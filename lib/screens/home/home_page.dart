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
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: '选择月份',
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
    return ListTile(
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
    );
  }
}
