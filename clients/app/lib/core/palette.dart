import 'package:flutter/material.dart';

/// 一套配色方案的数据载体。字段与 theme.dart 的 AppColors 一一对应。
/// 新增配色只需 new 一个 AppPalette 实例，不必改调用点。
class AppPalette {
  final String id; //        持久化用的稳定标识
  final String name; //      显示名
  final Brightness brightness; // 亮/暗，给 Flutter ThemeData 用

  final Color base; //       主背景
  final Color mantle; //     次背景（侧栏）
  final Color crust; //      最深（终端/状态栏）
  final Color surface0; //   边框/分隔
  final Color surface1; //   高亮边框
  final Color surface2;
  final Color text; //       主文字
  final Color subtext; //    次文字
  final Color overlay; //    暗淡文字
  final Color blue;
  final Color lavender;
  final Color sapphire;
  final Color green;
  final Color yellow;
  final Color peach;
  final Color red;
  final Color mauve;
  final Color teal;
  final Color pink;

  const AppPalette({
    required this.id,
    required this.name,
    required this.brightness,
    required this.base,
    required this.mantle,
    required this.crust,
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.text,
    required this.subtext,
    required this.overlay,
    required this.blue,
    required this.lavender,
    required this.sapphire,
    required this.green,
    required this.yellow,
    required this.peach,
    required this.red,
    required this.mauve,
    required this.teal,
    required this.pink,
  });
}

/// 内置配色方案。均来自 Catppuccin 官方色板，结构一致只是色号不同。
/// Mocha = 当前默认（暗）；Macchiato/Frappe 是偏暖的暗色；Latte 是亮色。
class Palettes {
  /// Catppuccin Mocha（深暗，原默认）
  static const mocha = AppPalette(
    id: 'mocha',
    name: 'Mocha 深暗',
    brightness: Brightness.dark,
    base: Color(0xFF1E1E2E),
    mantle: Color(0xFF181825),
    crust: Color(0xFF11111B),
    surface0: Color(0xFF313244),
    surface1: Color(0xFF45475A),
    surface2: Color(0xFF585B70),
    text: Color(0xFFCDD6F4),
    subtext: Color(0xFFA6ADC8),
    overlay: Color(0xFF6C7086),
    blue: Color(0xFF89B4FA),
    lavender: Color(0xFFB4BEFE),
    sapphire: Color(0xFF74C7EC),
    green: Color(0xFFA6E3A1),
    yellow: Color(0xFFF9E2AF),
    peach: Color(0xFFFAB387),
    red: Color(0xFFF38BA8),
    mauve: Color(0xFFCBA6F7),
    teal: Color(0xFF94E2D5),
    pink: Color(0xFFF5C2E7),
  );

  /// Catppuccin Macchiato（暗，比 Mocha 略亮偏暖）
  static const macchiato = AppPalette(
    id: 'macchiato',
    name: 'Macchiato 暖暗',
    brightness: Brightness.dark,
    base: Color(0xFF24273A),
    mantle: Color(0xFF1E2030),
    crust: Color(0xFF181926),
    surface0: Color(0xFF363A4F),
    surface1: Color(0xFF494D64),
    surface2: Color(0xFF5B6078),
    text: Color(0xFFCAD3F5),
    subtext: Color(0xFFA5ADCB),
    overlay: Color(0xFF6E738D),
    blue: Color(0xFF8AADF4),
    lavender: Color(0xFFB7BDF8),
    sapphire: Color(0xFF7DC4E4),
    green: Color(0xFFA6DA95),
    yellow: Color(0xFFEED49F),
    peach: Color(0xFFF5A97F),
    red: Color(0xFFED8796),
    mauve: Color(0xFFC6A0F6),
    teal: Color(0xFF8BD5CA),
    pink: Color(0xFFF5BDE6),
  );

  /// Catppuccin Frappé（暗，更柔和的中间调）
  static const frappe = AppPalette(
    id: 'frappe',
    name: 'Frappé 柔暗',
    brightness: Brightness.dark,
    base: Color(0xFF303446),
    mantle: Color(0xFF292C3C),
    crust: Color(0xFF232634),
    surface0: Color(0xFF414559),
    surface1: Color(0xFF51576D),
    surface2: Color(0xFF626880),
    text: Color(0xFFC6D0F5),
    subtext: Color(0xFFA5ADCE),
    overlay: Color(0xFF737994),
    blue: Color(0xFF8CAAEE),
    lavender: Color(0xFFBABBF1),
    sapphire: Color(0xFF85C1DC),
    green: Color(0xFFA6D189),
    yellow: Color(0xFFE5C890),
    peach: Color(0xFFEF9F76),
    red: Color(0xFFE78284),
    mauve: Color(0xFFCA9EE6),
    teal: Color(0xFF81C8BE),
    pink: Color(0xFFF4B8E4),
  );

  /// Catppuccin Latte（亮色）
  static const latte = AppPalette(
    id: 'latte',
    name: 'Latte 亮色',
    brightness: Brightness.light,
    base: Color(0xFFEFF1F5),
    mantle: Color(0xFFE6E9EF),
    crust: Color(0xFFDCE0E8),
    surface0: Color(0xFFCCD0DA),
    surface1: Color(0xFFBCC0CC),
    surface2: Color(0xFFACB0BE),
    text: Color(0xFF4C4F69),
    subtext: Color(0xFF5C5F77),
    overlay: Color(0xFF8C8FA1),
    blue: Color(0xFF1E66F5),
    lavender: Color(0xFF7287FD),
    sapphire: Color(0xFF209FB5),
    green: Color(0xFF40A02B),
    yellow: Color(0xFFDF8E1D),
    peach: Color(0xFFFE640B),
    red: Color(0xFFD20F39),
    mauve: Color(0xFF8839EF),
    teal: Color(0xFF179299),
    pink: Color(0xFFEA76CB),
  );

  /// 全部内置方案，按显示顺序
  static const all = [mocha, macchiato, frappe, latte];

  /// 按 id 取，找不到回退 Mocha
  static AppPalette byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => mocha);
}
