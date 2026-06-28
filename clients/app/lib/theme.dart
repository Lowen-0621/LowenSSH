import 'package:flutter/material.dart';
import 'core/palette.dart';

/// 运行时配色 —— 字段由当前激活的 AppPalette 填充，支持主题切换。
///
/// 注意：字段是 `static Color`（非 const），所以调用点 **不能** 写
/// `const TextStyle(color: AppColors.text)`。默认值取 Mocha，保证
/// 首帧（applyPalette 调用前）也有正确颜色。
class AppColors {
  static Color base = Palettes.mocha.base; //       主背景
  static Color mantle = Palettes.mocha.mantle; //   次背景（侧栏）
  static Color crust = Palettes.mocha.crust; //     最深（终端/状态栏）
  static Color surface0 = Palettes.mocha.surface0; //边框/分隔
  static Color surface1 = Palettes.mocha.surface1; //高亮边框
  static Color surface2 = Palettes.mocha.surface2;
  static Color text = Palettes.mocha.text; //       主文字
  static Color subtext = Palettes.mocha.subtext; // 次文字
  static Color overlay = Palettes.mocha.overlay; // 暗淡文字
  static Color blue = Palettes.mocha.blue;
  static Color lavender = Palettes.mocha.lavender;
  static Color sapphire = Palettes.mocha.sapphire;
  static Color green = Palettes.mocha.green;
  static Color yellow = Palettes.mocha.yellow;
  static Color peach = Palettes.mocha.peach;
  static Color red = Palettes.mocha.red;
  static Color mauve = Palettes.mocha.mauve;
  static Color teal = Palettes.mocha.teal;
  static Color pink = Palettes.mocha.pink;
}

/// 当前激活的配色（默认 Mocha）
AppPalette _current = Palettes.mocha;
AppPalette get currentPalette => _current;

/// 应用一套配色到 AppColors。调用后需触发 UI rebuild（换 MaterialApp 的 theme）。
void applyPalette(AppPalette p) {
  _current = p;
  AppColors.base = p.base;
  AppColors.mantle = p.mantle;
  AppColors.crust = p.crust;
  AppColors.surface0 = p.surface0;
  AppColors.surface1 = p.surface1;
  AppColors.surface2 = p.surface2;
  AppColors.text = p.text;
  AppColors.subtext = p.subtext;
  AppColors.overlay = p.overlay;
  AppColors.blue = p.blue;
  AppColors.lavender = p.lavender;
  AppColors.sapphire = p.sapphire;
  AppColors.green = p.green;
  AppColors.yellow = p.yellow;
  AppColors.peach = p.peach;
  AppColors.red = p.red;
  AppColors.mauve = p.mauve;
  AppColors.teal = p.teal;
  AppColors.pink = p.pink;
}

/// 等宽字体族（终端、命令、监控数值用）
const String kMonoFont = 'monospace';

ThemeData buildTheme() {
  final base = ThemeData(brightness: _current.brightness, useMaterial3: true);
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
