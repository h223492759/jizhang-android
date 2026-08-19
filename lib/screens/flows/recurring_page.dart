import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/core/local_first_api.dart';

/// 定期记账：每月/每年固定收支模板，到时间自动生成流水
class RecurringPage extends ConsumerStatefulWidget {
  const RecurringPage({super.key});
  @override
  ConsumerState<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends ConsumerState<RecurringPage> {
  List<Recurring> _list = [];
  List<Category> _cats = [];
  List<AttributionMember> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final api = ref.read(localApiProvider);
      _cats = await api.getCategories();
      // 先到期的落成流水，再拉模板
      try {
        final n = await api.generateRecurring();
        if (n > 0) toast('已自动生成 $n 笔定期记账');
      } catch (_) {}
      _list = await api.getRecurring();
      try {
        _members = await api.getAttributions();
      } catch (_) {}
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    try {
      final api = ref.read(localApiProvider);
      _list = await api.getRecurring();
      if (mounted) setState(() {});
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  String _catIcon(String name) {
    for (final c in _cats) {
      if (c.name == name) return c.icon;
    }
    return '💰';
  }

  Future<void> _generate() async {
    try {
      final n = await ref.read(localApiProvider).generateRecurring();
      toast(n > 0 ? '已生成 $n 笔' : '暂无可生成的记录');
      await _reload();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  Future<void> _openDialog([Recurring? t]) async {
    final form = _RecurForm(
      type: t?.type ?? 'expense',
      category: t?.category ?? '',
      description: t?.description ?? '',
      amount: t?.amount ?? 0,
      paymentMethod: t?.paymentMethod ?? '',
      freq: t?.freq ?? 'monthly',
      dayOfMonth: t?.dayOfMonth ?? 1,
      monthOfYear: t?.monthOfYear ?? 1,
      note: t?.note ?? '',
      attributionUid: t?.attributionUid,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RecurringFormDialog(
        form: form,
        cats: _cats,
        members: _members,
        isEdit: t != null,
        currentUid: ref.read(sessionProvider).user?.id,
      ),
    );
    if (ok == true) {
      try {
        final api = ref.read(localApiProvider);
        final body = {
          'type': form.type,
          'category': form.category,
          'description': form.description,
          'amount': form.amount,
          'payment_method': form.paymentMethod,
          'freq': form.freq,
          'day_of_month': form.dayOfMonth,
          'month_of_year': form.monthOfYear,
          'note': form.note,
          'attribution_uid': form.attributionUid,
        };
        if (t != null) {
          await api.updateRecurring(t.id, body);
          toast('已更新');
        } else {
          await api.addRecurring(body);
          toast('已添加');
        }
        await _reload();
      } catch (e) {
        toast(e.toString().replaceFirst('ApiException: ', ''));
      }
    }
  }

  Future<void> _delete(Recurring t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确定删除「${t.category} ${fmtMoney(t.amount)}」这条定期记账模板吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: AppColors.expense))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(localApiProvider).deleteRecurring(t.id);
      toast('已删除');
      await _reload();
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('定期记账')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('设定每月/每年固定收支，到时间自动生成流水（也可手动点「生成到期记录」）。',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                Row(children: [
                  TextButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('生成到期记录'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _openDialog(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.text,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新增模板'),
                  ),
                ]),
                const SizedBox(height: 6),
                if (_list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: Text('还没有定期记账模板，点「新增模板」添加，例如\n「每月 1 号 房租 3000」「每年 1 月 1 号 年终奖 20000」',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ),
                  )
                else
                  ..._list.map((t) => _card(t)),
              ],
            ),
    );
  }

  Widget _card(Recurring t) {
    final color = t.isExpense ? AppColors.expense : AppColors.income;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(t.isExpense ? '支出' : '收入',
                    style: TextStyle(fontSize: 11, color: color)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${_catIcon(t.category)} ${t.category}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('¥${fmtMoney(t.amount)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ]),
            if (t.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(t.description,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 4),
            Text(
              '${t.freqText} · 下次：${t.nextRun}'
              '${t.paymentMethod.isNotEmpty ? ' · ${t.paymentMethod}' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (t.note.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('备注：${t.note}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
            // 归属人标签（与流水归属展示一致）
            if (t.attribution.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(t.attribution,
                      style: const TextStyle(fontSize: 11, color: AppColors.primaryDark)),
                ),
              ]),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => _openDialog(t), child: const Text('编辑')),
                TextButton(
                  onPressed: () => _delete(t),
                  child: const Text('删除', style: TextStyle(color: AppColors.expense)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 模板表单（弹窗内编辑）
class _RecurForm {
  String type;
  String category;
  String description;
  double amount;
  String paymentMethod;
  String freq;
  int dayOfMonth;
  int monthOfYear;
  String note;
  int? attributionUid;
  _RecurForm({
    required this.type,
    required this.category,
    required this.description,
    required this.amount,
    required this.paymentMethod,
    required this.freq,
    required this.dayOfMonth,
    required this.monthOfYear,
    required this.note,
    this.attributionUid,
  });
}

class _RecurringFormDialog extends StatefulWidget {
  final _RecurForm form;
  final List<Category> cats;
  final List<AttributionMember> members;
  final bool isEdit;
  final int? currentUid;
  const _RecurringFormDialog({
    required this.form,
    required this.cats,
    required this.members,
    required this.isEdit,
    this.currentUid,
  });

  @override
  State<_RecurringFormDialog> createState() => _RecurringFormDialogState();
}

class _RecurringFormDialogState extends State<_RecurringFormDialog> {
  late final TextEditingController _desc;
  late final TextEditingController _amount;
  late final TextEditingController _pay;
  late final TextEditingController _note;
  late final TextEditingController _day;
  late final TextEditingController _month;

  List<Category> get _cats => widget.cats.where((c) => c.type == widget.form.type).toList();

  @override
  void initState() {
    super.initState();
    final f = widget.form;
    _desc = TextEditingController(text: f.description);
    _amount = TextEditingController(text: f.amount > 0 ? f.amount.toString() : '');
    _pay = TextEditingController(text: f.paymentMethod);
    _note = TextEditingController(text: f.note);
    _day = TextEditingController(text: f.dayOfMonth.toString());
    _month = TextEditingController(text: f.monthOfYear.toString());
    if (f.category.isEmpty && _cats.isNotEmpty) f.category = _cats.first.name;
    if (f.attributionUid == null) f.attributionUid = widget.currentUid;
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    _pay.dispose();
    _note.dispose();
    _day.dispose();
    _month.dispose();
    super.dispose();
  }

  bool _save() {
    final f = widget.form;
    f.description = _desc.text.trim();
    f.amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (f.amount <= 0) {
      toast('请输入正确金额');
      return false;
    }
    f.paymentMethod = _pay.text.trim();
    f.note = _note.text.trim();
    if (f.freq == 'yearly') {
      f.monthOfYear = int.tryParse(_month.text.trim()) ?? 1;
      if (f.monthOfYear < 1 || f.monthOfYear > 12) {
        toast('月份需在 1-12 之间');
        return false;
      }
    }
    f.dayOfMonth = int.tryParse(_day.text.trim()) ?? 1;
    if (f.dayOfMonth < 1 || f.dayOfMonth > 31) {
      toast('日期需在 1-31 之间');
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    final cats = _cats;
    return AlertDialog(
      title: Text(widget.isEdit ? '编辑定期记账' : '新增定期记账'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 类型
            Row(children: [
              _seg('支出', f.type == 'expense', () => setState(() {
                    f.type = 'expense';
                    if (cats.isNotEmpty) f.category = cats.first.name;
                  })),
              const SizedBox(width: 8),
              _seg('收入', f.type == 'income', () => setState(() {
                    f.type = 'income';
                    if (cats.isNotEmpty) f.category = cats.first.name;
                  })),
            ]),
            const SizedBox(height: 10),
            // 分类
            DropdownButtonFormField<String>(
              value: f.category.isEmpty ? null : f.category,
              items: cats.map((c) => DropdownMenuItem(value: c.name, child: Text('${c.icon} ${c.name}'))).toList(),
              onChanged: (v) => setState(() => f.category = v ?? ''),
              decoration: const InputDecoration(labelText: '分类', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: '名称（可空，留空用分类名）', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '金额', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            // 周期
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: f.freq,
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('每月')),
                    DropdownMenuItem(value: 'yearly', child: Text('每年')),
                  ],
                  onChanged: (v) => setState(() => f.freq = v ?? 'monthly'),
                  decoration: const InputDecoration(labelText: '周期', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              if (f.freq == 'yearly') ...[
                Expanded(
                  child: TextField(
                    controller: _month,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '月份(1-12)', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: _day,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: f.freq == 'yearly' ? '日期(1-31)' : '每月几号(1-31)',
                      border: const OutlineInputBorder(),
                      isDense: true),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _pay,
              decoration: const InputDecoration(labelText: '支付方式（可空）', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            // 归属
            DropdownButtonFormField<int?>(
              value: f.attributionUid,
              items: [
                const DropdownMenuItem(value: null, child: Text('不指定')),
                ...widget.members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.nickname))),
              ],
              onChanged: (v) => setState(() => f.attributionUid = v),
              decoration: const InputDecoration(
                  labelText: '归属（默认当前账号）', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: '备注（可空）', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: () {
            if (_save()) Navigator.pop(context, true);
          },
          child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _seg(String label, bool on, VoidCallback tap) => Expanded(
        child: InkWell(
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.primarySoft : AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: on ? AppColors.primaryDark : AppColors.divider),
            ),
            child: Text(label,
                style: TextStyle(
                    fontWeight: on ? FontWeight.bold : FontWeight.normal,
                    color: on ? AppColors.primaryDark : AppColors.textSecondary)),
          ),
        ),
      );
}
