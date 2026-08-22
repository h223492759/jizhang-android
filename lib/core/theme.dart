import 'package:flutter/material.dart';

class AppColors {
  // 主色：黄（复刻鲨鱼记账配色，不抄品牌 Logo/图标）
  static const primary = Color(0xFFFFD23F);
  static const primaryDark = Color(0xFFF7B500);
  static const primarySoft = Color(0xFFFFF3C4);

  static const background = Color(0xFFF6F7F9);
  static const card = Colors.white;
  static const divider = Color(0xFFEEEEEE);

  static const text = Color(0xFF222222);
  static const textSecondary = Color(0xFF888888);

  static const expense = Color(0xFFF04438); // 支出 红
  static const income = Color(0xFF2BA471); //  收入 绿

  static const blue = Color(0xFF3A7BFF);

  // 深色模式颜色（系统切换时使用）
  static const backgroundDark = Color(0xFF121212);
  static const cardDark = Color(0xFF1E1E1E);
  static const dividerDark = Color(0xFF2A2A2A);
  static const textDark = Color(0xFFEEEEEE);
  static const textSecondaryDark = Color(0xFFAAAAAA);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.backgroundDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: AppColors.textDark,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textDark),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
          primary: AppColors.primary,
          secondary: AppColors.income,
          surface: AppColors.cardDark,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.text,
        ),
        cardColor: AppColors.cardDark,
        dividerColor: AppColors.dividerDark,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: AppColors.textDark),
          bodyMedium: TextStyle(color: AppColors.textDark),
          bodySmall: TextStyle(color: AppColors.textSecondaryDark),
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.text,
          elevation: 0,
          centerTitle: true,
          // 统一缩小顶部标题字号（默认 Material3 约 22 偏大）
          titleTextStyle: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.income,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.text,
        ),
        cardTheme: CardTheme(
          color: AppColors.card,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        // 弹窗全局尺寸：标题/正文/按钮统一偏小，避免截图偏大看着拥挤
        dialogTheme: DialogTheme(
          titleTextStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
          contentTextStyle: const TextStyle(
              fontSize: 13, color: AppColors.text),
          // 内容过长时可滚动（避免弹出被屏幕截断）
          // 配合各 showDialog 调用在 content 用 SingleChildScrollView 包裹
        ),
      );
}

/// 响应 BuildContext 的颜色（深色模式自动切换）
class AppPalette {
  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color text(BuildContext c) => isDark(c) ? AppColors.textDark : AppColors.text;
  static Color textSecondary(BuildContext c) => isDark(c) ? AppColors.textSecondaryDark : AppColors.textSecondary;
  static Color background(BuildContext c) => isDark(c) ? AppColors.backgroundDark : AppColors.background;
  static Color card(BuildContext c) => isDark(c) ? AppColors.cardDark : AppColors.card;
  static Color divider(BuildContext c) => isDark(c) ? AppColors.dividerDark : AppColors.divider;
}
