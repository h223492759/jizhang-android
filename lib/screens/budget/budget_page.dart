import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/charts/category_detail_page.dart';
import 'package:jizhang_android/core/local_first_api.dart';

class BudgetPage extends ConsumerStatefulWidget {
  const BudgetPage({super.key});
  @override
  ConsumerState<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends ConsumerState<BudgetPage> {
  int _year = DateTime.now().year;
  BudgetData? _data;
  List<Category> _expenseCats = [];
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
      final results = await Future.wait([api.getBudgets(year: _year), api.getCategories()]);
      _data = results[0] as BudgetData;
      _expenseCats = (results[1] as List<Category>).where((c) => c.type == 'expense').toList();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickYear() async {
    int y = _year;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateD) => AlertDialog(
          title: const Text('选择年份'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setStateD(() => y--)),
              Text('$y 年',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setStateD(() => y++)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, y), child: const Text('确定')),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() => _year = picked);
      _load();
    }
  }

  // 卡片标题：单分类显示分类名；多分类显示「多分类N」（N = 该多分类在列表中的序号，从 1 开始）
  // 列表页/详情页传分类名显示（保留 _catLabel/_catLabelOf 旧 API）
  String _catCardTitle(BudgetCat c, int i) {
    final names = _parseNames(c.category);
    if (names.length <= 1) return names.first;
    final all = _data?.categories ?? <BudgetCat>[];
    int n = 0;
    for (int k = 0; k <= i && k < all.length; k++) {
      if (_parseNames(all[k].category).length > 1) n++;
    }
    return '多分类$n';
  }

  // 解析多分类 JSON 数组 → 分类列表
  List<String> _parseNames(String raw) {
    if (raw.startsWith('[')) {
      try {
        final arr = jsonDecode(raw);
        if (arr is List) return arr.map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return [raw];
  }

  // 兼容旧 API：列表/调整弹窗标题解析（多分类显示「餐饮、交通」）
  String _catLabel(BudgetCat c) {
    final ns = _parseNames(c.category);
    return ns.join('、');
  }
  String _catLabelOf(String raw) {
    return _parseNames(raw).join('、');
  }

  Future<void> _setBudget({String? category}) async {
    // 分类预算总和：把已设置好的各分类预算金额相加
    final catSum =
        _data?.categories.fold<double>(0, (s, c) => s + c.amount) ?? 0;
    // 默认填入当前金额：年度=总预算，分类=该分类已设金额
    double curAmt = 0;
    if (category == null) {
      curAmt = _data?.totalAmount ?? 0;
    } else {
      for (final c in _data?.categories ?? <BudgetCat>[]) {
        if (c.category == category) {
          curAmt = c.amount;
          break;
        }
      }
    }
    final fmtAmt = (double v) =>
        v == v.toInt() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    final ctrl = TextEditingController(text: curAmt > 0 ? fmtAmt(curAmt) : '');
    final label = _catLabelOf(category ?? '');
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(category == null ? '设置年度总预算' : '预算 · $label'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (category == null && _data != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('当前：${fmtMoney(_data!.totalAmount)}，已花 ${fmtMoney(_data!.totalSpent)}'),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: '预算金额', border: OutlineInputBorder()),
                      autofocus: true,
                    ),
                  ),
                  if (category == null && catSum > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: TextButton(
                        onPressed: () =>
                            setD(() => ctrl.text = fmtAmt(catSum)),
                        child: const Text('分类预算总和',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final amt = double.tryParse(picked ?? '');
    if (picked == null || amt == null || amt < 0) return;
    try {
      await ref.read(localApiProvider).setBudget(year: _year, category: category, amount: amt);
      toast('已保存');
      _load();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('预算')),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : () => _pickCategory(),
        child: const Icon(Icons.add),
      ),
      body: _loading || d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  Text('$_year 年度', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _loading ? null : _pickYear,
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('切换年份'),
                  ),
                ]),
                const SizedBox(height: 12),
                d.totalAmount > 0 ? _totalCard(d) : _emptyTotal(),
                const SizedBox(height: 16),
                const Text('分类预算', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                ...List.generate(d.categories.length, (i) => i).map((i) => _catCard(d.categories[i], i)),
              ],
            ),
    );
  }

  Widget _emptyTotal() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text('暂无年度预算', style: TextStyle(fontSize: 15, color: AppPalette.textSecondary(context))),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _setBudget(),
              icon: const Icon(Icons.add),
              label: const Text('添加年度预算'),
            ),
          ],
        ),
      );

  Widget _totalCard(BudgetData d) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppPalette.card(context), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Row(children: [
              const Text('年度总预算', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(onPressed: () => _setBudget(), child: const Text('设置')),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (d.totalAmount <= 0 ? 0.0 : d.totalPercent / 100).clamp(0.0, 1.0),
              minHeight: 14,
              backgroundColor: AppPalette.background(context),
              valueColor: AlwaysStoppedAnimation(
                d.totalPercent > 100 ? AppColors.expense : AppColors.primaryDark),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text('已花 ${fmtMoney(d.totalSpent)}', style: TextStyle(color: AppColors.expense)),
              const Spacer(),
              Text('剩余 ${fmtMoney(d.totalRemaining)}', style: TextStyle(color: AppColors.income)),
            ]),
          ],
        ),
      );

  Widget _catCard(BudgetCat c, int i) => Card(
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategoryDetailPage(
                category: c.category,
                type: 'expense',
                start: '$_year-01-01',
                end: '$_year-12-31',
                initialPeriod: DateTime(_year),
                initialYearMode: true,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(_catCardTitle(c, i), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _setBudget(category: c.category),
                    child: const Text('调整'),
                  ),
                ]),
                LinearProgressIndicator(
                  value: (c.amount <= 0 ? 0.0 : c.percent / 100).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: AppPalette.background(context),
                  valueColor: AlwaysStoppedAnimation(
                    c.percent > 100 ? AppColors.expense : AppColors.primaryDark),
                ),
                const SizedBox(height: 6),
                Text('已花 ${fmtMoney(c.spent)} / 预算 ${fmtMoney(c.amount)}',
                    style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
              ],
            ),
          ),
        ),
      );

  Future<void> _pickCategory() async {
    final cat = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择分类（添加预算）'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('年度总预算', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ..._expenseCats.map((c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c.name),
                child: Text('${c.icon} ${c.name}'),
              )),
        ],
      ),
    );
    if (cat != null || cat == null) {
      // null 表示选「总预算」
      await _setBudget(category: cat);
    }
  }
}
