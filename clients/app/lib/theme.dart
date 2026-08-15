import 'package:flutter/material.dart';
import 'core/palette.dart';

/// 运行时配色 —— 字段由当前激活的 AppPalette 填充，支持主题切换。
///
/// 注意：字段是 `static Color`（非 const），所以调用点 **不能** 写
/// `const TextStyle(color: AppColors.text)`。默认值取珍珠白，保证
/// 首帧（applyPalette 调用前）也有正确颜色。
class AppColors {
  static Color base = Palettes.pearl.base;
  static Color mantle = Palettes.pearl.mantle;
  static Color crust = Palettes.pearl.crust;
  static Color surface0 = Palettes.pearl.surface0;
  static Color surface1 = Palettes.pearl.surface1;
  static Color surface2 = Palettes.pearl.surface2;
  static Color text = Palettes.pearl.text;
  static Color subtext = Palettes.pearl.subtext;
  static Color overlay = Palettes.pearl.overlay;
  static Color blue = Palettes.pearl.blue;
  static Color lavender = Palettes.pearl.lavender;
  static Color sapphire = Palettes.pearl.sapphire;
  static Color green = Palettes.pearl.green;
  static Color yellow = Palettes.pearl.yellow;
  static Color peach = Palettes.pearl.peach;
  static Color red = Palettes.pearl.red;
  static Color mauve = Palettes.pearl.mauve;
  static Color teal = Palettes.pearl.teal;
  static Color pink = Palettes.pearl.pink;
}

/// 当前激活的配色（默认珍珠白）
AppPalette _current = Palettes.pearl;
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

/// 全应用统一动效节奏。
///
/// 桌面工具的动画只用于交代层级变化：悬停足够快，内容切换克制，
/// 页面与弹层不使用弹跳、位移过大的效果。
abstract final class AppMotion {
  static const hover = Duration(milliseconds: 100);
  static const hoverExit = Duration(milliseconds: 80);
  static const quick = Duration(milliseconds: 140);
  static const switcher = Duration(milliseconds: 180);
  static const panel = Duration(milliseconds: 240);
  static const page = Duration(milliseconds: 260);

  static const Curve standard = Cubic(.16, 1, .3, 1);
}

abstract final class AppRadius {
  static const compact = 8.0;
  static const small = 10.0;
  static const medium = 14.0;
  static const large = 18.0;
  static const pill = 999.0;
}

/// 统一的轻量阴影。使用当前主题文字色，暗色主题下也不会发灰。
abstract final class AppShadows {
  static Color get _color => currentPalette.brightness == Brightness.dark
      ? Colors.black
      : AppColors.text;

  static List<BoxShadow> soft({double opacity = .055}) => [
    BoxShadow(
      color: _color.withValues(alpha: opacity),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> floating({double opacity = .075}) => [
    BoxShadow(
      color: _color.withValues(alpha: opacity),
      blurRadius: 30,
      offset: const Offset(0, 12),
    ),
  ];
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: _current.brightness, useMaterial3: true);
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.small),
  );
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
    splashFactory: NoSplash.splashFactory,
    hoverColor: AppColors.surface0.withValues(alpha: .72),
    highlightColor: Colors.transparent,
    focusColor: AppColors.surface0.withValues(alpha: .72),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.mantle,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
        side: BorderSide(color: AppColors.surface0.withValues(alpha: .9)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.mantle,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: BorderSide(color: AppColors.surface0.withValues(alpha: .9)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.text.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(AppRadius.compact),
      ),
      textStyle: TextStyle(color: AppColors.base, fontSize: 12),
      waitDuration: const Duration(milliseconds: 450),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        animationDuration: AppMotion.hover,
        shape: WidgetStatePropertyAll(buttonShape),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? AppColors.surface0.withValues(alpha: .78)
              : Colors.transparent,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        animationDuration: AppMotion.hover,
        shape: WidgetStatePropertyAll(buttonShape),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? AppColors.surface0.withValues(alpha: .68)
              : Colors.transparent,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        animationDuration: AppMotion.hover,
        shape: WidgetStatePropertyAll(buttonShape),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? Colors.white.withValues(alpha: .08)
              : Colors.transparent,
        ),
      ),
    ),
  );
}
