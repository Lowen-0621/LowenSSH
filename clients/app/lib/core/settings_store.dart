/// 通用设置持久化 —— 语言等应用级偏好，存 $HOME/.lowenssh/settings.json。
/// 与 config.json/snippets.json 同目录。独立文件，避免污染主配置。
/// 后续批次（Terminal 设置/主题/快捷键）的偏好也并到这里。
library;

import 'dart:convert';
import 'dart:io';
import 'i18n.dart';

/// 终端光标样式
enum CursorStyle { block, underline, bar }

/// 应用级通用设置
class AppSettings {
  final AppLang lang;

  // 外观
  final String themeId; //        配色方案 id（见 palette.dart）

  // 终端设置（xterm 真实支持项）
  final double termFontSize; //   字号
  final bool selectToCopy; //     选中即复制
  final bool rightClickPaste; //  右键粘贴
  final CursorStyle cursorStyle; //光标样式
  final bool cursorBlink; //       光标闪烁

  const AppSettings({
    this.lang = AppLang.zh,
    this.themeId = 'mocha',
    this.termFontSize = 12.5,
    this.selectToCopy = true,
    this.rightClickPaste = true,
    this.cursorStyle = CursorStyle.block,
    this.cursorBlink = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        lang: (j['lang'] as String?) == 'en' ? AppLang.en : AppLang.zh,
        themeId: j['themeId'] as String? ?? 'mocha',
        termFontSize: (j['termFontSize'] as num?)?.toDouble() ?? 12.5,
        selectToCopy: j['selectToCopy'] as bool? ?? true,
        rightClickPaste: j['rightClickPaste'] as bool? ?? true,
        cursorStyle: switch (j['cursorStyle'] as String?) {
          'underline' => CursorStyle.underline,
          'bar' => CursorStyle.bar,
          _ => CursorStyle.block,
        },
        cursorBlink: j['cursorBlink'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'lang': lang == AppLang.en ? 'en' : 'zh',
        'themeId': themeId,
        'termFontSize': termFontSize,
        'selectToCopy': selectToCopy,
        'rightClickPaste': rightClickPaste,
        'cursorStyle': cursorStyle.name,
        'cursorBlink': cursorBlink,
      };

  AppSettings copyWith({
    AppLang? lang,
    String? themeId,
    double? termFontSize,
    bool? selectToCopy,
    bool? rightClickPaste,
    CursorStyle? cursorStyle,
    bool? cursorBlink,
  }) =>
      AppSettings(
        lang: lang ?? this.lang,
        themeId: themeId ?? this.themeId,
        termFontSize: termFontSize ?? this.termFontSize,
        selectToCopy: selectToCopy ?? this.selectToCopy,
        rightClickPaste: rightClickPaste ?? this.rightClickPaste,
        cursorStyle: cursorStyle ?? this.cursorStyle,
        cursorBlink: cursorBlink ?? this.cursorBlink,
      );
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
