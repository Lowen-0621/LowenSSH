import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/i18n.dart';
import '../core/settings_store.dart';

/// 通用设置 Notifier —— 语言等偏好，落盘持久化。
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => loadSettings();

  /// 切换语言（落盘 + 刷新，全应用即时重建）
  void setLang(AppLang lang) {
    final next = state.copyWith(lang: lang);
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
