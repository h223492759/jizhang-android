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
            Text('分类 ${(r['category'] as String?)?.isNotEmpty == true ? r['category'] : '住房'} · 账期 $range',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(_coverBrief(type, r['cover'] as Map?),
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

/// v2.2.17 出账窗口 → 覆盖账期行（显式账期，取代「覆盖月数」文本框）
class _CovRow {
  final TextEditingController fromCtrl; // 窗口起始日
  final TextEditingController toCtrl; // 窗口结束日
  String key; // '-2_2' | '-1_2' | '-1_1' | '0_1' | 'q3' | '0_3'
  _CovRow(this.fromCtrl, this.toCtrl, this.key);
  int get start {
    if (key == 'q3') return 0;
    return int.parse(key.split('_')[0]);
  }

  int get span {
    if (key == 'q3') return 3;
    return int.parse(key.split('_')[1]);
  }

  bool get quarter => key == 'q3';
  Map<String, dynamic> toJson() => {
        'from': int.parse(fromCtrl.text.trim().isEmpty ? '1' : fromCtrl.text.trim()),
        'to': int.parse(toCtrl.text.trim().isEmpty ? '31' : toCtrl.text.trim()),
        'start': start,
        'span': span,
        if (quarter) 'quarter': true,
      };
}

// 覆盖方案（与网页 COV_PRESETS 一致；水/气双窗口、电/物业单窗口）
const Map<String, String> kCovLabel = {
  '-2_2': '上月 + 上上月',
  '-1_2': '当月 + 上月',
  '-1_1': '上月（单月）',
  '0_1': '当月（单月）',
  'q3': '缴费月所在自然季度（季度缴）',
  '0_3': '当月起连缴 3 个月',
};
List<String> _covKeys(String type) {
  if (type == 'property') return const ['q3', '0_1', '-1_1', '0_3'];
  if (type == 'electric') return const ['-1_1', '0_1', '-1_2'];
  return const ['-2_2', '-1_2', '-1_1', '0_1']; // water/gas
}
// 非法/自定义 key（不在下拉预设里）→ 回落该类型默认第一项，避免 Dropdown 断言崩溃
String _covKeySafe(String type, String key) =>
    _covKeys(type).contains(key) ? key : _covKeys(type).first;

// 后端 decorateRule 的 cover → 编辑行（缺省按类型默认，与后端 defaultCover 一致）
List<_CovRow> _coverRowsOf(String type, Map? cover) {
  final wins = (cover != null && cover['windows'] is List && (cover['windows'] as List).isNotEmpty)
      ? (cover['windows'] as List)
      : null;
  if (wins != null) {
    return wins.map((w) {
      final m = w as Map;
      final start = (m['start'] as num?)?.toInt() ?? 0;
      final span = (m['span'] as num?)?.toInt() ?? 1;
      final quarter = m['quarter'] == true;
      // (start,span,quarter) → 下拉预设 key；非预设组合回落该类型默认
      String key = quarter
          ? 'q3'
          : (start == -2 && span == 2)
              ? '-2_2'
              : (start == -1 && span == 2)
                  ? '-1_2'
                  : (start == -1 && span == 1)
                      ? '-1_1'
                      : (start == 0 && span == 1)
                          ? '0_1'
                          : (start == 0 && span == 3)
                              ? '0_3'
                              : '';
      key = _covKeySafe(type, key.isEmpty ? '${start}_$span' : key);
      return _CovRow(
        TextEditingController(text: '${m['from'] ?? 1}'),
        TextEditingController(text: '${m['to'] ?? 31}'),
        key,
      );
    }).toList();
  }
  if (type == 'water' || type == 'gas') {
    return [
      _CovRow(TextEditingController(text: '1'), TextEditingController(text: '15'), '-2_2'),
      _CovRow(TextEditingController(text: '16'), TextEditingController(text: '31'), '-1_2'),
    ];
  }
  if (type == 'electric') {
    return [_CovRow(TextEditingController(text: '1'), TextEditingController(text: '31'), '-1_1')];
  }
  return [_CovRow(TextEditingController(text: '1'), TextEditingController(text: '31'), 'q3')];
}

// 规则卡片摘要：出账窗口 → 覆盖账期（只读解析 cover，不建编辑器行）
String _coverBrief(String type, Map? cover) {
  final wins = (cover != null && cover['windows'] is List)
      ? (cover['windows'] as List).cast<Map>()
      : null;
  String keyOf(Map w) {
    final start = (w['start'] as num?)?.toInt() ?? 0;
    final span = (w['span'] as num?)?.toInt() ?? 1;
    if (w['quarter'] == true) return 'q3';
    if (start == -2 && span == 2) return '-2_2';
    if (start == -1 && span == 2) return '-1_2';
    if (start == -1 && span == 1) return '-1_1';
    if (start == 0 && span == 1) return '0_1';
    if (start == 0 && span == 3) return '0_3';
    return '';
  }

  String wText(Map w) {
    final k = keyOf(w);
    final lbl = (kCovLabel[k] ?? k)
        .replaceAll('（单月）', '')
        .replaceAll('（季度缴）', '')
        .replaceAll('（月初缴上月）', '');
    final from = '${w['from'] ?? 1}';
    final to = '${w['to'] ?? 31}';
    return w['quarter'] == true
        ? '季内任意一天 → $lbl'
        : (from == '1' && to == '31'
            ? '任意日 → $lbl'
            : '$from-$to号 → $lbl');
  }

  if (wins == null || wins.isEmpty) {
    // 老规则无 cover → 按类型默认语义描述
    if (type == 'water' || type == 'gas') {
      return '1-15号→覆盖上月+上上月；16-31号→覆盖当月+上月';
    }
    if (type == 'electric') return '任意日出账 → 覆盖上月';
    return type == 'property' ? '季度缴 → 覆盖缴费月所在自然季度' : '';
  }
  return wins.map(wText).join('；');
}

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
  late final TextEditingController _fromCtrl; // YYYY-MM 起始账期文本
  late final TextEditingController _toCtrl; // YYYY-MM 结束账期
  late final List<_CovRow> _covRows; // v2.2.17 出账窗口 → 覆盖账期
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
    _covRows = _coverRowsOf(_type, r?['cover'] as Map?);
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
    for (final row in _covRows) {
      row.fromCtrl.dispose();
      row.toCtrl.dispose();
    }
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
      _unitCtrl.text = _unitDefault(type);
      for (final row in _covRows) {
        row.fromCtrl.dispose();
        row.toCtrl.dispose();
      }
      _covRows
        ..clear()
        ..addAll(_coverRowsOf(type, null));
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
      toast('请选择起始账期（首个被覆盖月份）');
      return;
    }
    final to = _toCtrl.text.trim();
    if (to.isNotEmpty && !RegExp(r'^\d{4}-\d{2}$').hasMatch(to)) {
      toast('结束账期格式不对');
      return;
    }
    final tiers = _norm(_rows);
    if (tiers == null) {
      toast('至少填写一个有效档位（单价>0）');
      return;
    }
    // v2.2.17：出账窗口合法性（1~31 且起始≤结束）
    for (final row in _covRows) {
      final f = int.tryParse(row.fromCtrl.text.trim());
      final t = int.tryParse(row.toCtrl.text.trim());
      if (f == null || t == null || f < 1 || f > 31 || t < f || t > 31) {
        toast('出账日窗口需为 1~31 且起始 ≤ 结束');
        return;
      }
    }
    final span = _covRows.map((r) => r.span).fold(1, (a, b) => a > b ? a : b);
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
      'cover': {
        'windows': _covRows.map((r) => r.toJson()).toList(),
      },
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
              child: _ymTile('起始账期（首个覆盖月）', _fromCtrl,
                  (v) => _fromCtrl.text = v),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ymTile('结束账期（可选）', _toCtrl, (v) => _toCtrl.text = v,
                  allowClear: true),
            ),
          ]),
          const SizedBox(height: 4),
          Text('「起始账期」是首个被覆盖的月份：水费选 2024-02 → 首期覆盖 2~3 月、首笔流水约 3 月下旬；起始账期之前的流水不计入。',
              style: TextStyle(fontSize: 11, color: AppPalette.textSecondary(context))),
          const SizedBox(height: 12),
          _coverEditor(),
          const SizedBox(height: 10),
          TextField(
            controller: _unitCtrl,
            decoration: _dec('计量单位（m³ / kWh / 元）'),
          ),
          if (isGas) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppPalette.cardSubtle(context),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('燃气费按「年累计金额」分档：覆盖账期落在同一年内的账单按年累计跨档自动升档，次年归零。',
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

  /// v2.2.17 出账窗口 → 覆盖账期编辑器（行 = 一个出账日窗口 + 覆盖方案下拉）
  Widget _coverEditor() {
    final twoCond = _type == 'water' || _type == 'gas';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        twoCond
            ? '出账窗口 → 覆盖账期（两个条件互斥：一笔流水只命中一个窗口）'
            : (_type == 'property'
                ? '出账窗口 → 覆盖账期（季内任一天缴都算该季度）'
                : '出账窗口 → 覆盖账期（月初缴上月用量）'),
        style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
      ),
      const SizedBox(height: 6),
      for (var i = 0; i < _covRows.length; i++) ...[
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          decoration: BoxDecoration(
            color: AppPalette.cardSubtle(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(twoCond ? '条件 ${i + 1}：' : '出账日：',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textSecondary(context))),
              const SizedBox(width: 8),
              if (!_covRows[i].quarter) ...[
                SizedBox(
                  width: 68,
                  child: TextField(
                    controller: _covRows[i].fromCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec('起始日'),
                  ),
                ),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('—')),
                SizedBox(
                  width: 68,
                  child: TextField(
                    controller: _covRows[i].toCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec('结束日'),
                  ),
                ),
                const SizedBox(width: 4),
                const Text('号', style: TextStyle(fontSize: 13)),
              ] else
                const Expanded(
                    child: Text('季内任意一天',
                        style: TextStyle(fontSize: 13))),
              const Spacer(),
              if (_covRows.length > 1)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    final rm = _covRows.removeAt(i);
                    rm.fromCtrl.dispose();
                    rm.toCtrl.dispose();
                  }),
                ),
            ]),
            Row(children: [
              const Padding(
                padding: EdgeInsets.only(left: 2, right: 6),
                child: Text('→ 覆盖', style: TextStyle(fontSize: 13)),
              ),
              Expanded(
                child: DropdownButton<String>(
                  value: _covRows[i].key,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(
                      fontSize: 13, color: AppPalette.text(context)),
                  items: _covKeys(_type).map((k) {
                    return DropdownMenuItem(
                        value: k, child: Text(kCovLabel[k] ?? k));
                  }).toList(),
                  onChanged: (v) =>
                      setState(() => _covRows[i].key = v ?? _covRows[i].key),
                ),
              ),
            ]),
          ]),
        ),
        if (i < _covRows.length - 1) const SizedBox(height: 2),
      ],
      if (twoCond)
        TextButton.icon(
          onPressed: () => setState(() {
            _covRows.add(_CovRow(
                TextEditingController(text: '1'),
                TextEditingController(text: '15'),
                '-2_2'));
          }),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('加条件'),
        ),
    ]);
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
