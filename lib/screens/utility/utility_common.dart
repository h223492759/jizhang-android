import 'package:flutter/material.dart';
import 'package:jizhang_android/core/theme.dart';

/// 水电气物业用量：类型常量 / 单位 / 月份选择器（utility 页面与规则页共用）
const List<Map<String, String>> kUtilityTypes = [
  {'type': 'water', 'label': '水费', 'unit': 'm³', 'icon': '💧'},
  {'type': 'electric', 'label': '电费', 'unit': 'kWh', 'icon': '⚡'},
  {'type': 'gas', 'label': '燃气费', 'unit': 'm³', 'icon': '🔥'},
  {'type': 'property', 'label': '物业费', 'unit': '元', 'icon': '🏢'},
];

String utilityLabel(String type) {
  for (final t in kUtilityTypes) {
    if (t['type'] == type) return t['label']!;
  }
  return type;
}

String utilityUnitOf(String type) {
  for (final t in kUtilityTypes) {
    if (t['type'] == type) return t['unit']!;
  }
  return '';
}

String ym2(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// 通用月份选择弹层，返回 'YYYY-MM' 或 null（取消）
Future<String?> pickMonth(BuildContext context, {required String initial}) async {
  var y = int.tryParse(initial.length >= 4 ? initial.substring(0, 4) : '') ??
      DateTime.now().year;
  var m = int.tryParse(initial.length >= 7 ? initial.substring(5, 7) : '') ??
      DateTime.now().month;
  final now = DateTime.now();
  String? picked;
  await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setSt) {
        Widget chip(int mm) {
          final sel = mm == m;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              picked = '$y-${mm.toString().padLeft(2, '0')}';
              Navigator.pop(ctx, picked);
            },
            child: Container(
              width: 60,
              margin: const EdgeInsets.all(3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$mm月',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  color: sel
                      ? AppPalette.onPrimary(ctx)
                      : Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setSt(() => y -= 1),
                  ),
                  Text('$y 年',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: y < now.year + 3
                        ? () => setSt(() => y += 1)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                children: [for (var i = 1; i <= 12; i++) chip(i)],
              ),
            ]),
          ),
        );
      });
    },
  );
  return picked;
}
