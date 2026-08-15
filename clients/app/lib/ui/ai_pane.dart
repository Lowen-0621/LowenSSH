import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../theme.dart';
import '../state/agent_provider.dart';
import '../state/snippet_provider.dart';
import '../state/config_provider.dart';
import '../state/settings_provider.dart';
import '../core/i18n.dart';
import 'app_hover_surface.dart';

/// AI 对话面板 —— 对话流 + 工具卡片 + 门禁卡片 + 输入框
/// 对应设计稿 .pane.ai。三种卡片(tool/ask/blocked)是门禁可视化核心。
/// 数据来自 agentProvider，输入框发送任务，ASK 卡片桥接确认。
class AiPane extends ConsumerStatefulWidget {
  const AiPane({super.key});

  @override
  ConsumerState<AiPane> createState() => _AiPaneState();
}

class _AiPaneState extends ConsumerState<AiPane> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(agentProvider.notifier).send(text);
    _scrollToBottom();
  }

  void _fillPrompt(String prompt) {
    _controller.text = prompt;
    _controller.selection = TextSelection.collapsed(offset: prompt.length);
    _focusNode.requestFocus();
  }

  void _newConversation() {
    ref.read(agentProvider.notifier).newConversation();
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: AppMotion.switcher,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(agentProvider);
    final l = ref.watch(l10nProvider);
    // 新消息进来自动滚到底
    ref.listen(agentProvider, (prev, next) => _scrollToBottom());
    // 命令片段等外部请求：把文本填进输入框并聚焦末尾
    ref.listen(composerProvider, (prev, next) {
      if (next == null) return;
      _controller.text = next.text;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _focusNode.requestFocus();
      ref.read(composerProvider.notifier).clear();
    });

    final children = <Widget>[];
    for (var i = 0; i < st.items.length; i++) {
      final item = st.items[i];
      // reasoning 是否「真正在思考」：运行中 + 是最后一项（否则是已结束/历史块）
      final live = st.running && i == st.items.length - 1;
      children.add(_renderItem(item, live: live));
      children.add(const SizedBox(height: 12));
    }
    // 末尾插入待确认卡片（ASK 态）
    if (st.pendingAsk != null) {
      children.add(
        _askCard(
          cmd: st.pendingAsk!.command,
          why: l.t('ai.gateVerdict', {'reason': st.pendingAsk!.reason}),
        ),
      );
      children.add(const SizedBox(height: 12));
    }

    return Container(
      color: AppColors.mantle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部模型切换条
          _modelBar(),
          _AgentStageRail(state: st),
          // 对话流
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.switcher,
              switchInCurve: AppMotion.standard,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: st.items.isEmpty && st.pendingAsk == null
                  ? _AgentEmptyState(
                      key: const ValueKey('agent-empty'),
                      label: l.t('ai.empty'),
                      onPrompt: _fillPrompt,
                    )
                  : SingleChildScrollView(
                      key: const ValueKey('agent-conversation'),
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ),
            ),
          ),
          AnimatedSwitcher(
            duration: AppMotion.quick,
            child: st.error == null
                ? const SizedBox.shrink(key: ValueKey('agent-no-error'))
                : Container(
                    key: const ValueKey('agent-error'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    color: AppColors.red.withValues(alpha: .07),
                    child: Text(
                      l.t('ai.error', {'err': '${st.error}'}),
                      style: TextStyle(fontSize: 11, color: AppColors.red),
                    ),
                  ),
          ),
          _inputBox(st.running, l),
        ],
      ),
    );
  }

  // 按 ChatItem 类型分发渲染
  Widget _renderItem(ChatItem it, {bool live = false}) {
    switch (it.kind) {
      case ChatItemKind.user:
        return _userBubble(it.text);
      case ChatItemKind.reasoning:
        return _ReasoningTile(
          text: it.text,
          seconds: it.reasoningSec ?? 0,
          live: live,
          l: ref.read(l10nProvider),
        );
      case ChatItemKind.assistant:
        return _assistantMsg(text: it.text);
      case ChatItemKind.tool:
        return _ToolTile(
          name: it.toolName ?? '',
          running: it.toolResult == null,
          executed: it.toolExecuted,
          cmd: it.toolArgs ?? '',
          result: it.toolResult ?? '',
        );
      case ChatItemKind.blocked:
        return _blockedCard(cmd: it.command ?? '', why: it.reason ?? '');
      case ChatItemKind.ask:
        return _askCard(cmd: it.command ?? '', why: it.reason ?? '');
    }
  }

  // 用户气泡（右对齐，圆角缺右下）
  Widget _userBubble(String text) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface0,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: SelectableText(
        text,
        style: TextStyle(fontSize: 13, color: AppColors.text),
      ),
    ),
  );

  // 顶部模型切换条：显示当前模型，下拉切换已配置 key 的供应商
  Widget _modelBar() {
    final cfg = ref.watch(configProvider);
    final l = ref.watch(l10nProvider);
    final active = cfg.activeProvider;
    // 只列已配置 key 的供应商；当前激活的即使没 key 也显示
    final selectable = cfg.providers
        .where((p) => p.configured || p.id == active.id)
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.mantle,
        border: Border(bottom: BorderSide(color: AppColors.surface0)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 14, color: AppColors.subtext),
          const SizedBox(width: 7),
          Text(
            l.t('ai.agent'),
            style: TextStyle(fontSize: 12, color: AppColors.subtext),
          ),
          const SizedBox(width: 8),
          // 模型下拉
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                initialValue: active.id,
                tooltip: l.t('ai.switchModel'),
                color: AppColors.mantle,
                onSelected: (id) =>
                    ref.read(configProvider.notifier).setActiveProvider(id),
                itemBuilder: (_) => [
                  for (final p in selectable)
                    PopupMenuItem(
                      value: p.id,
                      height: 38,
                      child: Row(
                        children: [
                          Icon(
                            p.id == active.id
                                ? Icons.check
                                : Icons.circle_outlined,
                            size: 13,
                            color: p.id == active.id
                                ? AppColors.green
                                : AppColors.overlay,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${p.name} · ${p.model}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface0,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        active.model,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.expand_more,
                        size: 14,
                        color: AppColors.subtext,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 历史会话：点击弹出历史列表，可恢复/删除
          _barIcon(
            icon: Icons.history,
            tooltip: l.t('ai.history'),
            onTap: () => _showHistory(context),
          ),
          const SizedBox(width: 6),
          _NewChatButton(
            enabled: !ref.watch(agentProvider).running,
            onTap: _newConversation,
          ),
        ],
      ),
    );
  }

  // 模型条上的小图标按钮
  Widget _barIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: 28,
      height: 28,
      child: AppHoverSurface(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.compact),
        child: Icon(icon, size: 16, color: AppColors.subtext),
      ),
    ),
  );

  // 历史会话面板：列出当前主机的归档会话，点击恢复，垃圾桶删除
  void _showHistory(BuildContext context) {
    final l = ref.read(l10nProvider);
    final entries = ref.read(agentProvider.notifier).historyEntries();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.mantle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  l.t('ai.history'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: Text(
                    l.t('ai.historyEmpty'),
                    style: TextStyle(fontSize: 12, color: AppColors.overlay),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
                      final ds =
                          '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)} ${_pad2(dt.hour)}:${_pad2(dt.minute)}';
                      return InkWell(
                        onTap: () {
                          ref.read(agentProvider.notifier).restoreHistory(e.id);
                          Navigator.of(ctx).pop();
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 9,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.text,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      ds,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: AppColors.overlay,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  ref
                                      .read(agentProvider.notifier)
                                      .deleteHistory(e.id);
                                  Navigator.of(ctx).pop();
                                  _showHistory(context); // 刷新列表
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.delete_outline,
                                    size: 15,
                                    color: AppColors.overlay,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');

  // 智能体消息正文（Markdown 渲染：加粗/列表/表格/代码块）
  Widget _assistantMsg({required String text}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(Icons.smart_toy_outlined, size: 13, color: AppColors.overlay),
          const SizedBox(width: 5),
          Text(
            ref.read(l10nProvider).t('ai.agent'),
            style: TextStyle(fontSize: 10.5, color: AppColors.overlay),
          ),
        ],
      ),
      const SizedBox(height: 4),
      // 可选中复制；Markdown 语法渲染成富文本
      SelectionArea(
        child: GptMarkdown(
          text,
          style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.text),
        ),
      ),
    ],
  );

  // 思考过程块 → 改用 _ReasoningTile（行内可折叠，见文件末尾）

  // 工具调用卡片 → 改用 _ToolTile（默认折叠的紧凑行，见文件末尾）

  // ASK 确认卡片：明确告诉用户 Agent 已暂停，选择后才会继续。
  Widget _askCard({required String cmd, required String why}) => Container(
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
    decoration: BoxDecoration(
      color: AppColors.yellow.withValues(alpha: .08),
      border: Border.all(color: AppColors.yellow.withValues(alpha: .32)),
      borderRadius: BorderRadius.circular(AppRadius.medium),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: AppColors.yellow,
            ),
            const SizedBox(width: 6),
            Text(
              ref.read(settingsProvider).lang == AppLang.zh
                  ? '执行已暂停，等待你的确认'
                  : 'Execution paused for approval',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.yellow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.crust,
            borderRadius: BorderRadius.circular(AppRadius.small),
            border: Border.all(color: AppColors.surface0),
          ),
          child: SelectableText(
            cmd,
            style: TextStyle(
              fontFamily: kMonoFont,
              fontSize: 12,
              color: AppColors.text,
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(why, style: TextStyle(fontSize: 11, color: AppColors.subtext)),
        const SizedBox(height: 13),
        Row(
          children: [
            _cardBtn(
              ref.read(l10nProvider).t('ai.allow'),
              primary: true,
              onTap: () => ref.read(agentProvider.notifier).resolveAsk(true),
            ),
            const SizedBox(width: 8),
            _cardBtn(
              ref.read(l10nProvider).t('ai.deny'),
              ghost: true,
              onTap: () => ref.read(agentProvider.notifier).resolveAsk(false),
            ),
          ],
        ),
      ],
    ),
  );

  // DENY 拦截卡片：红色左边线比整圈红框更快表达“已终止”。
  Widget _blockedCard({required String cmd, required String why}) => Container(
    padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
    decoration: BoxDecoration(
      color: AppColors.red.withValues(alpha: .08),
      border: Border(left: BorderSide(color: AppColors.red, width: 4)),
      borderRadius: BorderRadius.circular(AppRadius.small),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.block, size: 14, color: AppColors.red),
            const SizedBox(width: 6),
            Text(
              ref.read(l10nProvider).t('ai.blockedTitle'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          cmd,
          style: TextStyle(
            fontFamily: kMonoFont,
            fontSize: 11.5,
            color: AppColors.peach,
          ),
        ),
        const SizedBox(height: 5),
        Text(why, style: TextStyle(fontSize: 11, color: AppColors.subtext)),
      ],
    ),
  );

  // 卡片按钮（审批主操作 / 次操作）
  Widget _cardBtn(
    String label, {
    bool primary = false,
    bool ghost = false,
    VoidCallback? onTap,
  }) => AppHoverSurface(
    onTap: onTap,
    color: primary ? AppColors.yellow : Colors.transparent,
    hoverColor: primary
        ? AppColors.text.withValues(alpha: .06)
        : AppColors.text.withValues(alpha: .05),
    border: ghost ? Border.all(color: AppColors.surface1) : null,
    borderRadius: BorderRadius.circular(AppRadius.compact),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: primary ? FontWeight.w600 : FontWeight.normal,
        color: AppColors.text,
      ),
    ),
  );

  // AI 输入框 + 快捷键提示。running 时禁用并显示中断。
  Widget _inputBox(bool running, L10n l) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
    decoration: BoxDecoration(
      color: AppColors.mantle,
      border: Border(top: BorderSide(color: AppColors.surface0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.crust,
            border: Border.all(color: AppColors.surface1),
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: !running,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(fontSize: 13, color: AppColors.text),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: l.t('ai.inputHint'),
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppColors.overlay,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // running 时显示中断，否则显示发送
              running
                  ? InkWell(
                      onTap: () => ref.read(agentProvider.notifier).abort(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.yellow,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l.t('ai.interrupt'),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.yellow,
                            ),
                          ),
                        ],
                      ),
                    )
                  : InkWell(
                      onTap: _send,
                      child: Text(
                        l.t('ai.send'),
                        style: TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 12,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        DefaultTextStyle(
          style: TextStyle(
            fontFamily: kMonoFont,
            fontSize: 10,
            color: AppColors.overlay,
          ),
          child: Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(l.t('ai.sendKey')),
              Text(l.t('ai.newlineKey')),
              Text(l.t('ai.escKey')),
              Text(l.t('ai.cmdK')),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Agent 六阶段状态提示。只根据已有事件映射，不创建新的业务状态。
class _AgentStageRail extends StatelessWidget {
  const _AgentStageRail({required this.state});
  final AgentState state;

  static const _labels = [
    'Plan',
    'Risk Check',
    'Approve',
    'Execute',
    'Verify',
    'Summary',
  ];

  int get _activeIndex {
    if (state.pendingAsk != null) return 2;
    if (state.items.isEmpty) return 0;
    final last = state.items.last;
    if (state.running) {
      if (last.kind == ChatItemKind.tool) return 3;
      if (last.kind == ChatItemKind.reasoning ||
          last.kind == ChatItemKind.blocked) {
        return 1;
      }
      return 0;
    }
    if (last.kind == ChatItemKind.assistant) return 5;
    if (last.kind == ChatItemKind.tool) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 11),
      decoration: BoxDecoration(
        color: AppColors.mantle,
        border: Border(bottom: BorderSide(color: AppColors.surface0)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.switcher,
                  height: 1,
                  color: i <= active
                      ? AppColors.green.withValues(alpha: .52)
                      : AppColors.surface1,
                ),
              ),
            _StagePoint(
              label: _labels[i],
              active: i == active,
              complete: i < active,
            ),
          ],
        ],
      ),
    );
  }
}

