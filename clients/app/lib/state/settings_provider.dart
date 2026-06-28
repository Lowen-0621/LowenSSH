import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/i18n.dart';
import '../core/settings_store.dart';
import '../core/palette.dart';
import '../theme.dart';

/// 通用设置 Notifier —— 语言等偏好，落盘持久化。
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final s = loadSettings();
    // 启动即把持久化的配色应用到 AppColors（首帧之前）
    applyPalette(Palettes.byId(s.themeId));
    return s;
  }

  /// 切换语言（落盘 + 刷新，全应用即时重建）
  void setLang(AppLang lang) {
    final next = state.copyWith(lang: lang);
    saveSettings(next);
    state = next;
  }

  /// 切换配色方案（应用到 AppColors + 落盘 + 刷新，main 监听后重建 MaterialApp）
  void setTheme(String themeId) {
    applyPalette(Palettes.byId(themeId));
    final next = state.copyWith(themeId: themeId);
    saveSettings(next);
    state = next;
  }

  /// 更新终端设置（任一字段，落盘 + 刷新）
  void updateTerminal({
    double? termFontSize,
    bool? selectToCopy,
    bool? rightClickPaste,
    CursorStyle? cursorStyle,
    bool? cursorBlink,
  }) {
    final next = state.copyWith(
      termFontSize: termFontSize,
      selectToCopy: selectToCopy,
      rightClickPaste: rightClickPaste,
      cursorStyle: cursorStyle,
      cursorBlink: cursorBlink,
    );
    saveSettings(next);
    state = next;
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// 当前语言下的 L10n（派生）。UI 用 ref.watch(l10nProvider).t('key')。
final l10nProvider = Provider<L10n>((ref) {
  final lang = ref.watch(settingsProvider).lang;
  return L10n(lang);
});
