import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';

class RecordSheet extends ConsumerStatefulWidget {
  const RecordSheet({super.key});
  @override
  ConsumerState<RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends ConsumerState<RecordSheet> {
  String _type = 'expense';
  List<Category> _cats = [];
  Category? _cat;
  String _amount = '';
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  bool _catLoaded = false;

  final _suggestions = ['早餐', '午餐', '晚餐', '交通', '购物', '工资', '红包'];

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  Future<void> _loadCats() async {
    try {
      _cats = await ref.read(apiProvider).getCategories();
    } catch (_) {
      _cats = [];
    }
    if (mounted) setState(() => _catLoaded = true);
  }

  List<Category> get _visibleCats =>
      _cats.where((c) => c.type == _type).toList();

  void _tapDigit(String d) {
    if (d == '.' && _amount.contains('.')) return;
    if (d != '.' && _amount == '0') _amount = '';
    if (_amount == '' && d == '.') _amount = '0.';
    if (_amount.replaceAll('.', '').length >= 10) return;
    setState(() => _amount += d);
  }

  void _backspace() {
    if (_amount.isNotEmpty) setState(() => _amount = _amount.substring(0, _amount.length - 1));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_cat == null) {
      toast('请选择分类');
      return;
    }
    final amt = double.tryParse(_amount);
    if (amt == null || amt <= 0) {
      toast('请输入金额');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).createFlow({
        'type': _type,
        'amount': amt,
        'category': _cat!.name,
        'description': _note.text.trim(),
        'payment_method': '',
        'flow_time': ymd(_date),
      });
      ref.read(dataVersionProvider.notifier).state++;
      toast('已保存');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _categoryGrid(),
                    if (_cat != null) _detailCard(),
                    _amountDisplay(),
                    _numpad(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  _typeBtn('expense', '支出'),
                  _typeBtn('income', '收入'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _typeBtn(String t, String label) {
    final active = _type == t;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _type = t;
            _cat = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? (t == 'expense' ? AppColors.expense : AppColors.income) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: active ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  Widget _categoryGrid() {
    if (!_catLoaded) {
      return const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator());
    }
    final cats = _visibleCats;
    if (cats.isEmpty) {
      return const Padding(padding: EdgeInsets.all(24), child: Text('暂无分类，请先在网页端添加'));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, childAspectRatio: 1.1),
        itemCount: cats.length,
        itemBuilder: (ctx, i) {
          final c = cats[i];
          final sel = _cat?.id == c.id;
          return InkWell(
            onTap: () => setState(() => _cat = c),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary : AppColors.background,
                    shape: BoxShape.circle,
                    border: Border.all(color: sel ? AppColors.primaryDark : Colors.transparent),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Text(c.icon, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(height: 4),
                Text(c.name, style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _detailCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: '备注（可选）',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: _pickDate,
              ),
              hintText: ymd(_date),
            ),
            onTap: () {},
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _suggestions
                .map((s) => ActionChip(
                      label: Text(s),
                      onPressed: () => _note.text = s,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _amountDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: AppColors.primary,
      child: Center(
        child: Text(
          '¥ ${_amount.isEmpty ? '0' : _amount}',
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: AppColors.text),
        ),
      ),
    );
  }

  Widget _numpad() {
    final keys = [
      '7', '8', '9',
      '4', '5', '6',
      '1', '2', '3',
      '.', '0', '⌫',
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
      itemCount: keys.length + 1,
      itemBuilder: (ctx, i) {
        if (i == keys.length) {
          return _numKey('完成', onTap: _saving ? null : _save, primary: true);
        }
        final k = keys[i];
        if (k == '⌫') {
          return _numKey(k, onTap: _backspace);
        }
        return _numKey(k, onTap: () => _tapDigit(k));
      },
    );
  }

  Widget _numKey(String label, {VoidCallback? onTap, bool primary = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: primary ? AppColors.primaryDark : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: primary ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: primary ? Colors.white : AppColors.text)),
        ),
      ),
    );
  }
}
