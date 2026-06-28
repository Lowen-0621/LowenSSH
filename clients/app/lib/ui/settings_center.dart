import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/i18n.dart';
import '../core/config.dart';
import '../core/palette.dart';
import '../core/lock_store.dart';
import '../core/settings_store.dart';
import '../state/config_provider.dart';
import '../state/settings_provider.dart';

/// 应用版本号（与 pubspec version 对齐，手工维护）
const String kAppVersion = '1.0.0';

/// 设置中心 —— 左栏索引 + 右栏内容的大窗口（仿 Termius）。
/// 各页：AI 模型 / 通用 / 终端 / 终端主题 / 快捷键（后三者后续批次填充）。
Future<void> showSettingsCenter(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.base,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.surface0),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 620),
        child: const _SettingsCenter(),
      ),
    ),
  );
}

// 导航项标识
enum _Nav { aiModel, common, terminal, theme, security, shortcuts }

class _SettingsCenter extends ConsumerStatefulWidget {
  const _SettingsCenter();

  @override
  ConsumerState<_SettingsCenter> createState() => _SettingsCenterState();
}

class _SettingsCenterState extends ConsumerState<_SettingsCenter> {
  _Nav _active = _Nav.aiModel;

  @override
  Widget build(BuildContext context) {
    final l = ref.watch(l10nProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左栏导航
        SizedBox(width: 220, child: _navBar(l)),
        VerticalDivider(width: 1, color: AppColors.surface0),
        // 右栏内容
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部标题条
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: AppColors.surface0)),
                ),
                child: Row(
                  children: [
                    Text(l.t('settings.title'),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text)),
                    const Spacer(),
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close,
                          size: 18, color: AppColors.subtext),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: switch (_active) {
                    _Nav.aiModel => const _AiModelPage(),
                    _Nav.common => const _CommonPage(),
                    _Nav.terminal => const _TerminalPage(),
                    _Nav.theme => const _ThemePage(),
                    _Nav.security => const _SecurityPage(),
                    _ => _placeholder(l),
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 左侧导航栏
  Widget _navBar(L10n l) {
    Widget item(_Nav nav, IconData icon, String label) {
      final active = _active == nav;
      return InkWell(
        onTap: () => setState(() => _active = nav),
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.surface0 : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? AppColors.text : AppColors.subtext),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: active ? AppColors.text : AppColors.subtext)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: AppColors.mantle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          item(_Nav.aiModel, Icons.smart_toy_outlined,
              l.t('settings.nav.aiModel')),
          item(_Nav.common, Icons.tune, l.t('settings.nav.common')),
          item(_Nav.terminal, Icons.terminal_outlined,
              l.t('settings.nav.terminal')),
          item(_Nav.theme, Icons.palette_outlined,
              l.t('settings.nav.theme')),
          item(_Nav.security, Icons.lock_outline,
              l.t('settings.nav.security')),
          item(_Nav.shortcuts, Icons.keyboard_outlined,
              l.t('settings.nav.shortcuts')),
          const Spacer(),
          // 版本号
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.t('common.version'),
                    style: TextStyle(
                        fontSize: 11, color: AppColors.overlay)),
                Text(kAppVersion,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.overlay)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(L10n l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(l.t('settings.comingSoon'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.overlay)),
      );
}

// ============ AI 模型页 ============

class _AiModelPage extends ConsumerStatefulWidget {
  const _AiModelPage();

  @override
  ConsumerState<_AiModelPage> createState() => _AiModelPageState();
}

class _AiModelPageState extends ConsumerState<_AiModelPage> {
  // 当前编辑中的供应商 id（默认选激活的）
  String? _editingId;

