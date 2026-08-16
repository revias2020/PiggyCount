import 'package:flutter/material.dart';

/// 小猪记账设计令牌（仅亮色，不做暗色模式）。
///
/// 所有业务 Widget 应优先使用本文件常量，避免魔法色值散落各处；
/// 主色对齐开发文档图 2–6 的蓝/紫气质，实现期可按视觉微调数值。
abstract final class PigTokens {
  // --- 品牌色 ---
  /// 主色：按钮、选中 Tab、关键强调
  static const Color primary = Color(0xFF2F6BFF);

  /// 主色浅底：选中胶囊、弱强调背景
  static const Color primarySoft = Color(0x1A2F6BFF);

  /// AI 浮动球 / 发送按钮用的紫蓝起点
  static const Color aiGradientStart = Color(0xFF6B5CFF);

  /// AI 渐变终点
  static const Color aiGradientEnd = Color(0xFF2F6BFF);

  /// AI 助手页背景渐变上沿
  static const Color aiCanvasTop = Color(0xFFE8F0FF);

  /// AI 助手页背景渐变中段
  static const Color aiCanvasMid = Color(0xFFF3EEFF);

  /// AI 次要 Chip 浅底
  static const Color aiChipSoft = Color(0x1A6B5CFF);

  // --- 表面 ---
  static const Color scaffoldBackground = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSecondary = Color(0xFFF5F5F5);
  static const Color surfaceInput = Color(0xFFF3F4F6);

  // --- 文字 ---
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0x8A000000);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textLink = Color(0xFF3B82F6);

  // --- 语义 ---
  static const Color expense = Color(0xFF111827);
  static const Color income = Color(0xFF16A34A);
  static const Color danger = Color(0xFFDC2626);

  // --- 尺寸 ---
  static const double radiusCard = 12;
  static const double radiusPill = 20;
  /// 底部弹层顶角
  static const double radiusSheet = 16;
  static const double appBarHeight = 56;
  static const double bottomNavHeight = 56;

  // --- 间距（改页时优先用这些，避免魔法 EdgeInsets）---
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;

  /// 应用级 ThemeData（强制 light，忽略系统暗色）。
  static ThemeData lightTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        primary: primary,
      ),
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: surface,
        foregroundColor: textPrimary,
        centerTitle: false,
      ),
      dividerColor: const Color(0xFFE5E7EB),
      splashFactory: InkRipple.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
    );
  }
}
