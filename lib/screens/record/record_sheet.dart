import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String _expression = '';
  final _name = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  bool _catLoaded = false;

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

  bool get _hasOperator => _expression.contains('+') || _expression.contains('-');

  double? _compute(String expr) {
    if (expr.isEmpty) return null;
    try {
      final tokens = <String>[];
      int i = 0;
      while (i < expr.length) {
        if (expr[i] == '+' || expr[i] == '-') {
          tokens.add(expr[i]);
          i++;
        } else {
          int j = i;
          while (j < expr.length && expr[j] != '+' && expr[j] != '-') j++;
          tokens.add(expr.substring(i, j));
          i = j;
        }
      }
      double result = 0;
      String op = '+';
      for (final t in tokens) {
        if (t == '+' || t == '-') {
          op = t;
        } else if (t.isNotEmpty) {
          final v = double.tryParse(t);
          if (v == null) return null;
          result = op == '+' ? result + v : result - v;
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  double? get _computedAmount => _compute(_expression);

  void _tapDigit(String d) {
    if (d == '.') {
      // 当前操作数最多一个小数点
      final lastOp = _expression.lastIndexOf(RegExp(r'[+-]'));
      final current = lastOp == -1 ? _expression : _expression.substring(lastOp + 1);
      if (current.contains('.')) return;
      if (current.isEmpty) {
        setState(() => _expression += '0.');
        return;
      }
    }
    if (_expression == '0' && d != '.') {
      setState(() => _expression = d);
      return;
    }
    // 限制总长度
    if (_expression.length >= 12) return;
    setState(() => _expression += d);
  }

  void _tapOperator(String op) {
    if (_expression.isEmpty) return;
    final last = _expression[_expression.length - 1];
    if (last == '+' || last == '-') {
      setState(() => _expression = _expression.substring(0, _expression.length - 1) + op);
      return;
    }
    if (_hasOperator) {
      // 已有运算符，先计算再追加
      final val = _computedAmount;
      if (val == null) return;
      setState(() => _expression = '${_formatComputed(val)}$op');
      return;
    }
    setState(() => _expression += op);
  }

  void _backspace() {
    if (_expression.isNotEmpty) {
      setState(() => _expression = _expression.substring(0, _expression.length - 1));
    }
  }

  String _formatComputed(double v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
      locale: const Locale('zh', 'CN'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _finish() async {
    if (_cat == null) {
      toast('请选择分类');
      return;
    }
    var expr = _expression;
    if (expr.isNotEmpty) {
      final last = expr[expr.length - 1];
      if (last == '+' || last == '-') expr = expr.substring(0, expr.length - 1);
    }
    double? amt;
    if (expr.contains('+') || expr.contains('-')) {
      amt = _compute(expr);
    } else {
      amt = double.tryParse(expr);
    }
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
        'description': _name.text.trim(),
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

  void _onNumpad(String key) {
    switch (key) {
      case 'date':
        _pickDate();
        break;
      case '+':
      case '-':
        _tapOperator(key);
        break;
      case 'del':
        _backspace();
        break;
      case 'done':
        _finish();
        break;
      case '=':
        final val = _computedAmount;
        if (val != null) setState(() => _expression = _formatComputed(val));
        break;
      default:
        _tapDigit(key);
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
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: _cat != null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _amountDisplay(),
                                _nameInput(),
                                _numpad(),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
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
            _expression = '';
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

  Widget _amountDisplay() {
    final display = _expression.isEmpty ? '0' : _expression;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      color: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '¥ $display',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.text),
          ),
          if (_hasOperator && _computedAmount != null)
            Text(
              '= ${_formatComputed(_computedAmount!)}',
              style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _nameInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _name,
        decoration: InputDecoration(
          labelText: '名称（可选）',
          hintText: '请输入名称',
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _numpad() {
    final rows = [
      ['7', '8', '9', 'date'],
      ['4', '5', '6', '+'],
      ['1', '2', '3', '-'],
      ['.', '0', 'del', _hasOperator ? '=' : 'done'],
    ];
    return Container(
      height: 280,
      color: AppColors.divider,
      child: Column(
        children: rows.map((row) => Expanded(
          child: Row(
            children: row.map((k) => Expanded(child: _numKey(k))).toList(),
          ),
        )).toList(),
      ),
    );
  }

  Widget _numKey(String key) {
    String label;
    VoidCallback? onTap;
    bool primary = false;
    switch (key) {
      case 'date':
        label = '${_date.month}/${_date.day}';
        onTap = () => _onNumpad('date');
        break;
      case '+':
        label = '+';
        onTap = () => _onNumpad('+');
        break;
      case '-':
        label = '-';
        onTap = () => _onNumpad('-');
        break;
      case 'del':
        label = '删除';
        onTap = () => _onNumpad('del');
        break;
      case 'done':
        label = '完成';
        primary = true;
        onTap = _saving ? null : () => _onNumpad('done');
        break;
      case '=':
        label = '=';
        primary = true;
        onTap = () => _onNumpad('=');
        break;
      default:
        label = key;
        onTap = () => _onNumpad(key);
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(0.5),
        decoration: BoxDecoration(
          color: primary ? AppColors.primaryDark : Colors.white,
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: primary ? 20 : 22,
                  fontWeight: FontWeight.bold,
                  color: primary ? Colors.white : AppColors.text)),
        ),
      ),
    );
  }
}
