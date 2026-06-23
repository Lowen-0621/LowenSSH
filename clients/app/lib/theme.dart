import 'package:flutter/material.dart';

/// Catppuccin Mocha 配色 —— 与 design/mockup.html 保持一致
/// 暗色专业 IDE 风，是 App 端视觉基线
class AppColors {
  static const base = Color(0xFF1E1E2E); // 主背景
  static const mantle = Color(0xFF181825); // 次背景（侧栏）
  static const crust = Color(0xFF11111B); // 最深（终端/状态栏）
  static const surface0 = Color(0xFF313244); // 边框/分隔
  static const surface1 = Color(0xFF45475A); // 高亮边框
  static const surface2 = Color(0xFF585B70);
  static const text = Color(0xFFCDD6F4); // 主文字
  static const subtext = Color(0xFFA6ADC8); // 次文字
  static const overlay = Color(0xFF6C7086); // 暗淡文字
  static const blue = Color(0xFF89B4FA);
  static const lavender = Color(0xFFB4BEFE);
  static const sapphire = Color(0xFF74C7EC);
  static const green = Color(0xFFA6E3A1);
  static const yellow = Color(0xFFF9E2AF);
  static const peach = Color(0xFFFAB387);
  static const red = Color(0xFFF38BA8);
  static const mauve = Color(0xFFCBA6F7);
  static const teal = Color(0xFF94E2D5);
  static const pink = Color(0xFFF5C2E7);
}

/// 等宽字体族（终端、命令、监控数值用）
const String kMonoFont = 'monospace';

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.base,
    colorScheme: base.colorScheme.copyWith(
      surface: AppColors.base,
      primary: AppColors.blue,
      secondary: AppColors.sapphire,
      error: AppColors.red,
      onSurface: AppColors.text,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
      fontFamily: '-apple-system',
    ),
    dividerColor: AppColors.surface0,
  );
}
