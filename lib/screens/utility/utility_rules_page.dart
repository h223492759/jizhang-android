import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/local_first_api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/screens/utility/utility_common.dart';

/// 水电气物业规则管理（带生效起止，搬家/调价 = 新开一段）
class UtilityRulesPage extends ConsumerStatefulWidget {
  const UtilityRulesPage({super.key});
  @override
  ConsumerState<UtilityRulesPage> createState() => _UtilityRulesPageState();
}

class _UtilityRulesPageState extends ConsumerState<UtilityRulesPage> {
  List<dynamic> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(localApiProvider).getUtilityRules();
      if (!mounted) return;
      setState(() {
        _rules = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast('加载失败：$e');
    }
  }

  String _tierBrief(Map rule) {
    final tiers = (rule['tiers'] as List?) ?? [];
    if (tiers.isEmpty) return '';
    final first = (tiers.first as Map);
    final price = (first['price'] as num?)?.toDouble() ?? 0;
    final unit = (rule['unit'] as String?) ?? '';
    final cyc = (rule['cycle_type'] as String?) == 'by_year' ? '· 按年累计' : '';
    return '第1档 ${_p(price)}元${unit.isEmpty ? '' : '/$unit'} · 共${tiers.length}档$cyc';
  }

  String _p(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('计价规则'),
        actions: [
          IconButton(
            tooltip: '新建规则',
            icon: const Icon(Icons.add),
            onPressed: () => _openEdit(null),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? const Center(
                  child: Text('还没有任何规则，点右上角 + 新建',
                      style: TextStyle(color: AppColors.textSecondary)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final t in kUtilityTypes)
                      ..._section(context, t['type']!, t['label']!, t['icon']!),
                  ],
                ),
    );
  }

  List<Widget> _section(
      BuildContext context, String type, String label, String icon) {
    final mine =
        _rules.where((r) => (r as Map)['type'] == type).cast<Map>().toList();
    final children = <Widget>[];
    if (mine.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Row(children: [
          Text('$icon $label',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          TextButton(
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: () => _openEdit(type),
            child: const Text('+ 新增'),
          ),
        ]),
      ));
      for (final r in mine) {
        children.add(_ruleCard(context, r, type, icon));
      }
    }
    return children;
  }

  Widget _ruleCard(BuildContext context, Map r, String type, String icon) {
    final effFrom = (r['effective_from'] as String?) ?? '';
    final effTo = (r['effective_to'] as String?) ?? '';
    final range =
        effTo.isEmpty ? '$effFrom 起（未设置结束）' : '$effFrom ~ $effTo';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(icon, style: const TextStyle(fontSize: 22)),
        title: Text('${r['name'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('分类 ${(r['category'] as String?)?.isNotEmpty == true ? r['category'] : '住房'} · 生效 $range',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(_tierBrief(r),
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openEditExisting(r),
      ),
    );
  }

  Future<void> _openEdit(String? newType) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RuleEditPage(
          initType: newType ?? 'electric',
          editRule: null,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openEditExisting(Map rule) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RuleEditPage(
          initType: (rule['type'] as String?) ?? 'electric',
          editRule: Map<String, dynamic>.from(rule),
        ),
      ),
    );
    await _load();
  }
}

// ==================== 规则编辑页 ====================

class _RuleEditPage extends ConsumerStatefulWidget {
  final String initType;
  final Map<String, dynamic>? editRule; // null = 新建
  const _RuleEditPage({required this.initType, this.editRule});
  @override
  ConsumerState<_RuleEditPage> createState() => _RuleEditPageState();
}

List<Map<String, String>> _defaultTiers(String type) {
  switch (type) {
    case 'water':
      return [
        {'cap': '41', 'price': '3.5'},
        {'cap': '11', 'price': '5.25'},
        {'cap': '', 'price': '10.5'},
      ];
    case 'electric':
      return [
        {'cap': '200', 'price': '0.5889'},
        {'cap': '199', 'price': '0.6389'},
        {'cap': '', 'price': '0.8889'},
      ];
    case 'gas':
      return [
        {'cap': '320', 'price': '3.45'},
        {'cap': '80', 'price': '4.14'},
        {'cap': '', 'price': '5.18'},
      ];
    case 'property':
      return [
        {'cap': '', 'price': '82'},
      ];
  }
  return [
    {'cap': '', 'price': ''}
  ];
}

