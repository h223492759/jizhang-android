import 'dart:async';

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/category_icon.dart';
import 'package:jizhang_android/core/local_first_api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/owner_color.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/components/flow_row.dart';
import 'package:jizhang_android/screens/record/flow_detail_page.dart';
import 'package:jizhang_android/state/session.dart';

/// v2.2.17：关键字搜索流水（发现页右上角放大镜进入）
///
/// 语义与网页端「搜索流水」弹窗一致：
/// - 关键字按流水名称 `description` LIKE 匹配（本地库查询，offline-first）
/// - 默认搜「全部时间」，不限月份/年份
/// - 顶部显示命中笔数与收支合计，点任意一条进明细
class SearchFlowsPage extends ConsumerStatefulWidget {
  const SearchFlowsPage({super.key});

  @override
  ConsumerState<SearchFlowsPage> createState() => _SearchFlowsPageState();
}

class _SearchFlowsPageState extends ConsumerState<SearchFlowsPage> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  List<Flow> _flows = [];
  List<Category> _cats = [];
  int _total = 0;
  double _expense = 0;
  double _income = 0;
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadCats() async {
    try {
      final cats = await ref.read(localApiProvider).getCategories();
      if (mounted) setState(() => _cats = cats);
    } catch (_) {
      // 分类图标取不到不影响搜索，静默忽略
    }
  }

  String _iconOf(String name) => catIconOf(buildCatIconMap(_cats), name);

  /// 输入防抖 300ms：边打边搜，但不必每敲一个字都查一次
  void _onChanged(String v) {
    if (mounted) setState(() {}); // 让清除按钮（suffixIcon）随输入即时出现/消失
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    final kw = _ctrl.text.trim();
    if (kw.isEmpty) {
      setState(() {
        _flows = [];
        _total = 0;
        _expense = 0;
        _income = 0;
        _searched = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final fp = await ref
          .read(localApiProvider)
          .getFlows(keyword: kw, pageSize: 500);
      if (mounted) {
        setState(() {
          _flows = fp.list;
          _total = fp.total;
          _expense = fp.expense;
          _income = fp.income;
          _searched = true;
        });
      }
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overrides = ref.watch(ownerColorsProvider);
    final user = ref.watch(sessionProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('搜索流水')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '按名称搜索，如「奶茶」「超市」',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _ctrl.clear();
                          _search();
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          if (_searched && !_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: Row(
                children: [
                  Text('共 $_total 笔',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppPalette.textSecondary(context))),
                  const Spacer(),
                  Text('支出 ¥${fmtMoney(_expense)}　收入 ¥${fmtMoney(_income)}',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppPalette.textSecondary(context))),
                ],
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: !_searched
                ? Center(
                    child: Text('输入关键字开始搜索',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppPalette.textSecondary(context))),
                  )
                : _flows.isEmpty
                    ? const Center(child: Text('没有匹配的流水'))
                    : ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        children: buildGroupedFlows(
                          context,
                          flows: _flows,
                          tileBuilder: (f) => compactFlowTile(
                            context,
                            f: f,
                            iconBg: ownerColorFor(f, overrides, user),
                            iconChar: _iconOf(f.category),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => FlowDetailPage(flow: f)),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
