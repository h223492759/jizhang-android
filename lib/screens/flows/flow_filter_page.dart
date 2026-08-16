import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/api.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/state/session.dart';
import 'package:jizhang_android/screens/record/flow_detail_page.dart';

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fp = await ref.read(apiProvider).getFlows(
            category: widget.category,
            type: widget.type,
            start: widget.start,
            end: widget.end,
            pageSize: 500,
          );
      if (mounted) setState(() => _flows = fp.list);
    } catch (e) {
      toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _flows.isEmpty
              ? const Center(child: Text('暂无记录'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _flows.length,
                  itemBuilder: (_, i) {
                    final f = _flows[i];
                    final expense = f.isExpense;
                    return Card(
                      child: ListTile(
                        title: Text(f.category),
                        subtitle: Text('${datePart(f.flowTime)} ${f.description}'),
                        trailing: Text('${expense ? '-' : '+'}${fmtMoney(f.amount)}',
                            style: TextStyle(
                                color: expense ? AppColors.expense : AppColors.income,
                                fontWeight: FontWeight.bold)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FlowDetailPage(flow: f)),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
