import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/components/simple_date_picker.dart';
import 'package:jizhang_android/core/local_first_api.dart';

class RecordPage extends ConsumerStatefulWidget {
  final Flow? initialFlow;
  const RecordPage({super.key, this.initialFlow});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> {
  late String _type;
  List<Category> _cats = [];
  Category? _cat;
  String _expression = '';
  final _name = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  bool _catLoaded = false;
  PresetsData _presets = PresetsData(presets: [], frequent: [], recent: []);
  bool _presetsLoaded = false;

  bool get _isEdit => widget.initialFlow != null;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFlow;
    _type = f?.type ?? 'expense';
    if (f != null) {
      _expression = _formatComputed(f.amount);
      _name.text = f.description;
      _date = parseYmd(datePart(f.flowTime));
    }
    _loadCats();
    _loadPresets();
  }

  Future<void> _loadCats() async {
    try {
      _cats = await ref.read(localApiProvider).getCategories();
    } catch (_) {
      _cats = [];
    }
    if (mounted) {
      // 编辑模式：按名称匹配分类
      final f = widget.initialFlow;
      if (f != null) {
        _cat = _cats.cast<Category?>().firstWhere(
              (c) => c?.name == f.category && c?.type == f.type,
              orElse: () => null,
            );
      }
      setState(() => _catLoaded = true);
    }
  }

  Future<void> _loadPresets() async {
    try {
      _presets = await ref.read(localApiProvider).getPresets(type: _type, limit: 12);
    } catch (_) {
      _presets = PresetsData(presets: [], frequent: [], recent: []);
    }
    if (mounted) setState(() => _presetsLoaded = true);
  }

  List<Category> get _visibleCats =>
      _cats.where((c) => c.type == _type).toList();

  bool get _hasOperator =>
      _expression.contains('+') || _expression.contains('-');

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
          while (j < expr.length && expr[j] != '+' && expr[j] != '-') {
            j++;
          }
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
      final lastOp = _expression.lastIndexOf(RegExp(r'[+-]'));
      final current =
          lastOp == -1 ? _expression : _expression.substring(lastOp + 1);
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
    if (_expression.length >= 12) return;
    setState(() => _expression += d);
  }

  void _tapOperator(String op) {
    if (_expression.isEmpty) return;
    final last = _expression[_expression.length - 1];
    if (last == '+' || last == '-') {
      setState(() =>
          _expression = _expression.substring(0, _expression.length - 1) + op);
      return;
    }
    if (_hasOperator) {
      final val = _computedAmount;
      if (val == null) return;
      setState(() => _expression = '${_formatComputed(val)}$op');
      return;
    }
    setState(() => _expression += op);
  }

  void _backspace() {
    if (_expression.isNotEmpty) {
      setState(() =>
          _expression = _expression.substring(0, _expression.length - 1));
    }
  }

  String _formatComputed(double v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Future<void> _pickDate() async {
    final picked = await pickSimpleDate(
      context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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
      final body = {
        'type': _type,
        'amount': amt,
        'category': _cat!.name,
        'description': _name.text.trim(),
        'payment_method': '',
        'flow_time': ymd(_date),
      };
      if (_isEdit) {
        await ref.read(localApiProvider).updateFlow(widget.initialFlow!.id, body);
      } else {
        await ref.read(localApiProvider).createFlow(body);
      }
      ref.read(dataVersionProvider.notifier).state++;
      toast(_isEdit ? '已更新' : '已保存');
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
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: _typeToggle(),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _categoryGrid(),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _cat != null
                ? _buildInputPanel()
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _typeToggle() {
    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _typeBtn('expense', '支出'),
          _typeBtn('income', '收入'),
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
            _presetsLoaded = false;
          });
          _loadPresets();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? (t == 'expense' ? AppColors.expense : AppColors.income) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: active ? Colors.white : AppColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
          ),
        ),
      ),
    );
  }

  Widget _categoryGrid() {
    if (!_catLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final cats = _visibleCats;
    if (cats.isEmpty) {
      return const Center(child: Text('暂无分类，请先在网页端添加'));
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.05,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
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
                  border: Border.all(
                      color: sel ? AppColors.primaryDark : Colors.transparent),
                ),
                padding: const EdgeInsets.all(10),
                child: Text(c.icon, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(height: 4),
              Text(c.name,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _amountDisplay(),
          _nameInput(),
          _numpad(),
        ],
      ),
    );
  }

  Widget _amountDisplay() {
    final display = _expression.isEmpty ? '0' : _expression;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '¥ $display',
            style: const TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.text),
          ),
          if (_hasOperator && _computedAmount != null)
            Text(
              '= ${_formatComputed(_computedAmount!)}',
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  void _applyPreset(PresetName p) {
    Category? matched;
    if (p.category != null && p.category!.isNotEmpty) {
      matched = _cats.cast<Category?>().firstWhere(
            (c) => c?.name == p.category && c?.type == _type,
            orElse: () => null,
          );
    }
    setState(() {
      _name.text = p.name;
      if (matched != null) _cat = matched;
      if (p.amount != null && p.amount! > 0) {
        _expression = _formatComputed(p.amount!);
      }
    });
  }

  // 按分类筛选：仅保留「未指定分类」或「匹配当前分类」的项；严格过滤，不回退。
  List<PresetName> _filterByCat(List<PresetName> src) {
    if (_cat == null) return src;
    final cat = _cat!.name;
    if (cat.isEmpty) return src;
    return src.where((p) => p.category == null || p.category!.isEmpty || p.category == cat).toList();
  }

  Widget _nameInput() {
    // 常用名称：收藏(★) 与高频/最近都严格按当前分类过滤——
    // 只显示「未绑定分类」或「当前分类」的收藏/高频/最近，其他分类的收藏不可见；
    // 未选分类时显示全部。收藏排最前，高频/最近随后。
    final raw = <PresetName>[
      ..._filterByCat(_presets.presets),
      ..._filterByCat(_presets.frequent),
      ..._filterByCat(_presets.recent),
    ].where((p) => p.name.isNotEmpty).toList();
    final unique = <String, PresetName>{};
    for (final p in raw) {
      unique.putIfAbsent(p.name, () => p);
    }
    final display = unique.values.take(10).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称（可选）',
              hintText: '请输入名称',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          if (display.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: display.map((p) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(p.name, style: const TextStyle(fontSize: 12)),
                      backgroundColor: Colors.grey.shade200,
                      side: BorderSide.none,
                      onPressed: () => _applyPreset(p),
                    ),
                  );
                }).toList(),
              ),
            ),
          ] else if (_cat != null) ...[
            const SizedBox(height: 6),
            Text('该分类暂无常用名，可直接在下方输入',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ],
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
      height: 260,
      color: AppColors.divider,
      child: Column(
        children: rows
            .map((row) => Expanded(
                  child: Row(
                    children: row.map((k) => Expanded(child: _numKey(k))).toList(),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _numKey(String key) {
    String label = '';
    IconData? icon;
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
        icon = Icons.backspace; // 改成电脑键盘式「退格」图标
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
          child: icon != null
              ? Icon(icon, size: 22, color: primary ? Colors.white : AppColors.text)
              : Text(label,
                  style: TextStyle(
                      fontSize: primary ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: primary ? Colors.white : AppColors.text)),
        ),
      ),
    );
  }
}
