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
}

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.text,
          elevation: 0,
          centerTitle: true,
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
      );
}
