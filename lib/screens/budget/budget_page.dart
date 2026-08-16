import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api.dart';
import 'core/models.dart';
import 'core/theme.dart';
import 'core/util.dart';
import 'state/session.dart';

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
      final api = ref.read(apiProvider);
      final results = await Future.wait([api.getBudgets(year: _year), api.getCategories()]);
      _data = results[0] as BudgetData;
      _expenseCats = (results[1] as List<Category>).where((c) => c.type == 'expense').toList();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setBudget({String? category}) async {
    final ctrl = TextEditingController();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(category == null ? '设置年度总预算' : '预算 · ${category}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category == null && _data != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('当前：${fmtMoney(_data!.totalAmount)}，已花 ${fmtMoney(_data!.totalSpent)}'),
              ),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '预算金额', border: OutlineInputBorder()),
              autofocus: true,
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
    );
    final amt = double.tryParse(picked ?? '');
    if (picked == null || amt == null || amt < 0) return;
    try {
      await ref.read(apiProvider).setBudget(year: _year, category: category, amount: amt);
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
                    onPressed: () async {
                      final p = await showDatePicker(
                        context: context,
                        initialDate: DateTime(_year),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        helpText: '选择年份',
                      );
                      if (p != null) {
                        setState(() => _year = p.year);
                        _load();
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('切换'),
                  ),
                ]),
                const SizedBox(height: 12),
                _totalCard(d),
                const SizedBox(height: 16),
                const Text('分类预算', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                ...d.categories.map((c) => _catCard(c)),
              ],
            ),
    );
  }

  Widget _totalCard(BudgetData d) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Row(children: [
              const Text('年度总预算', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(onPressed: () => _setBudget(), child: const Text('设置')),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (d.totalAmount <= 0 ? 0 : d.totalPercent / 100).clamp(0.0, 1.0),
              minHeight: 14,
              backgroundColor: AppColors.background,
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

  Widget _catCard(BudgetCat c) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(c.category, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(onPressed: () => _setBudget(category: c.category), child: const Text('调整')),
              ]),
              LinearProgressIndicator(
                value: (c.amount <= 0 ? 0 : c.percent / 100).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: AppColors.background,
                valueColor: AlwaysStoppedAnimation(
                  c.percent > 100 ? AppColors.expense : AppColors.primaryDark),
              ),
              const SizedBox(height: 6),
              Text('已花 ${fmtMoney(c.spent)} / 预算 ${fmtMoney(c.amount)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
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
