import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/assets/savings_item_detail_page.dart';
import 'package:jizhang_android/screens/assets/wallet_detail_page.dart';

class AssetsPage extends ConsumerStatefulWidget {
  final int initialTab;
  const AssetsPage({super.key, this.initialTab = 0});
  @override
  ConsumerState<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends ConsumerState<AssetsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  SavingsOverview? _sav;
  WalletsData? _wallets;
  List<Category> _expenseCats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final sav = await api.getSavings();
      final wallets = await api.getWallets();
      final cats = await api.getCategories();
      _sav = sav;
      _wallets = wallets;
      _expenseCats = cats;
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('资产'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: '存款目标'), Tab(text: '分类钱包')],
          indicatorColor: AppColors.text,
          labelColor: AppColors.text,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [_savingsView(), _walletsView()],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : (_tab.index == 0 ? _addItem : _addWallet),
        child: const Icon(Icons.add),
      ),
    );
  }

  // ---------------- 存款目标 ----------------
  Widget _savingsView() {
    final s = _sav;
    if (s == null) return const SizedBox();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Row(children: [
                const Text('净资产', style: TextStyle(color: AppColors.textSecondary)),
                const Spacer(),
                TextButton(onPressed: _setGoal, child: const Text('设目标')),
              ]),
              const SizedBox(height: 4),
              Text('¥${fmtMoney(s.net)}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (s.target <= 0 ? 0.0 : s.percent / 100).clamp(0.0, 1.0),
                minHeight: 12,
                backgroundColor: AppColors.background,
                valueColor: AlwaysStoppedAnimation(AppColors.primaryDark),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Text('目标 ${fmtMoney(s.target)}', style: const TextStyle(fontSize: 12)),
                const Spacer(),
                Text('还差 ${fmtMoney(s.remaining)}', style: const TextStyle(fontSize: 12, color: AppColors.income)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Text('资产 ${fmtMoney(s.asset)}', style: const TextStyle(fontSize: 12, color: AppColors.income)),
                const Spacer(),
                Text('负债 ${fmtMoney(s.liability)}', style: const TextStyle(fontSize: 12, color: AppColors.expense)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('资金细则', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        ...s.items.map((it) => _itemCard(it)),
        if (s.expiredItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('已失效', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ...s.expiredItems.map((it) => _itemCard(it, expired: true)),
        ],
      ],
    );
  }

  Widget _itemCard(SavingsItem it, {bool expired = false}) => Card(
        color: expired ? Colors.grey[100] : Colors.white,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: it.isLiability ? AppColors.expense.withOpacity(0.12) : AppColors.income.withOpacity(0.12),
            child: Icon(it.isLiability ? Icons.arrow_downward : Icons.arrow_upward,
                color: it.isLiability ? AppColors.expense : AppColors.income),
          ),
          title: Text(it.name),
          subtitle: it.asOfEnd.isNotEmpty
              ? Text('失效于 ${it.asOfEnd}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))
              : (it.asOf.isNotEmpty ? Text('生效 ${it.asOf}') : null),
          trailing: Text('¥${fmtMoney(it.amount)}',
              style: TextStyle(
                  color: it.isLiability ? AppColors.expense : AppColors.income,
                  fontWeight: FontWeight.bold)),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SavingsItemDetailPage(item: it)),
          ),
        ),
      );

  Future<void> _setGoal() async {
    final ctrl = TextEditingController(text: _sav?.target.toString());
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置存款目标'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '目标金额', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())), child: const Text('保存')),
        ],
      ),
    );
    if (v != null) {
      try {
        await ref.read(apiProvider).setSavingsGoal(target: v);
        _load();
      } catch (e) {
        toast(e.toString().replaceFirst('ApiException: ', ''));
      }
    }
  }

  Future<void> _addItem() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    bool liability = false;
    final asOf = TextEditingController();
    final asOfEnd = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('新增资金细则'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '金额')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('计入方式：负债'),
                value: liability,
                onChanged: (v) => set(() => liability = v),
              ),
              TextField(controller: asOf, decoration: const InputDecoration(labelText: '生效日期(可选, 如20260101)')), TextField(controller: asOfEnd, decoration: const InputDecoration(labelText: '失效日期(可选)')), ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
          ],
        ),
      ),
    );
    final amt = double.tryParse(amount.text.trim());
    if (res == true && name.text.trim().isNotEmpty && amt != null) {
      try {
        await ref.read(apiProvider).addSavingsItem(
          name: name.text.trim(),
          amount: amt,
          sign: liability ? -1 : 1,
          asOf: asOf.text.trim(),
          asOfEnd: asOfEnd.text.trim(),
        );
        _load();
      } catch (e) {
        toast(e.toString().replaceFirst('ApiException: ', ''));
      }
    }
  }

  // ---------------- 分类钱包 ----------------
  Widget _walletsView() {
    final w = _wallets;
    if (w == null) return const SizedBox();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            _wcol('总余额', w.totalBalance),
            _wcol('总目标', w.totalTarget),
          ]),
        ),
        const SizedBox(height: 12),
        ...w.wallets.map((it) => Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.primarySoft, child: Text(it.icon)),
                title: Text(it.name),
                subtitle: it.linkCategory.isNotEmpty
                    ? Text('关联「${it.linkCategory}」自 ${it.linkFrom}')
                    : null,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('¥${fmtMoney(it.balance)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (it.target > 0)
                      Text('目标 ${fmtMoney(it.target)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => WalletDetailPage(wallet: it)),
                ),
              ),
            )),
      ],
    );
  }

  Widget _wcol(String l, double v) => Expanded(
        child: Column(children: [
          Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('¥${fmtMoney(v)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
      );

  Future<void> _addWallet() async {
    final name = TextEditingController();
    final target = TextEditingController();
    final linkCat = TextEditingController();
    final linkFrom = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增钱包'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
            TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '目标金额(可选)')),
            TextField(controller: linkCat, decoration: const InputDecoration(labelText: '关联分类(可选)')),
            TextField(controller: linkFrom, decoration: const InputDecoration(labelText: '关联起始日(如20260101,可选)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
        ],
      ),
    );
    if (res == true && name.text.trim().isNotEmpty) {
      try {
        await ref.read(apiProvider).addWallet(
          name: name.text.trim(),
          target: double.tryParse(target.text.trim()) ?? 0,
          linkCategory: linkCat.text.trim(),
          linkFrom: linkFrom.text.trim(),
        );
        _load();
      } catch (e) {
        toast(e.toString().replaceFirst('ApiException: ', ''));
      }
    }
  }
}
