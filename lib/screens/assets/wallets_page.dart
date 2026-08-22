import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/components/simple_date_picker.dart';
import 'package:jizhang_android/screens/assets/wallet_detail_page.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/core/local_first_api.dart';

const _palette = [
  Colors.blue,
  Colors.orange,
  Colors.green,
  Colors.purple,
  Colors.teal,
  Colors.red,
  Colors.amber,
  Colors.cyan,
  Colors.indigo,
  Colors.pink,
];


class _DepositRow {
  String cat;
  String owner;
  TextEditingController amount;
  TextEditingController startYm;
  TextEditingController endYm;
  _DepositRow({this.cat = '', this.owner = '', String amount = '', String startYm = '', String endYm = ''})
    : amount = TextEditingController(text: amount),
      startYm = TextEditingController(text: startYm),
      endYm = TextEditingController(text: endYm);
}
/// 分类钱包（与存款目标 / 资金细则完全独立的一页）
class WalletsPage extends ConsumerStatefulWidget {
  const WalletsPage({super.key});
  @override
  ConsumerState<WalletsPage> createState() => _WalletsPageState();
}

/// 关联行（每行一个 cat+from 对）
class _LinkRow {
  String cat = '';
  String from = '';
  _LinkRow({this.cat = '', this.from = ''});
}