  @override
  Widget build(BuildContext context) {
    final l = ref.watch(l10nProvider);
    final cfg = ref.watch(configProvider);
    final editingId = _editingId ?? cfg.activeProviderId;
    final editing =
        cfg.providers.firstWhere((p) => p.id == editingId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.t('settings.ai.title'),
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text)),
        const SizedBox(height: 4),
        Text(l.t('settings.ai.hint'),
            style: TextStyle(fontSize: 11.5, color: AppColors.overlay)),
        const SizedBox(height: 16),
        // 供应商选择行（横向卡片）
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in cfg.providers)
              _providerChip(p, p.id == editingId,
                  p.id == cfg.activeProviderId, () {
                setState(() => _editingId = p.id);
              }),
          ],
        ),
        const SizedBox(height: 20),
        // 编辑区
        _editor(l, editing, cfg.activeProviderId == editing.id),
      ],
    );
  }

  // 供应商卡片：名称 + 配置状态 + 激活标记
  Widget _providerChip(
      LlmProvider p, bool editing, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: editing ? AppColors.surface0 : AppColors.mantle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: editing ? AppColors.blue : AppColors.surface0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text)),
                ),
                if (active)
                  Icon(Icons.check_circle,
                      size: 14, color: AppColors.green),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: p.configured ? AppColors.green : AppColors.overlay,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(p.model,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10, color: AppColors.overlay)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 配置编辑表单
  Widget _editor(L10n l, LlmProvider p, bool isActive) {
    // 用 key 让切换供应商时重建表单（刷新 controller 初值）
    return _ProviderForm(
      key: ValueKey(p.id),
      provider: p,
      isActive: isActive,
      l: l,
    );
  }
}

// 供应商编辑表单（独立 StatefulWidget，持有 controller）
class _ProviderForm extends ConsumerStatefulWidget {
  final LlmProvider provider;
  final bool isActive;
  final L10n l;
  const _ProviderForm(
      {super.key,
      required this.provider,
      required this.isActive,
      required this.l});

  @override
  ConsumerState<_ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends ConsumerState<_ProviderForm> {
  late final TextEditingController _apiKey =
      TextEditingController(text: widget.provider.apiKey);
  late final TextEditingController _model =
      TextEditingController(text: widget.provider.model);
  late final TextEditingController _baseURL =
      TextEditingController(text: widget.provider.baseURL);

  @override
  void dispose() {
    _apiKey.dispose();
    _model.dispose();
    _baseURL.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(configProvider.notifier).updateProvider(
          widget.provider.id,
          apiKey: _apiKey.text.trim(),
          model: _model.text.trim(),
          baseURL: _baseURL.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.mantle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.surface0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(widget.provider.name,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
              const SizedBox(width: 8),
              if (widget.isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(l.t('settings.ai.active'),
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.green)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _label(l.t('settings.ai.apiKey')),
          _input(_apiKey, obscure: true, onChanged: (_) => _save()),
          const SizedBox(height: 12),
          _label(l.t('settings.ai.model')),
          _input(_model, onChanged: (_) => _save()),
          const SizedBox(height: 12),
          _label(l.t('settings.ai.baseUrl')),
          _input(_baseURL, onChanged: (_) => _save()),
          const SizedBox(height: 16),
          // 设为当前 / 已是当前
          Align(
            alignment: Alignment.centerLeft,
            child: widget.isActive
                ? Text(l.t('settings.ai.active'),
                    style: TextStyle(
                        fontSize: 12, color: AppColors.green))
                : FilledButton(
                    onPressed: widget.provider.configured
                        ? () => ref
                            .read(configProvider.notifier)
                            .setActiveProvider(widget.provider.id)
                        : null,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: AppColors.crust,
                        disabledBackgroundColor: AppColors.surface0),
                    child: Text(l.t('settings.ai.setActive')),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============ 通用页 ============

class _CommonPage extends ConsumerWidget {
  const _CommonPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(l10nProvider);
    final lang = ref.watch(settingsProvider).lang;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.t('settings.common.title'),
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.mantle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.surface0),
          ),
          child: Row(
            children: [
              Text(l.t('settings.common.language'),
                  style: TextStyle(fontSize: 13, color: AppColors.text)),
              const Spacer(),
              // 语言切换
              _langTab(l.t('settings.common.langZh'), lang == AppLang.zh,
                  () => ref.read(settingsProvider.notifier).setLang(AppLang.zh)),
              const SizedBox(width: 8),
              _langTab(l.t('settings.common.langEn'), lang == AppLang.en,
                  () => ref.read(settingsProvider.notifier).setLang(AppLang.en)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _langTab(String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppColors.surface1 : AppColors.base,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: active ? AppColors.blue : AppColors.surface0),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  color: active ? AppColors.text : AppColors.subtext)),
        ),
      );
}

// ============ 终端设置页 ============

class _TerminalPage extends ConsumerWidget {
  const _TerminalPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(l10nProvider);
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.t('settings.term.title'),
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.mantle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.surface0),
          ),
          child: Column(
            children: [
              // 选中即复制 / 右键粘贴
              _switchRow(l.t('settings.term.selectToCopy'), s.selectToCopy,
                  (v) {
                notifier.updateTerminal(selectToCopy: v, rightClickPaste: v);
              }),
              Divider(height: 1, color: AppColors.surface0),
              // 光标闪烁
              _switchRow(l.t('settings.term.cursorBlink'), s.cursorBlink,
                  (v) => notifier.updateTerminal(cursorBlink: v)),
              Divider(height: 1, color: AppColors.surface0),
              // 光标样式（三选）
              _rowWrap(
                l.t('settings.term.cursorStyle'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _seg(l.t('settings.term.cursorBlock'),
                        s.cursorStyle == CursorStyle.block,
                        () => notifier.updateTerminal(
                            cursorStyle: CursorStyle.block)),
                    const SizedBox(width: 6),
                    _seg(l.t('settings.term.cursorUnderline'),
                        s.cursorStyle == CursorStyle.underline,
                        () => notifier.updateTerminal(
                            cursorStyle: CursorStyle.underline)),
                    const SizedBox(width: 6),
                    _seg(l.t('settings.term.cursorBar'),
                        s.cursorStyle == CursorStyle.bar,
                        () => notifier.updateTerminal(
                            cursorStyle: CursorStyle.bar)),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.surface0),
              // 字号（± 步进）
              _rowWrap(
                l.t('settings.term.fontSize'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _stepBtn(Icons.remove, () {
                      final n = (s.termFontSize - 1).clamp(8.0, 28.0);
                      notifier.updateTerminal(termFontSize: n);
                    }),
                    Container(
                      width: 44,
                      alignment: Alignment.center,
                      child: Text(s.termFontSize.toStringAsFixed(0),
                          style: TextStyle(
                              fontSize: 13, color: AppColors.text)),
                    ),
                    _stepBtn(Icons.add, () {
                      final n = (s.termFontSize + 1).clamp(8.0, 28.0);
                      notifier.updateTerminal(termFontSize: n);
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 开关行
  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: AppColors.text)),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.crust,
              activeTrackColor: AppColors.blue,
            ),
          ],
        ),
      );

  // 标签 + 右侧自定义控件行
  Widget _rowWrap(String label, Widget trailing) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: AppColors.text)),
            ),
            trailing,
          ],
        ),
      );

  // 分段选择按钮
  Widget _seg(String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.surface1 : AppColors.base,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: active ? AppColors.blue : AppColors.surface0),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: active ? AppColors.text : AppColors.subtext)),
        ),
      );

  // 步进按钮
  Widget _stepBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.surface0,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: AppColors.text),
        ),
      );
}

