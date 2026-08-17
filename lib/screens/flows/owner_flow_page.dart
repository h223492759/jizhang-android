import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/core/owner_color.dart';
import 'package:jizhang_android/components/flow_row.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/record/flow_detail_page.dart';

/// 某个归属人（账户）的流水明细：按金额由高到低降序，
/// 采用首页紧凑行样式（不显示日期分组）。
class OwnerFlowPage extends ConsumerStatefulWidget {
  final String attribution;
  final String title;
  final String start;
  final String end;
  final bool isSelf;
  const OwnerFlowPage({
    super.key,
    required this.attribution,
    required this.title,
    required this.start,
    required this.end,
    this.isSelf = false,
  });

  @override
  ConsumerState<OwnerFlowPage> createState() => _OwnerFlowPageState();
}

class _OwnerFlowPageState extends ConsumerState<OwnerFlowPage> {
  List<Flow> _flows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fp = await ref.read(apiProvider).getFlows(
            start: widget.start,
            end: widget.end,
            pageSize: 2000,
          );
      final matched = fp.list.where((f) => f.attribution == widget.attribution).toList();
      matched.sort((a, b) => b.amount.compareTo(a.amount));
      if (mounted) setState(() => _flows = matched);
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
      appBar: AppBar(title: Text('${widget.title}的流水')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _flows.isEmpty
              ? const Center(child: Text('暂无记录'))
              : ListView(
                  children: _flows.map((f) {
                    return compactFlowTile(
                      f: f,
                      iconBg: ownerColorFor(f, overrides, user),
                      iconChar: f.category.isNotEmpty ? f.category[0] : '·',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => FlowDetailPage(flow: f)),
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}