class _WalletsPageState extends ConsumerState<WalletsPage> {
  WalletsData? _data;
  List<Category> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(localApiProvider);
      // 先拉服务器最新钱包刷新本地镜像（确保看到网页端新加/改的钱包）
      try { await api.refreshWallets(); } catch (_) {}
      final d = await api.getWallets();
      final cats = await api.getCategories();
      if (mounted) {
        setState(() {
          _data = d;
          _cats = cats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      toast(e.toString().replaceFirst('ApiException: ', ''));
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
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('钱包')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? const Center(child: Text('加载失败'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _header(d),
                      const SizedBox(height: 12),
                      _pie(d),
                      const SizedBox(height: 16),
                      ...d.wallets.map((w) => _walletCard(w)),
                      if (d.wallets.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text(
                              '还没有钱包。点右下角「＋」新增养娃、买房等专项金，每月存一笔即可（记录带日期、金额与操作人）。',
                              style: TextStyle(color: AppPalette.textSecondary(context))),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _addWallet,
        child: const Icon(Icons.add),
      ),
    );
  }

  // 总余额一行（总目标/达成率已按要求删除）
  Widget _header(WalletsData d) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _col('总余额', '¥${fmtMoney(d.totalBalance)}', true),
        ],
      ),
    );
  }

  Widget _col(String l, String v, [bool bold = false]) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l, style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
            const SizedBox(height: 4),
            Text(v,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                    fontSize: bold ? 18 : 15)),
          ],
        ),
      );

  // 各钱包「已存余额」占比饼图（余额 <= 0 不计入）
  Widget _pie(WalletsData d) {
    final ws = d.wallets.where((w) => w.balance > 0).toList();
    if (ws.isEmpty) {
      return const SizedBox();
    }
    final total = ws.fold(0.0, (s, w) => s + w.balance);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('专项金已存余额分布', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 46,
                borderData: FlBorderData(show: false),
                sections: ws.asMap().entries.map((e) {
                  final w = e.value;
                  final c = _palette[e.key % _palette.length];
                  final p = total > 0 ? (w.balance / total * 100) : 0;
                  return PieChartSectionData(
                    value: w.balance,
                    title: '${p.toStringAsFixed(0)}%',
                    color: c,
                    radius: 64,
                    titleStyle: TextStyle(
                        fontSize: 11, color: AppPalette.card(context), fontWeight: FontWeight.bold),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...ws.asMap().entries.map((e) {
            final w = e.value;
            final c = _palette[e.key % _palette.length];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(width: 10, height: 10, color: c),
                  const SizedBox(width: 6),
                  Expanded(child: Text(w.name, overflow: TextOverflow.ellipsis)),
                  Text('¥${fmtMoney(w.balance)}',
                      style: TextStyle(fontSize: 13, color: AppPalette.textSecondary(context))),
                ],
              ),
            );
          }),
          if (d.wallets.any((w) => w.balance <= 0))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '未计入分布（已存 ≤ 0）：${d.wallets.where((w) => w.balance <= 0).map((w) => w.name).join('、')}',
                style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _walletCard(Wallet w) {
    final pct = (w.target > 0 ? w.percent : 0).clamp(0, 100);
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WalletDetailPage(wallet: w)),
        ).then((_) => _load()),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(backgroundColor: AppColors.primarySoft, child: Text(w.icon)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(w.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                  Text('${w.count}笔', style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
                ],
              ),
              const SizedBox(height: 6),
              Text('¥${fmtMoney(w.balance)}',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: w.balance >= 0 ? AppColors.income : AppColors.expense)),
              if (w.target > 0)
                Text('目标 ¥${fmtMoney(w.target)} · 已达成 $pct%',
                    style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)))
              else
                Text('未设目标', style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
              if (w.target > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 6,
                    backgroundColor: AppPalette.background(context),
                    valueColor: AlwaysStoppedAnimation(
                        w.balance >= w.target ? AppColors.income : AppColors.primaryDark),
                  ),
                ),
              if (w.linkLinks.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final lk in w.linkLinks)
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('🔗 关联 ${lk.cat} · 自 ${lk.from.isEmpty ? "（未设）" : lk.from}',
                        style: TextStyle(fontSize: 12, color: AppColors.primaryDark)),
                  ),
                const SizedBox(height: 4),
                Text(
                  '关联自动 ${w.linked >= 0 ? '+' : '−'}${fmtMoney(w.linked.abs())}（手动 ${fmtMoney(w.manualBalance)}）',
                  style: TextStyle(
                      fontSize: 12,
                      color: w.linked >= 0 ? AppColors.income : AppColors.expense),
                ),
              ],
              const SizedBox(height: 4),
              Text('存入 ${fmtMoney(w.totalIn)}｜支出 ${fmtMoney(w.totalOut)}',
                  style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
              Text('最近 ${w.lastYmd.isEmpty ? '—' : w.lastYmd}',
                  style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(onPressed: () => _editWallet(w), child: const Text('修改钱包信息')),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => WalletDetailPage(wallet: w)),
                    ).then((_) => _load()),
                    child: const Text('改'),
                  ),
                  TextButton(
                    onPressed: () => _deleteWallet(w),
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

  // ---------------- 新增 / 编辑 钱包 ----------------
  /// 构建一行"分类+日期"：Dropdown(选分类) + TextField(输日期YYYY-MM-DD) + × 按钮
  Widget _buildLinkRow(List<_LinkRow> rows, int i, void Function(void Function()) set) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: rows[i].cat.isEmpty ? null : rows[i].cat,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: '分类', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              items: [
                const DropdownMenuItem(value: '', child: Text('选择分类')),
                ..._cats.map((c) => DropdownMenuItem(
                    value: c.name,
                    child: Text('${c.name}${c.type == 'income' ? '（收）' : '（支）'}',
                        style: const TextStyle(fontSize: 12)))),
              ],
              onChanged: (v) => set(() => rows[i].cat = v ?? ''),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: rows[i].from,
              decoration: const InputDecoration(
                  labelText: '起始日', isDense: true,
                  hintText: '2026-08-14',
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              onChanged: (v) => rows[i].from = v.trim(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: '删除该行',
            onPressed: () => set(() {
              if (rows.length > 1) {
                rows.removeAt(i);
              } else {
                rows[0] = _LinkRow();
              }
            }),
          ),
        ],
      ),
    );
  }

  Future<void> _addWallet() async {
    final name = TextEditingController();
    final icon = TextEditingController(text: '👛');
    final target = TextEditingController();
    final initBalance = TextEditingController();
    final note = TextEditingController();
    // 多行关联：每行 {cat, from}，支持同钱包多分类不同起始日（如礼金支 1月 + 礼金收 6月）
    final linkRows = <_LinkRow>[_LinkRow()];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('新增钱包'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: '名称（如 养娃 / 买房）')),
                TextField(controller: icon, decoration: const InputDecoration(labelText: '图标 emoji（可选）')),
                TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '目标金额（可选）')),
                TextField(controller: initBalance, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '已存金额（可选，记为一笔存入）')),
                const SizedBox(height: 8),
                const Text('关联流水分类（可选，每行一个分类+起始日）', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                ...List.generate(linkRows.length, (i) => _buildLinkRow(linkRows, i, set)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => set(() => linkRows.add(_LinkRow())),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('添加一行', style: TextStyle(fontSize: 12)),
                  ),
                ),
                TextField(controller: note, decoration: const InputDecoration(labelText: '备注（可选）')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final cleanLinks = linkRows
        .where((r) => r.cat.trim().isNotEmpty)
        .map((r) => {'cat': r.cat.trim(), 'from': r.from.trim()})
        .toList();
    try {
      final api = ref.read(localApiProvider);
      final id = await api.addWallet(
        name: name.text.trim(),
        icon: icon.text.trim().isEmpty ? '👛' : icon.text.trim(),
        target: double.tryParse(target.text.trim()) ?? 0,
        linkLinks: cleanLinks,
        note: note.text.trim(),
      );
      final ib = double.tryParse(initBalance.text.trim()) ?? 0;
      if (ib > 0) {
        await api.addWalletTxn(id, amount: ib, direction: 'in', ymd: ymdNow(), note: '初始已存');
      }
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  Future<void> _editWallet(Wallet w) async {
    final name = TextEditingController(text: w.name);
    final icon = TextEditingController(text: w.icon);
    final target = TextEditingController(text: w.target > 0 ? w.target.toString() : '');
    final note = TextEditingController(text: w.note);
    final linkRows = <_LinkRow>[];
    if (w.linkLinks.isNotEmpty) {
      for (final l in w.linkLinks) {
        linkRows.add(_LinkRow(cat: l.cat, from: l.from));
      }
    } else if (w.linkCategories.isNotEmpty) {
      for (final c in w.linkCategories) {
        linkRows.add(_LinkRow(cat: c, from: w.linkFrom));
      }
    } else if (w.linkCategory.isNotEmpty) {
      linkRows.add(_LinkRow(cat: w.linkCategory, from: w.linkFrom));
    }
    if (linkRows.isEmpty) linkRows.add(_LinkRow());
    // 定存细则行（每行 {cat, amount, start_ym, end_ym}，owner 可选）
    final depositRows = <_DepositRow>[];
    for (final r in w.depositRules) {
      depositRows.add(_DepositRow(
        cat: r.cat, owner: r.owner,
        amount: r.amount.toString(),
        startYm: r.startYm, endYm: r.endYm,
      ));
    }
    if (depositRows.isEmpty) depositRows.add(_DepositRow());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('修改钱包信息'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
                  TextField(controller: icon, decoration: const InputDecoration(labelText: '图标 emoji（可选）')),
                  TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '目标金额（可选）')),
                  const SizedBox(height: 12),
                  const Text('关联流水分类（每行一个分类+起始日）', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ...List.generate(linkRows.length, (i) => _buildLinkRow(linkRows, i, set)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => set(() => linkRows.add(_LinkRow())),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('添加一行', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('定存细则（每月第一笔匹配收入流水且金额 ≥ 规则总额时自动存入）', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ...List.generate(depositRows.length, (i) => _buildDepositRow(depositRows, i, set)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => set(() => depositRows.add(_DepositRow())),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('添加定存细则', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: note, decoration: const InputDecoration(labelText: '备注（可选）')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final cleanLinks = linkRows
        .where((r) => r.cat.trim().isNotEmpty)
        .map((r) => {'cat': r.cat.trim(), 'from': r.from.trim()})
        .toList();
    final cleanDeposit = <Map<String, dynamic>>[];
    for (final r in depositRows) {
      final c = r.cat.trim();
      final amt = double.tryParse(r.amount.text.trim()) ?? 0;
      if (c.isEmpty || amt <= 0) continue;
      cleanDeposit.add({
        'cat': c, 'owner': r.owner.trim(),
        'amount': amt,
        'start_ym': r.startYm.text.trim(), 'end_ym': r.endYm.text.trim(),
      });
    }
    try {
      await ref.read(localApiProvider).updateWallet(
        id: w.id,
        name: name.text.trim(),
        icon: icon.text.trim().isEmpty ? '👛' : icon.text.trim(),
        target: double.tryParse(target.text.trim()) ?? 0,
        linkLinks: cleanLinks,
        note: note.text.trim(),
        depositRules: cleanDeposit,
      );
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  Widget _buildDepositRow(List<_DepositRow> rows, int i, void Function(void Function()) set) {
    final r = rows[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: r.cat),
                  decoration: const InputDecoration(labelText: '来源分类', isDense: true),
                  onChanged: (v) => r.cat = v,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: r.owner),
                  decoration: const InputDecoration(labelText: '归属人(可选)', isDense: true),
                  onChanged: (v) => r.owner = v,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => set(() => rows.removeAt(i)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: r.amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '金额', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: r.startYm,
                  decoration: const InputDecoration(labelText: '开始 YYYY-MM', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: r.endYm,
                  decoration: const InputDecoration(labelText: '结束 YYYY-MM', isDense: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteWallet(Wallet w) async {
    if (!await _confirm('删除钱包「${w.name}」？其下所有资金记录也会一并删除。')) return;
    try {
      await ref.read(localApiProvider).deleteWallet(w.id);
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }
}
