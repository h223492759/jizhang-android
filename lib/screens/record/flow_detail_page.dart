import 'package:flutter/material.dart' hide Flow;
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';

class FlowDetailPage extends StatelessWidget {
  final Flow flow;
  const FlowDetailPage({super.key, required this.flow});

  @override
  Widget build(BuildContext context) {
    final expense = flow.isExpense;
    final date = parseYmd(datePart(flow.flowTime));
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
                    flow.category.isNotEmpty ? flow.category[0] : '·',
                    style: const TextStyle(fontSize: 32, color: AppColors.primaryDark),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  flow.category,
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
                  _row('金额', '${expense ? '-' : '+'}${fmtMoney(flow.amount)}',
                      valueColor: expense ? AppColors.expense : AppColors.income),
                  const Divider(height: 24),
                  _row('日期', '${ymd(date)} ${weekdayCn(date)}'),
                  if (flow.description.isNotEmpty) ...[
                    const Divider(height: 24),
                    _row('名称', flow.description),
                  ],
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
