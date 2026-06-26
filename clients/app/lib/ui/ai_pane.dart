import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../theme.dart';
import '../state/agent_provider.dart';
import '../state/snippet_provider.dart';

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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(agentProvider);
    // 新消息进来自动滚到底
    ref.listen(agentProvider, (prev, next) => _scrollToBottom());
    // 命令片段等外部请求：把文本填进输入框并聚焦末尾
    ref.listen(composerProvider, (prev, next) {
      if (next == null) return;
      _controller.text = next.text;
      _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length));
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
      children.add(_askCard(
        cmd: st.pendingAsk!.command,
        why: '门禁判定：ASK — ${st.pendingAsk!.reason}',
      ));
      children.add(const SizedBox(height: 12));
    }

    return Container(
      color: AppColors.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 对话流
          Expanded(
            child: st.items.isEmpty && st.pendingAsk == null
                ? const Center(
                    child: Text('连接主机后，输入运维任务开始对话',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.overlay)),
                  )
                : SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
          ),
          if (st.error != null)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: AppColors.red.withValues(alpha: .12),
              child: Text('错误：${st.error}',
                  style: const TextStyle(fontSize: 11, color: AppColors.red)),
            ),
          _inputBox(st.running),
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
            text: it.text, seconds: it.reasoningSec ?? 0, live: live);
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
          decoration: const BoxDecoration(
            color: AppColors.surface0,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(2),
            ),
          ),
          child: SelectableText(text,
              style: const TextStyle(fontSize: 13, color: AppColors.text)),
        ),
      );

  // 智能体消息正文（Markdown 渲染：加粗/列表/表格/代码块）
  Widget _assistantMsg({required String text}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.smart_toy_outlined,
                  size: 13, color: AppColors.overlay),
              SizedBox(width: 5),
              Text('智能体',
                  style: TextStyle(fontSize: 10.5, color: AppColors.overlay)),
            ],
          ),
          const SizedBox(height: 4),
          // 可选中复制；Markdown 语法渲染成富文本
          SelectionArea(
            child: GptMarkdown(
              text,
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.text),
            ),
          ),
        ],
      );

  // 思考过程块 → 改用 _ReasoningTile（行内可折叠，见文件末尾）

  // 工具调用卡片 → 改用 _ToolTile（默认折叠的紧凑行，见文件末尾）

  // ASK 确认卡片（黄边，三按钮：允许/拒绝/总是允许）
  Widget _askCard({required String cmd, required String why}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.yellow.withValues(alpha: .08),
          border: Border.all(color: AppColors.yellow),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: AppColors.yellow),
                SizedBox(width: 6),
                Text('需要确认 · 该命令需人工放行',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.yellow)),
              ],
            ),
            const SizedBox(height: 5),
            Text(cmd,
                style: const TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 12,
                    color: AppColors.peach)),
            const SizedBox(height: 5),
            Text(why,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.subtext)),
            const SizedBox(height: 8),
            Row(
              children: [
                _cardBtn('允许执行', danger: true,
                    onTap: () =>
                        ref.read(agentProvider.notifier).resolveAsk(true)),
                const SizedBox(width: 8),
                _cardBtn('拒绝', ghost: true,
                    onTap: () =>
                        ref.read(agentProvider.notifier).resolveAsk(false)),
              ],
            ),
          ],
        ),
      );

  // DENY 拦截卡片（红边）
  Widget _blockedCard({required String cmd, required String why}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: .08),
          border: Border.all(color: AppColors.red),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.block, size: 14, color: AppColors.red),
                SizedBox(width: 6),
                Text('已阻止 · 高危命令',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.red)),
              ],
            ),
            const SizedBox(height: 5),
            Text(cmd,
                style: const TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 11.5,
                    color: AppColors.peach)),
            const SizedBox(height: 5),
            Text(why,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.subtext)),
          ],
        ),
      );

  // 卡片按钮（danger红底 / ghost透明描边）
  Widget _cardBtn(String label,
          {bool danger = false, bool ghost = false, VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: danger ? AppColors.red : Colors.transparent,
            border: ghost ? Border.all(color: AppColors.surface1) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: danger ? FontWeight.w600 : FontWeight.normal,
                  color: danger ? AppColors.crust : AppColors.text)),
        ),
      );

  // AI 输入框 + 快捷键提示。running 时禁用并显示中断。
  Widget _inputBox(bool running) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.mantle,
          border: Border(top: BorderSide(color: AppColors.surface0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.base,
                border: Border.all(color: AppColors.surface1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: !running,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.text),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '输入运维任务，或 @ 引用主机…',
                        hintStyle: TextStyle(
                            fontSize: 13, color: AppColors.overlay),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // running 时显示中断，否则显示发送
                  running
                      ? InkWell(
                          onTap: () =>
                              ref.read(agentProvider.notifier).abort(),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: AppColors.yellow),
                              ),
                              SizedBox(width: 6),
                              Text('中断',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.yellow)),
                            ],
                          ),
                        )
                      : InkWell(
                          onTap: _send,
                          child: const Text('↵ 发送',
                              style: TextStyle(
                                  fontFamily: kMonoFont,
                                  fontSize: 12,
                                  color: AppColors.blue)),
                        ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            DefaultTextStyle(
              style: const TextStyle(
                  fontFamily: kMonoFont, fontSize: 10, color: AppColors.overlay),
              child: Wrap(
                spacing: 14,
                runSpacing: 4,
                children: const [
                  Text('⏎ 发送'),
                  Text('⇧⏎ 换行'),
                  Text('Esc 中断'),
                  Text('⌘K 命令面板'),
                ],
              ),
            ),
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
  const _ReasoningTile(
      {required this.text, required this.seconds, this.live = false});

  @override
  State<_ReasoningTile> createState() => _ReasoningTileState();
}

