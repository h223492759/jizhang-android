import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';
import 'package:jizhang_android/core/category_icon.dart';
import 'package:jizhang_android/core/owner_color.dart';
import 'package:jizhang_android/state/session.dart';

class FlowDetailPage extends ConsumerStatefulWidget {
  final Flow flow;
  const FlowDetailPage({super.key, required this.flow});

  @override
  ConsumerState<FlowDetailPage> createState() => _FlowDetailPageState();
}

class _FlowDetailPageState extends ConsumerState<FlowDetailPage> {
  late List<Category> _cats;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _cats = [];
    _load();
  }

  Future<void> _load() async {
    try {
      _cats = await ref.read(apiProvider).getCategories();
    } catch (_) {
      _cats = [];
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.flow;
    final expense = f.isExpense;
    final date = parseYmd(datePart(f.flowTime));
    final iconMap = buildCatIconMap(_cats);
    final user = ref.watch(sessionProvider).user;
    final ownerColor = ownerColorFor(f, ref.watch(ownerColorsProvider), user);
    final ownerLabel = f.attribution.isEmpty ? '我' : f.attribution;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('查看明细'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.primary,
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    catIconOf(iconMap, f.category),
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  f.category,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('类型', expense ? '支出' : '收入'),
                  const Divider(height: 24),
                  _row('金额', '${expense ? '-' : '+'}${fmtMoney(f.amount)}',
                      valueColor: expense ? AppColors.expense : AppColors.income),
                  const Divider(height: 24),
                  _row('日期', '${ymd(date)} ${weekdayCn(date)}'),
                  if (flow.description.isNotEmpty) ...[
                    const Divider(height: 24),
                    _row('名称', flow.description),
                  ],
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Text('归属人',
                          style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: ownerColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              ownerLabel,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.text),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: valueColor ?? AppColors.text),
          ),
        ),
      ],
    );
  }
}
