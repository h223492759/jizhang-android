import 'package:flutter/material.dart' hide Flow;
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/theme.dart';
import 'package:jizhang_android/core/util.dart';

/// 首页风格的紧凑流水行：左侧分类图标（带归属人底色），名称单行省略，右侧带符号金额。
/// 图标 / 名称 / 金额 各自可绑定独立的点击行为（无嵌套手势冲突）：
/// - onIconTap  → 点图标
/// - onNameTap  → 点名称
/// - onAmountTap → 点金额
/// 若某项未单独指定，则回退到 onTap（整行通用点击，如查看明细）。
/// - onLongPress → 整行长按（如首页弹出操作菜单）
Widget compactFlowTile({
  required Flow f,
  required Color iconBg,
  required String iconChar,
  VoidCallback? onTap,
  VoidCallback? onIconTap,
  VoidCallback? onNameTap,
  VoidCallback? onAmountTap,
  VoidCallback? onLongPress,
}) {
  final expense = f.isExpense;
  final name = f.description.isNotEmpty ? f.description : f.category;

  Widget _tap(VoidCallback? cb, Widget child) => cb == null
      ? child
      : GestureDetector(
          onTap: cb,
          behavior: HitTestBehavior.opaque,
          child: child,
        );

  Widget row = Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      _tap(onIconTap ?? onTap,
          CircleAvatar(radius: 18, backgroundColor: iconBg, child: Text(iconChar, style: const TextStyle(fontSize: 16)))),
      const SizedBox(width: 10),
      Expanded(
        child: _tap(
          onNameTap ?? onTap,
          Row(
            children: [
              if (f.isAiSource) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
                    ],
                  ),
                  child: const Text('AI',
                      style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: AppColors.text)),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 8),
      _tap(
        onAmountTap ?? onTap,
        Text('${expense ? '-' : '+'}${fmtMoney(f.amount)}',
            style: TextStyle(
                color: expense ? AppColors.expense : AppColors.income,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      ),
    ],
  );
  if (onLongPress != null) {
    row = GestureDetector(onLongPress: onLongPress, child: row);
  }
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: row,
  );
}

/// 把流水按日期分组，返回可直接放进 SliverList / ListView 的 widget 列表。
/// 每个日期分组前加一行「m月d日 周X」标题，并用 1 像素横线与上一天分开。
List<Widget> buildGroupedFlows({
  required List<Flow> flows,
  required Widget Function(Flow) tileBuilder,
  bool showDateHeader = true,
}) {
  final grouped = <String, List<Flow>>{};
  for (final f in flows) {
    final d = datePart(f.flowTime);
    (grouped[d] ??= []).add(f);
  }
  final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  final out = <Widget>[];
  for (final k in keys) {
    if (showDateHeader) {
      DateTime? dt;
      try {
        dt = parseYmd(k);
      } catch (_) {
        dt = null;
      }
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(
          dt != null ? '${dt.month}月${dt.day}日 ${weekdayCn(dt)}' : k,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ));
    }
    for (final f in grouped[k]!) {
      out.add(tileBuilder(f));
    }
    out.add(const Divider(height: 1, thickness: 1, color: AppColors.divider));
  }
  return out;
}
