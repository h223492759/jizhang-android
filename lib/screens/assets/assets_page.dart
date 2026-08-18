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

  Future<bool> _confirm(String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SizedBox(),
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
        onPressed: _loading ? null : (_tab.index == 0 ? () => _showItemDialog() : _addWallet),
        child: const Icon(Icons.add),
      ),
    );
  }

  // ---------------- 存款目标 ----------------
  Widget _savingsView() {
    final s = _sav;
    if (s == null) return const SizedBox();
    final hasTarget = s.target > 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 净资产 + 目标
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('当前净资产', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('¥${fmtMoney(s.net)}',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: s.net >= 0 ? AppColors.income : AppColors.expense)),
                        const SizedBox(height: 6),
                        Text('资产 ${fmtMoney(s.asset)}｜负债 ${fmtMoney(s.liability)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (hasTarget)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('存款目标', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('¥${fmtMoney(s.target)}',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(s.remaining > 0 ? '还差 ¥${fmtMoney(s.remaining)}' : '已超 ¥${fmtMoney(-s.remaining)}',
                              style: TextStyle(fontSize: 12, color: s.remaining > 0 ? AppColors.expense : AppColors.income)),
                        ],
                      ),
                    ),
                ],
              ),
              if (hasTarget) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: (s.percent / 100).clamp(0.0, 1.0),
                  minHeight: 12,
                  backgroundColor: AppColors.background,
                  valueColor: AlwaysStoppedAnimation(s.net >= s.target ? AppColors.income : AppColors.primaryDark),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Text('已达成 ${s.percent}%',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ]),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('还没有设定目标，点右侧「修改目标」设定，例如 100 万。',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton(onPressed: _setGoal, child: const Text('修改目标')),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _updateAssets,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.text,
                    ),
                    child: const Text('更新资产和负债'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // 资金细则
        Row(children: [
          const Text('资金细则', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _showItemDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新增细则'),
          ),
        ]),
        const SizedBox(height: 10),
        _itemGrid(s.items, false),
        if (s.expiredItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('已失效（不计入净资产，点「改」可延长或取消失效日期）',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          _itemGrid(s.expiredItems, true),
        ],
        // 历史柱状图（横向：最新月在最上）
        if (s.months.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text('历史净资产（每月取该月最后一次更新）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          _historyBarChart(s),
        ],
        // 历史记录
        if (s.months.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text('历史记录（点「改」可像「更新资产」一样调整该月，点「删」删除该月）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          _historyList(s),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _itemGrid(List<SavingsItem> items, bool expired) {
    if (items.isEmpty) {
      return Text(expired ? '无' : '还没有资金细则。点「新增细则」把现金、微信余额、信用卡账单等逐项加进来。',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13));
    }
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.35,
      children: items.map((it) => _itemTile(it, expired)).toList(),
    );
  }

  Widget _itemTile(SavingsItem it, bool expired) {
    final color = it.isLiability ? AppColors.expense : AppColors.income;
    return Card(
      color: expired ? Colors.grey[100] : Colors.white,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SavingsItemDetailPage(item: it)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(it.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(it.isLiability ? '负债 −' : '资产 +',
                      style: TextStyle(fontSize: 11, color: color)),
                ),
              ]),
              const SizedBox(height: 6),
              Text('¥${fmtMoney(it.amount)}',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: color)),
              if (it.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(it.note, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              if (it.asOf.isNotEmpty || it.asOfEnd.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    it.asOfEnd.isNotEmpty ? '失效 ${it.asOfEnd}' : '生效 ${it.asOf}',
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  ),
                ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => _showItemDialog(it), child: const Text('改')),
                  TextButton(
                    onPressed: () => _deleteItem(it),
                    child: const Text('删', style: TextStyle(color: AppColors.expense)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyBarChart(SavingsOverview s) {
    final list = [...s.months].reversed.toList(); // 最新月在上
    double maxAbs = 0;
    for (final m in list) maxAbs = maxAbs < m.net.abs() ? m.net.abs() : maxAbs;
    if (maxAbs <= 0) maxAbs = 1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: list.map((m) {
          final frac = (m.net.abs() / maxAbs).clamp(0.02, 1.0);
          final c = m.net < 0
              ? AppColors.expense
              : (s.target > 0 && m.net >= s.target ? AppColors.income : AppColors.primaryDark);
          final ym = m.ymd.length >= 7 ? m.ymd.substring(0, 7) : m.ymd;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 52, child: Text(ym, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: frac,
                  child: Container(
                    height: 18,
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 96,
                child: Text('¥${fmtMoney(m.net)}',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                        color: m.net >= 0 ? AppColors.income : AppColors.expense)),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _historyList(SavingsOverview s) {
    final list = [...s.months].reversed.toList();
    final hasTarget = s.target > 0;
    return Column(
      children: list.map((m) {
        final ym = m.ymd.length >= 7 ? m.ymd.substring(0, 7) : m.ymd;
        final gap = s.target - m.net;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ym, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(m.ymd, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      Text('操作人：${m.opUser.isNotEmpty ? m.opUser : '—'}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('资产 ¥${fmtMoney(m.asset)}', style: const TextStyle(fontSize: 12)),
                    Text('负债 ¥${fmtMoney(m.liability)}', style: const TextStyle(fontSize: 12, color: AppColors.expense)),
                    Text('净资产 ¥${fmtMoney(m.net)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                            color: m.net >= 0 ? AppColors.income : AppColors.expense)),
                  ],
                ),
                if (hasTarget)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('距目标', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        Text(gap > 0 ? '差 ¥${fmtMoney(gap)}' : '超 ¥${fmtMoney(-gap)}',
                            style: TextStyle(fontSize: 12, color: gap > 0 ? AppColors.expense : AppColors.income)),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    children: [
                      TextButton(onPressed: () => _editHistory(m), child: const Text('改')),
                      TextButton(
                        onPressed: () => _delHistory(m),
                        child: const Text('删', style: TextStyle(color: AppColors.expense)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // 新增 / 编辑 资金细则
  Future<void> _showItemDialog([SavingsItem? it]) async {
    final isEdit = it != null;
    final name = TextEditingController(text: it?.name ?? '');
    final amount = TextEditingController(text: it != null ? it.amount.toString() : '');
    bool liability = it?.isLiability ?? false;
    final asOf = TextEditingController(text: it?.asOf ?? '');
    final asOfEnd = TextEditingController(text: it?.asOfEnd ?? '');
    final note = TextEditingController(text: it?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(isEdit ? '编辑资金细则' : '新增资金细则'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
                TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '金额（正数）')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('计入方式：负债'),
                  value: liability,
                  onChanged: (v) => set(() => liability = v),
                ),
                TextField(controller: asOf, decoration: const InputDecoration(labelText: '生效日期（可选，如20260101）')),
                TextField(controller: asOfEnd, decoration: const InputDecoration(labelText: '失效日期（可选）')),
                TextField(controller: note, decoration: const InputDecoration(labelText: '备注（可选）')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amount.text.trim());
    if (name.text.trim().isEmpty || amt == null) {
      toast('请填写名称和金额');
      return;
    }
    try {
      if (isEdit) {
        await ref.read(apiProvider).updateSavingsItem(
          id: it!.id,
          name: name.text.trim(),
          amount: amt,
          sign: liability ? -1 : 1,
          asOf: asOf.text.trim(),
          asOfEnd: asOfEnd.text.trim(),
          note: note.text.trim(),
        );
      } else {
        await ref.read(apiProvider).addSavingsItem(
          name: name.text.trim(),
          amount: amt,
          sign: liability ? -1 : 1,
          asOf: asOf.text.trim(),
          asOfEnd: asOfEnd.text.trim(),
          note: note.text.trim(),
        );
      }
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  Future<void> _deleteItem(SavingsItem it) async {
    if (!await _confirm('删除资金细则「${it.name}」？')) return;
    try {
      await ref.read(apiProvider).deleteSavingsItem(it.id);
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  Future<void> _setGoal() async {
    final ctrl = TextEditingController(text: _sav?.target.toString());
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改存款目标'),
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

  // 更新资产和负债（批量填金额）
  Future<void> _updateAssets() async {
    final s = _sav;
    if (s == null) return;
    if (s.items.isEmpty) {
      toast('请先新增资金细则');
      return;
    }
    final ctrls = {for (final it in s.items) it.id: TextEditingController(text: it.amount.toString())};
    final date = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, set) {
          double asset = 0, liab = 0;
          for (final it in s.items) {
            final v = double.tryParse(ctrls[it.id]!.text.trim()) ?? 0;
            if (it.isLiability) liab += v; else asset += v;
          }
          return AlertDialog(
            title: const Text('更新资产和负债'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: date, decoration: const InputDecoration(labelText: '记录日期（默认今天，可选历史日期回填）')),
                  const Divider(),
                  ...s.items.map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text('${it.name}${it.isLiability ? '（负债）' : '（资产）'}')),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: ctrls[it.id],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: '金额'),
                        ),
                      ),
                    ]),
                  )),
                  const Divider(),
                  Text('资产合计 ¥${fmtMoney(asset)}', style: const TextStyle(fontSize: 13)),
                  Text('负债合计 ¥${fmtMoney(liab)}', style: const TextStyle(fontSize: 13, color: AppColors.expense)),
                  Text('净资产 ¥${fmtMoney(asset - liab)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final items = s.items.map((it) => {
      'id': it.id,
      'amount': double.tryParse(ctrls[it.id]!.text.trim()) ?? 0,
    }).toList();
    try {
      await ref.read(apiProvider).bulkUpdateSavingsItems(items: items, ymd: date.text.trim());
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  // 历史记录 改 / 删
  Future<void> _editHistory(SavingsMonth m) async {
    final asset = TextEditingController(text: m.asset.toString());
    final liability = TextEditingController(text: m.liability.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('修改 ${m.ymd} 的历史'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: asset, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '资产')),
            TextField(controller: liability, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '负债')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final a = double.tryParse(asset.text.trim());
    final l = double.tryParse(liability.text.trim());
    if (a == null || a < 0 || l == null || l < 0) {
      toast('金额需为正数');
      return;
    }
    try {
      await ref.read(apiProvider).updateSavingsHistory(ymd: m.ymd, asset: a, liability: l);
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  Future<void> _delHistory(SavingsMonth m) async {
    if (!await _confirm('删除 ${m.ymd} 的历史记录？')) return;
    try {
      await ref.read(apiProvider).deleteSavingsHistory(m.ymd);
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
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
                    ? Text('关联「${it.linkCategory}」自 ${it.linkFrom} · ${it.count}笔')
                    : Text('${it.count}笔资金记录'),
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
        if (w.wallets.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('还没有分类钱包。点右下角「+」新增养娃、买房等专项金，每月存一笔即可（记录带日期、金额与操作人）。',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        const SizedBox(height: 24),
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
