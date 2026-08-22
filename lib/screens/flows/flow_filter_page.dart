import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/core/owner_color.dart';
import 'package:jizhang_android/core/category_icon.dart';
import 'package:jizhang_android/components/flow_row.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/record/flow_detail_page.dart';
import 'package:jizhang_android/core/local_first_api.dart';

class FlowFilterPage extends ConsumerStatefulWidget {
  final String? category;
  final String? type;
  final String? start;
  final String? end;
  final String title;
  const FlowFilterPage({
    super.key,
    this.category,
    this.type,
    this.start,
    this.end,
    required this.title,
  });

  @override
  ConsumerState<FlowFilterPage> createState() => _FlowFilterPageState();
}

class _FlowFilterPageState extends ConsumerState<FlowFilterPage> {
  List<Flow> _flows = [];
  List<Category> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _iconOf(String name) => catIconOf(buildCatIconMap(_cats), name);

  Future<void> _load() async {
    try {
      final api = ref.read(localApiProvider);
      final fp = await api.getFlows(
            category: widget.category,
            type: widget.type,
            start: widget.start,
            end: widget.end,
            pageSize: 500,
          );
      final cats = await api.getCategories();
      if (mounted) {
        setState(() {
          _flows = fp.list;
          _cats = cats;
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
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _flows.isEmpty
              ? const Center(child: Text('暂无记录'))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  children: buildGroupedFlows(
                    flows: _flows,
                    tileBuilder: (f) => compactFlowTile(context,
                      f: f,
                      iconBg: ownerColorFor(f, overrides, user),
                      iconChar: _iconOf(f.category),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => FlowDetailPage(flow: f)),
                      ),
                    ),
                  ),
                ),
    );
  }
}
