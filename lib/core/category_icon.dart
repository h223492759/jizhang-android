import 'package:jizhang_android/core/models.dart';

/// 分类图标统一：返回「分类名 -> emoji 图标」映射（来自后端 Category.icon）。
Map<String, String> buildCatIconMap(List<Category> cats) {
  final m = <String, String>{};
  for (final c in cats) {
    if (c.name.isNotEmpty) m[c.name] = c.icon;
  }
  return m;
}

/// 取某分类的图标字符；找不到时回退到默认💰（不再用汉字兜底）。
String catIconOf(Map<String, String> iconMap, String name) {
  if (name.isEmpty) return '💰';
  return iconMap[name] ?? '💰';
}
