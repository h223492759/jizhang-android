import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jizhang_android/core/models.dart';
import 'package:jizhang_android/core/storage.dart';
import 'package:jizhang_android/state/session.dart';

/// 归属人（多账号记账）底色：
/// - 本账号归属人（自己）用灰色；
/// - 其他归属人优先用本地设置底色，其次用后端返回的 attributionColor，最后用哈希兜底色。
final ownerColorsProvider =
    StateNotifierProvider<OwnerColorsNotifier, Map<String, String>>(
  (ref) => OwnerColorsNotifier(),
);

class OwnerColorsNotifier extends StateNotifier<Map<String, String>> {
  OwnerColorsNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    state = await Storage.getOwnerColors();
  }

  Future<void> setColor(String owner, String hex) async {
    final m = Map<String, String>.from(state);
    m[owner] = hex;
    state = m;
    await Storage.setOwnerColors(m);
  }

  Future<void> remove(String owner) async {
    final m = Map<String, String>.from(state);
    m.remove(owner);
    state = m;
    await Storage.setOwnerColors(m);
  }
}

/// 判断某条流水的归属人是否就是当前登录账号。
bool isSelfAttribution(String attribution, User? user) {
  if (attribution.isEmpty) return true;
  if (user == null) return true;
  return attribution == user.username || attribution == user.nickname;
}

Color parseColor(String hex, {Color fallback = Colors.grey}) {
  try {
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 3) h = h.split('').map((c) => c + c).join('');
    if (h.length == 6) h = 'ff$h';
    if (h.length != 8) return fallback;
    return Color(int.parse(h, radix: 16));
  } catch (_) {
    return fallback;
  }
}

Color _hashColor(String s) {
  int h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0xffffffff;
  }
  final hue = (h % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.55, 0.62).toColor();
}

/// 解析某条流水的图标底色（归属人底色）。
Color ownerColorFor(
    Flow f, Map<String, String> overrides, User? user) {
  if (isSelfAttribution(f.attribution, user)) {
    return Colors.grey.shade300;
  }
  final ov = overrides[f.attribution];
  if (ov != null && ov.isNotEmpty) return parseColor(ov);
  if (f.attributionColor != null && f.attributionColor!.isNotEmpty) {
    return parseColor(f.attributionColor!);
  }
  return _hashColor(f.attribution);
}
