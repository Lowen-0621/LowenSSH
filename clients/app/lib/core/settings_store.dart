/// 通用设置持久化 —— 语言等应用级偏好，存 $HOME/.lowenssh/settings.json。
/// 与 config.json/snippets.json 同目录。独立文件，避免污染主配置。
/// 后续批次（Terminal 设置/主题/快捷键）的偏好也并到这里。
library;

import 'dart:convert';
import 'dart:io';
import 'i18n.dart';

/// 应用级通用设置
class AppSettings {
  final AppLang lang;

  const AppSettings({this.lang = AppLang.zh});

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        lang: (j['lang'] as String?) == 'en' ? AppLang.en : AppLang.zh,
      );

  Map<String, dynamic> toJson() => {
        'lang': lang == AppLang.en ? 'en' : 'zh',
      };

  AppSettings copyWith({AppLang? lang}) =>
      AppSettings(lang: lang ?? this.lang);
}

String get _settingsFile =>
    '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.lowenssh/settings.json';

/// 读设置；不存在或损坏返回默认（中文）
AppSettings loadSettings() {
  final file = File(_settingsFile);
  if (!file.existsSync()) return const AppSettings();
  try {
    final parsed = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return AppSettings.fromJson(parsed);
  } catch (_) {
    return const AppSettings();
  }
}

/// 写设置
void saveSettings(AppSettings s) {
  final dir = Directory(
      '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.lowenssh');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File(_settingsFile)
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(s.toJson()));
}
