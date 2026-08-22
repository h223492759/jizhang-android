import 'package:flutter/material.dart';
import 'package:jizhang_android/core/theme.dart';

/// 统一日期选择弹窗：周一为每周第一天，无顶部大标题/编辑按钮。
Future<DateTime?> pickSimpleDate(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: AppPalette.card(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _SimpleDatePickerSheet(
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
    ),
  );
}

class _SimpleDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  const _SimpleDatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_SimpleDatePickerSheet> createState() => _SimpleDatePickerSheetState();
}

class _SimpleDatePickerSheetState extends State<_SimpleDatePickerSheet> {
  late DateTime _displayed; // 当前展示的年月
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _displayed = DateTime(widget.initialDate.year, widget.initialDate.month, 1);
    _selected = widget.initialDate;
  }

  bool _isInRange(DateTime d) =>
      !d.isBefore(_startOfDay(widget.firstDate)) &&
      !d.isAfter(_startOfDay(widget.lastDate));

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  void _changeMonth(int delta) {
    setState(() {
      _displayed = DateTime(_displayed.year, _displayed.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateTime(_displayed.year, _displayed.month + 1, 0).day;
    // Monday 为每周第一天：DateTime.weekday 中 Monday=1, Sunday=7
    final leadingBlank = (_displayed.weekday - 1) % 7;
    final totalCells = leadingBlank + daysInMonth;
    final trailingBlank = (7 - (totalCells % 7)) % 7;
    final cells = totalCells + trailingBlank;

    final weekTitles = const ['一', '二', '三', '四', '五', '六', '日'];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 年月切换
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeMonth(-1),
                ),
                Text(
                  '${_displayed.year}年${_displayed.month}月',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 星期表头（周一开头）
            Row(
              children: weekTitles
                  .map((w) => Expanded(
                        child: Center(
                          child: Text(
                            w,
                            style: TextStyle(
                              color: w == '六' || w == '日'
                                  ? Colors.grey
                                  : Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            // 日期网格
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
              ),
              itemCount: cells,
              itemBuilder: (context, index) {
                if (index < leadingBlank) {
                  return const SizedBox.shrink();
                }
                final day = index - leadingBlank + 1;
                if (day > daysInMonth) return const SizedBox.shrink();
                final date =
                    DateTime(_displayed.year, _displayed.month, day);
                final enabled = _isInRange(date);
                final isSelected = _startOfDay(date) == _startOfDay(_selected);
                final isToday = _startOfDay(date) == _startOfDay(DateTime.now());
                return InkWell(
                  onTap: enabled
                      ? () => setState(() => _selected = date)
                      : null,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryDark
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: isToday && !isSelected
                          ? Border.all(color: AppColors.primaryDark, width: 1)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          color: !enabled
                              ? Colors.grey.shade300
                              : isSelected
                                  ? Colors.white
                                  : (w_sat_sun(date)
                                      ? Colors.grey
                                      : Colors.black87),
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('确定'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool w_sat_sun(DateTime d) => d.weekday == 6 || d.weekday == 7;
}