class _StagePoint extends StatelessWidget {
  const _StagePoint({
    required this.label,
    required this.active,
    required this.complete,
  });
  final String label;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedContainer(
        duration: AppMotion.switcher,
        width: active ? 9 : 7,
        height: active ? 9 : 7,
        decoration: BoxDecoration(
          color: active
              ? AppColors.text
              : complete
              ? AppColors.green
              : AppColors.surface2,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          color: active ? AppColors.text : AppColors.overlay,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ],
  );
}

class _AgentEmptyState extends StatelessWidget {
  const _AgentEmptyState({
    super.key,
    required this.label,
    required this.onPrompt,
  });
  final String label;
  final ValueChanged<String> onPrompt;

  static const _starters = [
    (
      Icons.monitor_heart_outlined,
      '主机健康检查',
      '检查当前主机的 CPU、内存、磁盘、负载和关键进程，并总结异常。',
    ),
    (Icons.speed_outlined, '定位高负载', '找出当前主机 CPU 和内存占用最高的进程，分析可能原因。'),
    (Icons.description_outlined, '检查错误日志', '检查系统和常见服务最近的错误日志，定位可能的问题并给出建议。'),
  ];

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.text.withValues(alpha: .055),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.route_rounded,
              color: AppColors.subtext,
              size: 25,
            ),
          ),
          const SizedBox(height: 16),
          Text(label, style: TextStyle(fontSize: 13, color: AppColors.subtext)),
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final starter in _starters)
                _StarterButton(
                  icon: starter.$1,
                  label: starter.$2,
                  onTap: () => onPrompt(starter.$3),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '新建对话',
    child: SizedBox(
      height: 28,
      child: AppHoverSurface(
        onTap: enabled ? onTap : null,
        enabled: enabled,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        border: Border.all(color: AppColors.surface0),
        hoverColor: AppColors.text.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 15, color: AppColors.subtext),
            const SizedBox(width: 5),
            Text(
              '新对话',
              style: TextStyle(
                color: enabled ? AppColors.text : AppColors.overlay,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StarterButton extends StatelessWidget {
  const _StarterButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppHoverSurface(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    color: AppColors.mantle,
    hoverColor: AppColors.text.withValues(alpha: .065),
    border: Border.all(color: AppColors.surface0),
    borderRadius: BorderRadius.circular(10),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.subtext),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.text)),
      ],
    ),
  );
}

