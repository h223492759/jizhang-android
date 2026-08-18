import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';

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
      _sav = sav;
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
          tabs: const [Tab(text: '存款目标'), Tab(text: '资金细则')],
          indicatorColor: AppColors.text,
          labelColor: AppColors.text,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [_savingsView(), _fundsView()],
            ),
      floatingActionButton: _tab.index == 1
          ? FloatingActionButton(
              onPressed: _loading ? null : () => _showItemDialog(),
              child: const Icon(Icons.add),
            )
          : null,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('当前净资产', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('¥${fmtMoney(s.net)}',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: s.net >= 0 ? AppColors.income : AppColors.expense)),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text('资产 ${fmtMoney(s.asset)}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const Text('｜', style: TextStyle(color: AppColors.textSecondary)),
                  Text('负债 ${fmtMoney(s.liability)}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  if (hasTarget) ...[
                    const Text('｜', style: TextStyle(color: AppColors.textSecondary)),
                    Text(
                        s.remaining > 0
                            ? '还差 ¥${fmtMoney(s.remaining)}'
                            : '已超 ¥${fmtMoney(-s.remaining)}',
                        style: TextStyle(
                            fontSize: 13,
                            color: s.remaining > 0 ? AppColors.expense : AppColors.income)),
                  ],
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
                Text('已达成 ${s.percent}% · 目标 ¥${fmtMoney(s.target)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
          const Text('历史记录（点「改」可按明细调整该月，点「删」删除该月）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          _historyList(s),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _fundsView() {
    final s = _sav;
    if (s == null) return const SizedBox();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
      childAspectRatio: 1.8,
      children: items.map((it) => _itemTile(it, expired)).toList(),
    );
  }

  Widget _itemTile(SavingsItem it, bool expired) {
    final color = it.isLiability ? AppColors.expense : AppColors.income;
    return Card(
      color: expired ? Colors.grey[100] : Colors.white,
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
    );
  }

  Widget _historyBarChart(SavingsOverview s) {
    final list = [...s.months].reversed.toList(); // 最新月在上
    double maxAbs = 0;
    for (final m in list) maxAbs = maxAbs < m.net.abs() ? m.net.abs() : maxAbs;
    if (maxAbs <= 0) maxAbs = 1;
    final hasTarget = s.target > 0;
    final targetFrac = hasTarget ? (s.target / maxAbs).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTarget)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('目标基线 ¥${fmtMoney(s.target)}（右侧为达成率 %）',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ...list.map((m) {
            final frac = (m.net.abs() / maxAbs).clamp(0.02, 1.0);
            final c = m.net < 0
                ? AppColors.expense
                : (s.target > 0 && m.net >= s.target ? AppColors.income : AppColors.primaryDark);
            final ym = m.ymd.length >= 7 ? m.ymd.substring(0, 7) : m.ymd;
            final pct = hasTarget ? (m.net / s.target * 100) : (m.net.abs() / maxAbs * 100);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(width: 52, child: Text(ym, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      final w = constraints.maxWidth;
                      return Stack(
                        children: [
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: frac,
                            child: Container(
                              height: 18,
                              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                          if (hasTarget)
                            Positioned(
                              left: targetFrac * w,
                              top: 0,
                              bottom: 0,
                              child: Container(width: 2, color: AppColors.text),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 72,
                  child: Text('${pct.toStringAsFixed(2)}%',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary)),
                ),
              ]),
            );
          }).toList(),
        ],
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ym, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('操作人：${m.opUser.isNotEmpty ? m.opUser : '—'}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text('资产 ¥${fmtMoney(m.asset)} ｜ 负债 ¥${fmtMoney(m.liability)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Text('净资产 ¥${fmtMoney(m.net)}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                              color: m.net >= 0 ? AppColors.income : AppColors.expense)),
                      if (hasTarget)
                        Text('距目标 ${gap > 0 ? '差' : '超'} ¥${fmtMoney(gap.abs())}',
                            style: TextStyle(fontSize: 12,
                                color: gap > 0 ? AppColors.expense : AppColors.income)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    TextButton(onPressed: () => _editHistory(m), child: const Text('改')),
                    TextButton(
                      onPressed: () => _delHistory(m),
                      child: const Text('删', style: TextStyle(color: AppColors.expense)),
                    ),
                  ],
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

  // 修改某月历史：按明细（逐条细则金额）调整，与网页端一致
  Future<void> _editHistory(SavingsMonth m) async {
    final ym = m.ymd.length >= 7 ? m.ymd.substring(0, 7) : m.ymd;
    Map<String, dynamic> monthData;
    try {
      monthData = await ref.read(apiProvider).getSavingsMonthItems(ym);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
      return;
    }
    final items = (monthData['items'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    if (items.isEmpty) {
      toast('该月暂无明细可编辑');
      return;
    }
    final ctrls = {
      for (final it in items)
        it['id']: TextEditingController(text: (it['amount']?.toString() ?? '0'))
    };
    final date = TextEditingController(text: (monthData['ymd'] ?? m.ymd).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, set) {
          double asset = 0, liab = 0;
          for (final it in items) {
            final v = double.tryParse(ctrls[it['id']]!.text.trim()) ?? 0;
            if ((it['sign'] ?? 1) < 0) liab += v; else asset += v;
          }
          return AlertDialog(
            title: Text('修改 $ym 的历史'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: date,
                      decoration: const InputDecoration(labelText: '记录日期（默认该月，可选历史日期回填）')),
                  const Divider(),
                  ...items.map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text('${it['name']}${(it['sign'] ?? 1) < 0 ? '（负债）' : '（资产）'}')),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: ctrls[it['id']],
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
    final body = items
        .map((it) => {
              'id': it['id'],
              'amount': double.tryParse(ctrls[it['id']]!.text.trim()) ?? 0,
            })
        .toList();
    try {
      await ref.read(apiProvider).bulkUpdateSavingsItems(
          items: body, ymd: date.text.trim(), mode: 'history');
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

  }