// ============ 共用小部件 ============

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: AppColors.subtext)),
    );

Widget _input(TextEditingController c,
        {bool obscure = false, ValueChanged<String>? onChanged}) =>
    TextField(
      controller: c,
      obscureText: obscure,
      onChanged: onChanged,
      style: TextStyle(fontSize: 13, color: AppColors.text),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.base,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppColors.surface0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: AppColors.blue),
        ),
      ),
    );

// ============ 外观（配色）页 ============

class _ThemePage extends ConsumerWidget {
  const _ThemePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(l10nProvider);
    final currentId = ref.watch(settingsProvider).themeId;
    final zh = ref.watch(settingsProvider).lang == AppLang.zh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(l.t('settings.theme.scheme')),
        const SizedBox(height: 4),
        Text(l.t('settings.theme.hint'),
            style: TextStyle(fontSize: 11, color: AppColors.overlay)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final p in Palettes.all)
              _paletteCard(
                p,
                zh: zh,
                selected: p.id == currentId,
                onTap: () => ref.read(settingsProvider.notifier).setTheme(p.id),
              ),
          ],
        ),
      ],
    );
  }

  // 单张配色预览卡：迷你界面预览 + 名称 + 选中标记
  Widget _paletteCard(AppPalette p,
      {required bool zh, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.surface0,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 迷你界面预览：用该方案自身的颜色渲染
            _miniPreview(p),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(zh ? p.nameZh : p.nameEn,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text)),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 16, color: AppColors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 用配色自身颜色画一个三栏迷你界面缩略图
  Widget _miniPreview(AppPalette p) {
    return Container(
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.base,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.surface0),
      ),
      child: Row(
        children: [
          // 侧栏
          Container(width: 30, color: p.mantle, child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dot(p.blue),
              const SizedBox(height: 4),
              _dot(p.subtext),
              const SizedBox(height: 4),
              _dot(p.subtext),
            ],
          )),
          // 主区：几条彩色文字行
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _bar(p.green, 0.7),
                  const SizedBox(height: 4),
                  _bar(p.yellow, 0.5),
                  const SizedBox(height: 4),
                  _bar(p.text, 0.85),
                  const SizedBox(height: 4),
                  _bar(p.mauve, 0.4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) =>
      Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _bar(Color c, double widthFactor) => FractionallySizedBox(
        widthFactor: widthFactor,
        alignment: Alignment.centerLeft,
        child: Container(
            height: 5,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(3))),
      );
}

