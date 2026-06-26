/// 轻量国际化 —— 不引第三方包，一个 key→译文 Map 搞定中/英切换。
/// 设计：L10n 持有当前语言；t(key) 取译文，缺失回退中文、再回退 key 本身。
/// 全应用文案逐步迁移到这里（分批），新代码一律用 context 无关的 L10n.of(ref)。
library;

/// 支持的语言
enum AppLang { zh, en }

/// 文案字典。外层 key 是文案标识，内层按语言取值。
/// 约定：key 用点分命名空间（settings.title / common.save）。
const Map<String, Map<AppLang, String>> _dict = {
  // 通用动作
  'common.save': {AppLang.zh: '保存', AppLang.en: 'Save'},
  'common.cancel': {AppLang.zh: '取消', AppLang.en: 'Cancel'},
  'common.delete': {AppLang.zh: '删除', AppLang.en: 'Delete'},
  'common.add': {AppLang.zh: '添加', AppLang.en: 'Add'},
  'common.close': {AppLang.zh: '关闭', AppLang.en: 'Close'},
  'common.version': {AppLang.zh: '版本', AppLang.en: 'Version'},

  // 设置中心 - 导航
  'settings.title': {AppLang.zh: '设置', AppLang.en: 'Settings'},
  'settings.nav.aiModel': {AppLang.zh: 'AI 模型', AppLang.en: 'AI Model'},
  'settings.nav.common': {AppLang.zh: '通用', AppLang.en: 'Common'},
  'settings.nav.terminal': {AppLang.zh: '终端', AppLang.en: 'Terminal'},
  'settings.nav.theme': {AppLang.zh: '终端主题', AppLang.en: 'Terminal Theme'},
  'settings.nav.shortcuts': {AppLang.zh: '快捷键', AppLang.en: 'Shortcuts'},

  // 通用页
  'settings.common.title': {AppLang.zh: '通用设置', AppLang.en: 'Common Settings'},
  'settings.common.language': {AppLang.zh: '语言', AppLang.en: 'Language'},
  'settings.common.langZh': {AppLang.zh: '简体中文', AppLang.en: 'Simplified Chinese'},
  'settings.common.langEn': {AppLang.zh: '英文', AppLang.en: 'English'},

  // AI 模型页
  'settings.ai.title': {AppLang.zh: 'AI 模型设置', AppLang.en: 'AI Model Settings'},
  'settings.ai.provider': {AppLang.zh: '供应商', AppLang.en: 'Provider'},
  'settings.ai.apiKey': {AppLang.zh: 'API Key', AppLang.en: 'API Key'},
  'settings.ai.baseUrl': {AppLang.zh: 'Base URL', AppLang.en: 'Base URL'},
  'settings.ai.model': {AppLang.zh: '模型', AppLang.en: 'Model'},
  'settings.ai.active': {AppLang.zh: '当前使用', AppLang.en: 'Active'},
  'settings.ai.setActive': {AppLang.zh: '设为当前', AppLang.en: 'Set as active'},
  'settings.ai.configured': {AppLang.zh: '已配置', AppLang.en: 'Configured'},
  'settings.ai.notConfigured': {AppLang.zh: '未配置 Key', AppLang.en: 'No API Key'},
  'settings.ai.hint': {
    AppLang.zh: '填入对应供应商的 API Key 即可启用。均走 OpenAI 兼容协议。',
    AppLang.en: 'Enter the API Key to enable. All use the OpenAI-compatible protocol.'
  },

  // 终端设置页
  'settings.term.title': {AppLang.zh: '终端设置', AppLang.en: 'Terminal Settings'},
  'settings.term.fontSize': {AppLang.zh: '字号', AppLang.en: 'Font Size'},
  'settings.term.selectToCopy': {
    AppLang.zh: '选中即复制 / 右键粘贴',
    AppLang.en: 'Select to copy & Right click to paste'
  },
  'settings.term.rightClickPaste': {
    AppLang.zh: '右键粘贴',
    AppLang.en: 'Right click to paste'
  },
  'settings.term.cursorStyle': {AppLang.zh: '光标样式', AppLang.en: 'Cursor Style'},
  'settings.term.cursorBlink': {AppLang.zh: '光标闪烁', AppLang.en: 'Cursor Blink'},
  'settings.term.cursorBlock': {AppLang.zh: '方块', AppLang.en: 'Block'},
  'settings.term.cursorUnderline': {AppLang.zh: '下划线', AppLang.en: 'Underline'},
  'settings.term.cursorBar': {AppLang.zh: '竖线', AppLang.en: 'Bar'},
};

/// 当前语言下取文案
class L10n {
  final AppLang lang;
  const L10n(this.lang);

  String t(String key) {
    final entry = _dict[key];
    if (entry == null) return key; // 没收录就显示 key，便于发现遗漏
    return entry[lang] ?? entry[AppLang.zh] ?? key;
  }
}
