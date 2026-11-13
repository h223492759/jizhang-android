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

/// 纯文本处展示用：分类 icon 可能存 "svg:<字形名>"（网页端挑选的矢量图标覆盖），
/// 没有对应 emoji 字符，剥离前缀返回空串，避免原样显示 "svg:xxx"。
String plainCatIcon(String? icon) {
  final s = (icon ?? '').trim();
  return s.startsWith('svg:') ? '' : s;
}