/// 思考过程行内折叠块（仿 Claude Code "Thought for Xs"）。
/// 默认折叠成一行"思考 Xs"，点击展开看完整思考；运行中也可随时展开。
class _ReasoningTile extends StatefulWidget {
  final String text;
  final int seconds;
  final bool live; // 是否「真正在思考」（运行中且为最后一项），否则是已结束/历史块
  final L10n l;
  const _ReasoningTile({
    required this.text,
    required this.seconds,
    required this.l,
    this.live = false,
  });

  @override
  State<_ReasoningTile> createState() => _ReasoningTileState();
}

class _ReasoningTileState extends State<_ReasoningTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    // 有秒数 → 「思考 Xs」；无秒数：运行中显示「思考中…」，历史/已结束显示「思考过程」
    final title = widget.seconds > 0
        ? l.t('ai.thinkingDone', {'sec': '${widget.seconds}'})
        : (widget.live ? l.t('ai.thinking') : l.t('ai.thinkProcess'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 折叠标题行：脑图标 + "思考 Xs" + 展开箭头
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology_outlined,
                  size: 13,
                  color: AppColors.overlay,
                ),
                const SizedBox(width: 5),
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: AppColors.overlay),
                ),
                const SizedBox(width: 3),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 14,
                  color: AppColors.overlay,
                ),
              ],
            ),
          ),
        ),
        // 展开后：完整思考内容（灰色斜体，左竖线）
        AnimatedSize(
          duration: AppMotion.switcher,
          curve: AppMotion.standard,
          alignment: Alignment.topLeft,
          child: _expanded && widget.text.isNotEmpty
              ? Container(
                  margin: const EdgeInsets.only(top: 4, left: 2),
                  padding: const EdgeInsets.only(left: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: AppColors.surface1, width: 2),
                    ),
                  ),
                  child: SelectableText(
                    widget.text,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.overlay,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// 工具调用紧凑折叠行（仿 Claude Code / Netcatty）。
/// 默认折叠成一行：[图标] 命令 ✓；点击展开看完整输出。信息密度高，一屏可放多条。
class _ToolTile extends StatefulWidget {
  final String name;
  final bool running; // 执行中（结果未回填）
  final bool executed; // 是否真正执行（false=被阻止/拒绝）
  final String cmd; // 工具参数 JSON，如 {"command":"df -h"}
  final String result; // 命令输出
  const _ToolTile({
    required this.name,
    required this.running,
    required this.executed,
    required this.cmd,
    required this.result,
  });

  @override
  State<_ToolTile> createState() => _ToolTileState();
}

class _ToolTileState extends State<_ToolTile> {
  bool _expanded = false;

  /// 从参数 JSON 提取可读命令：execCommand 取 command，其它取 path/原样
  String get _display {
    try {
      final obj = jsonDecode(widget.cmd) as Map<String, dynamic>;
      return (obj['command'] ?? obj['path'] ?? widget.cmd).toString();
    } catch (_) {
      return widget.cmd;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.base,
        border: Border.all(color: AppColors.surface0),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 折叠标题行：终端图标 + 命令 + 状态 + 展开箭头
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 13, color: AppColors.sapphire),
                  const SizedBox(width: 7),
                  // 命令（单行省略），占满中间
                  Expanded(
                    child: Text(
                      _display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 11.5,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 状态：执行中转圈 / 已执行绿勾 / 被阻止红叉
                  if (widget.running)
                    SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.yellow,
                      ),
                    )
                  else if (widget.executed)
                    Icon(
                      Icons.check_circle_outline,
                      size: 12,
                      color: AppColors.green,
                    )
                  else
                    Icon(Icons.block, size: 12, color: AppColors.red),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 14,
                    color: AppColors.overlay,
                  ),
                ],
              ),
            ),
          ),
          // 展开态：完整输出（最高 200px，可选中复制）
          AnimatedSize(
            duration: AppMotion.switcher,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: _expanded && widget.result.isNotEmpty
                ? Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.crust,
                      border: Border(
                        top: BorderSide(color: AppColors.surface0),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        widget.result,
                        style: TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 11.5,
                          color: AppColors.subtext,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