// ============ 安全（主密码）页 ============

class _SecurityPage extends ConsumerStatefulWidget {
  const _SecurityPage();

  @override
  ConsumerState<_SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends ConsumerState<_SecurityPage> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _msg;
  bool _isError = false;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _setMsg(String m, {bool error = false}) =>
      setState(() {
        _msg = m;
        _isError = error;
      });

  bool get _zh => ref.read(settingsProvider).lang == AppLang.zh;

  // 设置或修改主密码
  void _save() {
    final hasOld = hasMasterPassword();
    // 已设密码：先验旧
    if (hasOld && !verifyMasterPassword(_oldCtrl.text)) {
      _setMsg(_zh ? '当前密码错误' : 'Current password is wrong', error: true);
      return;
    }
    final np = _newCtrl.text;
    if (np.isEmpty) {
      _setMsg(_zh ? '新密码不能为空' : 'New password cannot be empty', error: true);
      return;
    }
    if (np != _confirmCtrl.text) {
      _setMsg(_zh ? '两次输入不一致' : 'Passwords do not match', error: true);
      return;
    }
    setMasterPassword(np);
    _oldCtrl.clear();
    _newCtrl.clear();
    _confirmCtrl.clear();
    _setMsg(_zh ? '已保存，下次启动生效' : 'Saved. Takes effect next launch');
  }

  // 取消主密码
  void _clear() {
    if (!verifyMasterPassword(_oldCtrl.text)) {
      _setMsg(_zh ? '当前密码错误' : 'Current password is wrong', error: true);
      return;
    }
    clearMasterPassword();
    _oldCtrl.clear();
    _newCtrl.clear();
    _confirmCtrl.clear();
    setState(() {});
    _setMsg(_zh ? '已取消主密码' : 'Master password removed');
  }

  @override
  Widget build(BuildContext context) {
    final zh = _zh;
    final hasPwd = hasMasterPassword();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(zh ? '主密码' : 'Master Password'),
        const SizedBox(height: 4),
        Text(
            hasPwd
                ? (zh ? '已启用。启动应用时需输入主密码解锁。' : 'Enabled. Required to unlock on launch.')
                : (zh ? '未设置。设置后启动需解锁，保护本地主机簿与密钥。' : 'Not set. Protects local hosts & keys.'),
            style: TextStyle(fontSize: 11, color: AppColors.overlay)),
        const SizedBox(height: 16),
        if (hasPwd) ...[
          _label(zh ? '当前密码' : 'Current Password'),
          _input(_oldCtrl, obscure: true),
          const SizedBox(height: 12),
        ],
        _label(zh ? '新密码' : 'New Password'),
        _input(_newCtrl, obscure: true),
        const SizedBox(height: 12),
        _label(zh ? '确认新密码' : 'Confirm New Password'),
        _input(_confirmCtrl, obscure: true),
        if (_msg != null) ...[
          const SizedBox(height: 10),
          Text(_msg!,
              style: TextStyle(
                  fontSize: 12,
                  color: _isError ? AppColors.red : AppColors.green)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
              child: Text(hasPwd ? (zh ? '修改' : 'Change') : (zh ? '设置' : 'Set'),
                  style: TextStyle(color: AppColors.crust)),
            ),
            if (hasPwd) ...[
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _clear,
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.red)),
                child: Text(zh ? '取消主密码' : 'Remove',
                    style: TextStyle(color: AppColors.red)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
