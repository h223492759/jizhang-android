import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:jizhang_android/core/cat_icon_names.dart';

/// 分类矢量图标（icon-proposal 图标集，与网页端共用同一套 SVG 源）：
/// - assets/icons/g/<名>.svg   深线字形 → 配浅色圆底（本人 / 中性底）
/// - assets/icons/gw/<名>.svg  白线字形 → 配彩色圆底（好友 / 归属人专属色）
/// 名字不在 kCatIconNames（分类 + 储备池全集）里时（如用户自建分类）回退 emoji。
///
/// 圆底色沿用既有归属人逻辑（ownerColorFor）：本人浅灰、归属人专属色，
/// 字形深/白按圆底亮度自动选择，保证彩底上也看得清。
class CatIcon extends StatelessWidget {
  final String name; // 分类名（= SVG 文件名）
  final Color bg; // 圆底色
  final double size; // 圆直径
  final String emoji; // 无对应 SVG 时的兜底 emoji

  const CatIcon({
    super.key,
    required this.name,
    required this.bg,
    this.size = 36,
    this.emoji = '💰',
  });

  static const double _glyphRatio = 0.84; // 字形占圆直径比例（SVG 字形外径≈84%）

  static bool _hasSvg(String name) => kCatIconNames.contains(name);

  /// 圆底亮度 → 选深线(g)或白线(gw)
  static bool _preferWhiteInk(Color c) {
    final lum =
        (0.299 * c.red + 0.587 * c.green + 0.114 * c.blue) / 255 * c.opacity;
    return lum < 0.62;
  }

  @override
  Widget build(BuildContext context) {
    // 图标覆盖：emoji 传 "svg:<字形名>"（网页端编辑分类挑选的矢量图标，可与分类名不同）
    String glyph = name;
    final e = emoji.trim();
    if (e.startsWith('svg:')) {
      final g = e.substring(4).trim();
      if (g.isNotEmpty && _hasSvg(g)) glyph = g;
    }
    Widget child;
    if (_hasSvg(glyph)) {
      final ink = _preferWhiteInk(bg) ? 'gw' : 'g';
      final d = size * _glyphRatio;
      child = SvgPicture.asset(
        'assets/icons/$ink/$glyph.svg',
        width: d,
        height: d,
        // 字形颜色已烘焙进文件（g=#222 / gw=#FFF），这里不做二次着色
      );
    } else {
      // 覆盖名无对应字形时不再原样显示 "svg:xxx"，回退默认 emoji
      child = Text(e.startsWith('svg:') ? '💰' : emoji,
          style: TextStyle(fontSize: size * 0.44));
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: child,
    );
  }
}