class _ReasoningTileState extends State<_ReasoningTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // 有秒数 → 「思考 Xs」；无秒数：运行中显示「思考中…」，历史/已结束显示「思考过程」
    final title = widget.seconds > 0
        ? '思考 ${widget.seconds}s'
        : (widget.live ? '思考中…' : '思考过程');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 折叠标题行：脑图标 + "思考 Xs" + 展开箭头
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.psychology_outlined,
                    size: 13, color: AppColors.overlay),
                const SizedBox(width: 5),
                Text(title,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.overlay)),
                const SizedBox(width: 3),
                Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 14,
                    color: AppColors.overlay),
              ],
            ),
          ),
        ),
        // 展开后：完整思考内容（灰色斜体，左竖线）
        if (_expanded && widget.text.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4, left: 2),
            padding: const EdgeInsets.only(left: 9),
            decoration: const BoxDecoration(
              border:
                  Border(left: BorderSide(color: AppColors.surface1, width: 2)),
            ),
            child: SelectableText(widget.text,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: AppColors.overlay)),
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
        color: AppColors.mantle,
        border: Border.all(color: AppColors.surface0),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 折叠标题行：终端图标 + 命令 + 状态 + 展开箭头
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.terminal,
                      size: 13, color: AppColors.sapphire),
                  const SizedBox(width: 7),
                  // 命令（单行省略），占满中间
                  Expanded(
                    child: Text(
                      _display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 11.5,
                          color: AppColors.peach),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 状态：执行中转圈 / 已执行绿勾 / 被阻止红叉
                  if (widget.running)
                    const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AppColors.yellow),
                    )
                  else if (widget.executed)
                    const Icon(Icons.check_circle_outline,
                        size: 12, color: AppColors.green)
                  else
                    const Icon(Icons.block,
                        size: 12, color: AppColors.red),
                  const SizedBox(width: 4),
                  Icon(
                      _expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 14,
                      color: AppColors.overlay),
                ],
              ),
            ),
          ),
          // 展开态：完整输出（最高 200px，可选中复制）
          if (_expanded && widget.result.isNotEmpty)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: const BoxDecoration(
                color: AppColors.crust,
                border: Border(top: BorderSide(color: AppColors.surface0)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(widget.result,
                    style: const TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 11.5,
                        color: AppColors.subtext)),
              ),
            ),
        ],
      ),
    );
  }
}
