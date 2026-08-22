import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/components/simple_date_picker.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/core/local_first_api.dart';

class WalletDetailPage extends ConsumerStatefulWidget {
  final Wallet wallet;
  const WalletDetailPage({super.key, required this.wallet});

  @override
  ConsumerState<WalletDetailPage> createState() => _WalletDetailPageState();
}

class _WalletDetailPageState extends ConsumerState<WalletDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  // 新增 / 编辑 资金记录用的本地状态
  final _amountCtr = TextEditingController();
  final _noteCtr = TextEditingController();
  String _dir = 'in';
  DateTime _txnDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtr.dispose();
    _noteCtr.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(localApiProvider).getWalletTxns(widget.wallet.id);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      // mounted 检查兜底：即使组件已 dispose，也尝试更新（防止 _loading 卡死）
      if (mounted) setState(() => _loading = false);
    }
  }

  // 默认空数据（防止 build 抛异常时显示空白）
  Map<String, dynamic> get _safeData => _data ?? const {
        'rows': <dynamic>[],
        'linkedRows': <dynamic>[],
        'balance': 0,
        'linkedSum': 0,
        'monthly': <dynamic>[],
      };
  List<_WalletTxn> get _rows {
    final list = (_safeData['rows'] as List? ?? []);
    return list.map((x) {
      try { return _WalletTxn.fromJson(x as Map<String, dynamic>); }
      catch (_) { return null; }
    }).whereType<_WalletTxn>().toList();
  }
  List<Flow> get _linked {
    final list = (_safeData['linkedRows'] as List? ?? []);
    return list.map((x) {
      try { return Flow.fromJson(x as Map<String, dynamic>); }
      catch (_) { return null; }
    }).whereType<Flow>().toList();
  }
  // 月结（服务端聚合）：不依赖历史落库，仅当月/上月实时算也正常
  List<Map<String, dynamic>> get _monthly {
    final list = (_safeData['monthly'] as List? ?? []);
    return list.map((x) {
      try { return Map<String, dynamic>.from(x as Map); }
      catch (_) { return null; }
    }).whereType<Map<String, dynamic>>().toList();
  }
  // 资金记录 + 月结 合并按日期倒序（月结穿插在手工记录之间，与网页端一致）
  List<_RowItem> get _allTxns {
    final items = <_RowItem>[];
    for (final t in _rows) {
      items.add(_RowItem(kind: 'manual', ymd: t.ymd, amount: t.amount, note: t.note, op: t.opUser, txn: t));
    }
    for (final m in _monthly) {
      items.add(_RowItem(
        kind: 'monthly',
        ymd: (m['ymd'] ?? '').toString(),
        amount: (m['amount'] as num? ?? 0).toDouble(),
        note: '月结 · ${m['category'] ?? ''}',
        op: (m['attribution'] ?? '').toString(),
        txn: null,
      ));
    }
    items.sort((a, b) => b.ymd.compareTo(a.ymd));
    return items;
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

  // 新增资金：日期 + 金额 + 方向 + 备注
  Future<void> _addFunds() async {
    final amt = double.tryParse(_amountCtr.text.trim());
    if (amt == null || amt <= 0) {
      toast('请输入大于 0 的金额');
      return;
    }
    try {
      await ref.read(localApiProvider).addWalletTxn(
            widget.wallet.id,
            amount: amt,
            direction: _dir,
            ymd: ymd(_txnDate),
            note: _noteCtr.text.trim(),
          );
      _amountCtr.clear();
      _noteCtr.clear();
      _dir = 'in';
      _txnDate = DateTime.now();
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  Future<void> _editTxn(_WalletTxn t) async {
    final amount = TextEditingController(text: t.amount.abs().toString());
    final note = TextEditingController(text: t.note);
    String dir = t.amount < 0 ? 'out' : 'in';
    DateTime date = parseYmd(t.ymd);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('修改资金记录'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '金额')),
                const SizedBox(height: 8),
                const Text('方向', style: TextStyle(fontSize: 13)),
                Row(children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('存入 +'),
                      selected: dir == 'in',
                      onSelected: (_) => set(() => dir = 'in'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('支出 −'),
                      selected: dir == 'out',
                      onSelected: (_) => set(() => dir = 'out'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await pickSimpleDate(
                      context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) set(() => date = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: '日期'),
                    child: Text(ymd(date)),
                  ),
                ),
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
    if (amt == null || amt <= 0) {
      toast('请输入大于 0 的金额');
      return;
    }
    try {
      await ref.read(localApiProvider).updateWalletTxn(
            t.id,
            amount: amt,
            direction: dir,
            ymd: ymd(date),
            note: note.text.trim(),
          );
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  Future<void> _deleteTxn(_WalletTxn t) async {
    if (!await _confirm('删除这条资金记录？')) return;
    try {
      await ref.read(localApiProvider).deleteWalletTxn(t.id);
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wallet;
    final rows = _rows;
    final linked = _linked;
    final manualIn = rows.fold(0.0, (s, t) => s + (t.amount > 0 ? t.amount : 0));
    // 余额以接口返回的实时数据为准（手动记录合计 + 关联分类净额），新增 / 修改后立即刷新
    final respBalance = (_safeData['balance'] as num? ?? 0).toDouble();
    final respLinked = (_safeData['linkedSum'] as num? ?? 0).toDouble();
    final curBalance = respBalance + respLinked;
    final showEmpty = rows.isEmpty && linked.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(w.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 汇总
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      _sumCol('当前余额（手动+关联）', fmtMoney(curBalance),
                          curBalance >= 0 ? AppColors.income : AppColors.expense),
                      if (w.target > 0) _sumCol('目标', fmtMoney(w.target), null),
                      _sumCol('手动存入', fmtMoney(manualIn), null),
                      if (w.linkCategory.isNotEmpty)
                        _sumCol('关联自动', '${respLinked >= 0 ? '+' : '−'}${fmtMoney(respLinked.abs())}',
                            respLinked >= 0 ? AppColors.income : AppColors.expense),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 新增资金
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('新增资金', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await pickSimpleDate(
                                context,
                                initialDate: _txnDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now().add(const Duration(days: 1)),
                              );
                              if (picked != null) setState(() => _txnDate = picked);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: '日期'),
                              child: Text(ymd(_txnDate)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(controller: _amountCtr, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: '金额')),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('存入 +'),
                            selected: _dir == 'in',
                            onSelected: (_) => setState(() => _dir = 'in'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('支出 −'),
                            selected: _dir == 'out',
                            onSelected: (_) => setState(() => _dir = 'out'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(controller: _noteCtr, decoration: const InputDecoration(labelText: '备注（可选）')),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _addFunds,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppPalette.text(context)),
                          child: const Text('新增资金'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 资金记录（手工 + 自动月结按日期穿插，与网页端一致）
                const Text('资金记录（日期 · 金额 · 操作人）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                if (_allTxns.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('还没有资金记录', style: TextStyle(color: AppPalette.textSecondary(context))),
                  )
                else
                  ..._allTxns.map((it) => Card(
                        child: ListTile(
                          tileColor: it.kind == 'monthly' ? AppPalette.background(context) : null,
                          title: Text(it.ymd),
                          subtitle: Text(it.kind == 'monthly'
                              ? '${it.note} · ${it.op} · 自动'
                              : (it.note.isNotEmpty ? it.note : (it.op.isNotEmpty ? '操作人：${it.op}' : ''))),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${it.amount >= 0 ? '+' : '−'}${fmtMoney(it.amount.abs())}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: it.amount >= 0 ? AppColors.income : AppColors.expense)),
                              if (it.kind == 'manual') ...[
                                const SizedBox(width: 4),
                                TextButton(onPressed: () => _editTxn(it.txn!), child: const Text('改')),
                                TextButton(
                                  onPressed: () => _deleteTxn(it.txn!),
                                  child: const Text('删', style: TextStyle(color: AppColors.expense)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )),
                if (showEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('该钱包暂无资金记录与关联流水。',
                      style: TextStyle(color: AppPalette.textSecondary(context))),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _sumCol(String l, String v, Color? c) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l, style: TextStyle(fontSize: 11, color: AppPalette.textSecondary(context))),
            const SizedBox(height: 4),
            Text(v,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: c ?? AppPalette.text(context))),
          ],
        ),
      );
}

// 资金记录 + 月结 合并行
class _RowItem {
  final String kind; // manual | monthly
  final String ymd;
  final double amount;
  final String note;
  final String op;
  final _WalletTxn? txn; // manual 时非空
  _RowItem({required this.kind, required this.ymd, required this.amount, required this.note, required this.op, this.txn});
}

class _WalletTxn {
  final int id;
  final String ymd;
  final double amount;
  final String note;
  final String opUser;
  _WalletTxn(
      {required this.id, required this.ymd, required this.amount, required this.note, required this.opUser});
  factory _WalletTxn.fromJson(Map<String, dynamic> j) => _WalletTxn(
        id: (j['id'] ?? 0).toInt(),
        ymd: j['ymd'] ?? '',
        amount: (j['amount'] ?? 0).toDouble(),
        note: j['note'] ?? '',
        opUser: j['op_user'] ?? '',
      );
}
