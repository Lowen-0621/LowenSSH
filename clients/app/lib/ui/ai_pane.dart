import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../state/agent_provider.dart';

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

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
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

    final children = <Widget>[];
    for (final item in st.items) {
      children.add(_renderItem(item));
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
  Widget _renderItem(ChatItem it) {
    switch (it.kind) {
      case ChatItemKind.user:
        return _userBubble(it.text);
      case ChatItemKind.reasoning:
        return _reasoningBlock(it.text);
      case ChatItemKind.assistant:
        return _assistantMsg(text: it.text);
      case ChatItemKind.tool:
        return _toolCard(
          name: it.toolName ?? '',
          status: it.toolResult == null ? 'run' : 'ok',
          cmd: it.toolArgs ?? '',
          result: it.toolResult ?? '执行中…',
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
          child: Text(text,
              style: const TextStyle(fontSize: 13, color: AppColors.text)),
        ),
      );

  // 智能体消息正文
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
          Text(text,
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.text)),
        ],
      );

  // 思考过程块（reasoning，灰色斜体，左边竖线）
  Widget _reasoningBlock(String text) => Container(
        padding: const EdgeInsets.only(left: 9),
        decoration: const BoxDecoration(
          border:
              Border(left: BorderSide(color: AppColors.surface1, width: 2)),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: AppColors.overlay)),
      );

  // 工具调用卡片（头部名称+状态 / 命令 / 结果）
  Widget _toolCard({
    required String name,
    required String status,
    required String cmd,
    required String result,
  }) {
    final (Color sc, IconData si, String st) = switch (status) {
      'run' => (AppColors.yellow, Icons.pending_outlined, '执行中'),
      _ => (AppColors.green, Icons.check_circle_outline, '已执行'),
    };
    return Container(
      decoration: BoxDecoration(
        color: AppColors.mantle,
        border: Border.all(color: AppColors.surface0),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.terminal,
                    size: 14, color: AppColors.sapphire),
                const SizedBox(width: 7),
                Text(name,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.sapphire)),
                const Spacer(),
                Icon(si, size: 12, color: sc),
                const SizedBox(width: 4),
                Text(st, style: TextStyle(fontSize: 10.5, color: sc)),
              ],
            ),
          ),
          // 命令
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: const BoxDecoration(
              color: AppColors.crust,
              border: Border(top: BorderSide(color: AppColors.surface0)),
            ),
            child: Text(cmd,
                style: const TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 11.5,
                    color: AppColors.peach)),
          ),
          // 结果（最高 80px 截断）
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 80),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.surface0)),
            ),
            child: Text(result,
                overflow: TextOverflow.fade,
                style: const TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 11.5,
                    color: AppColors.subtext)),
          ),
        ],
      ),
    );
  }

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
              child: Row(
                children: const [
                  Text('⏎ 发送'),
                  SizedBox(width: 14),
                  Text('⇧⏎ 换行'),
                  SizedBox(width: 14),
                  Text('Esc 中断'),
                  SizedBox(width: 14),
                  Text('⌘K 命令面板'),
                ],
              ),
            ),
          ],
        ),
      );
}