class _RuleEditPageState extends ConsumerState<_RuleEditPage> {
  late String _type;
  bool get _editing => widget.editRule != null;
  // v260908：关联消费分类（识别=规则分类+名称关键词，默认住房兼容老规则）
  late String _category;
  List<Category> _cats = [];
  late final TextEditingController _nameCtrl;
  late final TextEditingController _fromCtrl; // YYYY-MM 文本
  late final TextEditingController _toCtrl;
  late final TextEditingController _spanCtrl;
  late final TextEditingController _unitCtrl;
  late final List<Map<String, TextEditingController>> _rows; // tiers 行
  bool _seasonOn = false;
  late final Set<int> _seasonMonths;
  late final List<Map<String, TextEditingController>> _seasonRows;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.editRule;
    _type = widget.initType;
    final catRaw = (r?['category'] as String?)?.trim() ?? '';
    _category = catRaw.isEmpty ? '住房' : catRaw;
    _loadCats();
    final now = DateTime.now();
    final thisYm = ym2(now);
    _nameCtrl = TextEditingController(
        text: (r?['name'] as String?) ?? '');
    _fromCtrl = TextEditingController(
        text: (r?['effective_from'] as String?) ?? thisYm);
    _toCtrl =
        TextEditingController(text: (r?['effective_to'] as String?) ?? '');
    _spanCtrl = TextEditingController(
        text: r?['bill_span'] == null
            ? '${_spanDefault(_type)}'
            : '${r?['bill_span']}');
    _unitCtrl = TextEditingController(
        text: (r?['unit'] as String?) ?? _unitDefault(_type));
    _rows = _makeRows(
        _type, r?['tiers'] == null ? null : (r!['tiers'] as List));
    final s = r?['season'] as Map?;
    _seasonOn = s != null;
    _seasonMonths = (s != null && s['months'] is List)
        ? ((s['months'] as List).map((e) => (e as num).toInt()).toSet())
        : {5, 6, 7, 8, 9, 10};
    // 夏季档模板：广州夏季 260/339/∞（仅电费使用；无 season 数据时给默认值）
    _seasonRows = (s != null && s['tiers'] is List)
        ? _makeRows('electric', s['tiers'] as List)
        : <Map<String, TextEditingController>>[
            {
              'cap': TextEditingController(text: '260'),
              'price': TextEditingController(text: '0.5889')
            },
            {
              'cap': TextEditingController(text: '339'),
              'price': TextEditingController(text: '0.6389')
            },
            {
              'cap': TextEditingController(text: ''),
              'price': TextEditingController(text: '0.8889')
            },
          ];
  }

  int _spanDefault(String type) {
    switch (type) {
      case 'water':
      case 'gas':
        return 2;
      case 'property':
        return 3;
    }
    return 1;
  }

  String _unitDefault(String type) {
    switch (type) {
      case 'electric':
        return 'kWh';
      case 'property':
        return '元';
    }
    return 'm³';
  }

  /// tiers 编辑器行：cap 文本 '' = ∞（末档）
  List<Map<String, TextEditingController>> _makeRows(
      String type, List? src) {
    if (src != null && src.isNotEmpty) {
      return src.map((e) {
        final m = e as Map;
        final cap = m['cap'];
        return {
          'cap': TextEditingController(text: _fmtNum(cap)),
          'price': TextEditingController(text: _fmtNum(m['price'])),
        };
      }).toList();
    }
    if (type == 'property') {
      return [
        {'cap': TextEditingController(text: ''), 'price': TextEditingController(text: '82')}
      ];
    }
    return _defaultTiers(type).map((e) => {
          'cap': TextEditingController(text: e['cap']!),
          'price': TextEditingController(text: e['price']!),
        }).toList();
  }

  /// 数字显示：41 → '41'，3.5 → '3.5'，避免 '41.0'
  String _fmtNum(dynamic v) {
    if (v == null) return '';
    if (v is int) return '$v';
    if (v is double) {
      return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    }
    return '$v';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _spanCtrl.dispose();
    _unitCtrl.dispose();
    for (final row in _rows) {
      row['cap']!.dispose();
      row['price']!.dispose();
    }
    for (final row in _seasonRows) {
      row['cap']!.dispose();
      row['price']!.dispose();
    }
    super.dispose();
  }

  void _changeType(String type) {
    setState(() {
      _type = type;
      _nameCtrl.text = '';
      _spanCtrl.text = '${_spanDefault(type)}';
      _unitCtrl.text = _unitDefault(type);
      _seasonOn = false;
      _seasonMonths.clear();
      _seasonMonths.addAll({5, 6, 7, 8, 9, 10});
      for (final row in _rows) {
        row['cap']!.dispose();
        row['price']!.dispose();
      }
      _rows
        ..clear()
        ..addAll(_makeRows(type, null));
      for (final row in _seasonRows) {
        row['cap']!.dispose();
        row['price']!.dispose();
      }
      _seasonRows
        ..clear()
        ..addAll(_makeRows(type, null));
    });
  }

  /// 加载支出分类（规则可选绑定任意消费分类）
  Future<void> _loadCats() async {
    try {
      final all = await ref.read(localApiProvider).getCategories();
      if (!mounted) return;
      setState(() {
        _cats = all.where((c) => c.type == 'expense').toList();
      });
    } catch (_) {}
  }

  /// 归一化档位：过滤单价<=0；末行 cap 若非空自动补 ∞ 行；空列表返回 null
  List<Map<String, dynamic>>? _norm(List<Map<String, TextEditingController>> rows) {
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final price = double.tryParse(row['price']!.text.trim());
      if (price == null || price <= 0) continue;
      final capRaw = row['cap']!.text.trim();
      out.add({
        'cap': capRaw.isEmpty ? null : double.tryParse(capRaw),
        'price': price,
      });
    }
    if (out.isEmpty) return null;
    if (out.last['cap'] != null) {
      out.add({'cap': null, 'price': out.last['price']});
    }
    return out;
  }

  Future<void> _save() async {
    final from = _fromCtrl.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(from)) {
      toast('请选择生效起始月');
      return;
    }
    final to = _toCtrl.text.trim();
    if (to.isNotEmpty && !RegExp(r'^\d{4}-\d{2}$').hasMatch(to)) {
      toast('结束月格式不对');
      return;
    }
    final tiers = _norm(_rows);
    if (tiers == null) {
      toast('至少填写一个有效档位（单价>0）');
      return;
    }
    final span = int.tryParse(_spanCtrl.text.trim()) ?? 0;
    if (span < 1) {
      toast('覆盖月数至少为 1');
      return;
    }
    final body = <String, dynamic>{
      'type': _type,
      'name': _nameCtrl.text.trim().isEmpty
          ? '${utilityLabel(_type)}规则'
          : _nameCtrl.text.trim(),
      'category': _category,
      'effective_from': from,
      'effective_to': to,
      'bill_span': span,
      'cycle_type': _type == 'gas' ? 'by_year' : 'by_span',
      'unit': _unitCtrl.text.trim().isEmpty ? _unitDefault(_type) : _unitCtrl.text.trim(),
      'tiers': tiers,
    };
    if (_type == 'electric') {
      if (_seasonOn) {
        final st = _norm(_seasonRows);
        if (st == null) {
          toast('夏季档至少一个有效档位');
          return;
        }
        if (_seasonMonths.isEmpty) {
          toast('请选择夏季月份');
          return;
        }
        final months = _seasonMonths.toList()..sort();
        body['season'] = {'months': months, 'tiers': st};
      } else {
        body['season'] = null;
      }
    }
    if (_type == 'property') {
      final monthly =
          double.tryParse(_rows.first['price']!.text.trim()) ?? 0;
      body['monthly_fee'] = monthly > 0 ? monthly : null;
    }
    setState(() => _saving = true);
    try {
      final api = ref.read(localApiProvider);
      if (_editing) {
        await api.updateUtilityRule(
            ((widget.editRule!['id'] as num)).toInt(), body);
        toast('已更新');
      } else {
        await api.createUtilityRule(body);
        toast('已新建');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteRule() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除规则'),
        content: const Text('删除后不再按此规则生成账单；已生成的账单会保留。确定删除？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(localApiProvider)
          .deleteUtilityRule(((widget.editRule!['id'] as num)).toInt());
      toast('已删除');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      toast('删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProp = _type == 'property';
    final isElec = _type == 'electric';
    final isGas = _type == 'gas';
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑规则' : '新建规则'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: '删除规则',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteRule,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_editing) ...[
            Text('类型', style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: kUtilityTypes.map((t) {
              final type = t['type']!;
              final active = type == _type;
              return ChoiceChip(
                label: Text('${t['icon']}${t['label']}'),
                selected: active,
                onSelected: (_) => _changeType(type),
              );
            }).toList()),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _nameCtrl,
            decoration: _dec('规则名称（如：广州水费）'),
          ),
          const SizedBox(height: 14),
          Text('关联分类（识别该分类下名称含「水费/电费/燃气费/物业费」的支出流水）',
              style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            ..._cats.map((c) => ChoiceChip(
                  avatar: Text(c.icon, style: const TextStyle(fontSize: 14)),
                  label: Text(c.name),
                  selected: _category == c.name,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _category = c.name),
                )),
            // 已选分类不在列表（历史分类已被删除）时仍保留显示
            if (!_cats.any((c) => c.name == _category))
              ChoiceChip(
                label: Text('$_category（已删除）'),
                selected: true,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {},
              ),
          ]),
          if (_cats.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('未加载到分类，将使用默认分类「住房」',
                  style: TextStyle(
                      fontSize: 11, color: AppPalette.textSecondary(context))),
            ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _ymTile('生效起始月', _fromCtrl,
                  (v) => _fromCtrl.text = v),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ymTile('生效结束月（可选）', _toCtrl, (v) => _toCtrl.text = v,
                  allowClear: true),
            ),
          ]),
          const SizedBox(height: 4),
          Text('生效起始月之前、结束月之后的流水不会自动计入（搬家/调价可新开一段）',
              style: TextStyle(fontSize: 11, color: AppPalette.textSecondary(context))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _spanCtrl,
                keyboardType: TextInputType.number,
                decoration: _dec(isProp
                    ? '覆盖月数（季度预付=3）'
                    : isGas
                        ? '覆盖月数（隔月缴费=2）'
                        : '覆盖月数（每月=1）'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unitCtrl,
                decoration: _dec('计量单位'),
              ),
            ),
          ]),
          // v2.2.6：快捷月数 chips（物业/水/电常用 1/3/4/6/12 月；燃气默认 2 月不让改）
          if (!isGas) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final n in const [1, 3, 4, 6, 12])
                  ChoiceChip(
                    label: Text('${n}月'),
                    selected: (int.tryParse(_spanCtrl.text) ?? 0) == n,
                    onSelected: (_) {
                      setState(() => _spanCtrl.text = '$n');
                    },
                  ),
              ],
            ),
          ],
          if (isGas) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppPalette.cardSubtle(context),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('燃气费按「年累计金额」分档：一年内缴费金额累计跨档后自动升档，次年归零。',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
          const SizedBox(height: 16),
          Text(isProp ? '月费（每覆盖月费用）' : '档位（上限留空=最高档不限量；末档自动为 ∞）',
              style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
          const SizedBox(height: 6),
          ..._tierEditor(_rows),
          if (isElec) ...[
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用夏季档（5~10月）', style: TextStyle(fontSize: 14)),
              subtitle: Text(_seasonOn
                  ? '夏季月份使用下方夏季档，其余月份用上方普通档'
                  : '全年使用上方普通档',
                  style: TextStyle(fontSize: 11, color: AppPalette.textSecondary(context))),
              value: _seasonOn,
              onChanged: (v) => setState(() => _seasonOn = v),
            ),
            if (_seasonOn) ...[
              const SizedBox(height: 4),
              Text('夏季月份', style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (var i = 1; i <= 12; i++)
                  FilterChip(
                    label: Text('$i月'),
                    selected: _seasonMonths.contains(i),
                    visualDensity: VisualDensity.compact,
                    onSelected: (on) => setState(() {
                      if (on) {
                        _seasonMonths.add(i);
                      } else {
                        _seasonMonths.remove(i);
                      }
                    }),
                  ),
              ]),
              const SizedBox(height: 10),
              Text('夏季档位（上限留空=不限量）',
                  style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
              const SizedBox(height: 6),
              ..._tierEditor(_seasonRows),
            ],
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _ymTile(String label, TextEditingController ctrl,
      ValueChanged<String> onPick, {bool allowClear = false}) {
    // v260911-12：用户反馈「弹窗选月份后 UI 仍显示旧月份」BUG 修：
    //   原实现 onPick 只 set ctrl.text，不触发父 rebuild → 控件显示快照失效。
    //   现改为 StatefulBuilder 让 pickMonth 回调触发局部 setState。
    return StatefulBuilder(builder: (ctx, setSt) {
      final val = ctrl.text;
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final p = await pickMonth(context,
              initial: val.isEmpty ? ym2(DateTime.now()) : val);
          if (p != null) {
            setSt(() {
              ctrl.text = p;
            });
            onPick(p);
          }
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppPalette.divider(context)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: AppPalette.textSecondary(context))),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(
                    child: Text(
                      val.isEmpty ? '永久（不设结束）' : val,
                      style: TextStyle(
                          fontSize: 14,
                          color: val.isEmpty
                              ? AppPalette.textSecondary(context)
                              : AppPalette.text(context)),
                    ),
                  ),
                  if (allowClear && val.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setSt(() {
                          ctrl.text = '';
                        });
                        onPick('');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close,
                            size: 14, color: AppPalette.textSecondary(context)),
                      ),
                    ),
                  Icon(Icons.calendar_month,
                      size: 15, color: AppPalette.textSecondary(context)),
                ]),
              ]),
        ),
      );
    });
  }

  List<Widget> _tierEditor(List<Map<String, TextEditingController>> rows) {
    return [
      for (var i = 0; i < rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: rows[i]['cap'],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec(i == rows.length - 1 ? '上限 ∞' : '上限'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('→'),
            ),
            Expanded(
              child: TextField(
                controller: rows[i]['price'],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec('单价'),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              onPressed: rows.length > 1
                  ? () {
                      setState(() {
                        rows[i]['cap']!.dispose();
                        rows[i]['price']!.dispose();
                        rows.removeAt(i);
                      });
                    }
                  : null,
            ),
          ]),
        ),
      Row(children: [
        TextButton.icon(
          onPressed: () => setState(() {
            rows.add({
              'cap': TextEditingController(),
              'price': TextEditingController(),
            });
          }),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加一行'),
        ),
      ]),
    ];
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );
}
