import 'package:flutter/material.dart';
import '../theme.dart';

/// AI 对话面板 —— 对话流 + 工具卡片 + 门禁卡片 + 输入框
/// 对应设计稿 .pane.ai。三种卡片(tool/ask/blocked)是门禁可视化核心。
class AiPane extends StatelessWidget {
  const AiPane({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 对话流
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _userBubble('web01 磁盘满了，帮我查下哪占的空间，清理掉能删的日志'),
                  const SizedBox(height: 12),
                  _assistantMsg(
                    reasoning: '先看磁盘占用，定位大文件，再判断哪些日志可以安全清理…',
                    text: '根目录已用 92%。我先看一下各目录占用情况。',
                  ),
                  const SizedBox(height: 12),
                  _toolCard(
                    name: 'execCommand',
                    status: 'ok',
                    cmd: 'du -sh /var/log/*',
                    result:
                        '2.1G /var/log/nginx\n1.8G /var/log/app\n512M /var/log/syslog',
                  ),
                  const SizedBox(height: 12),
                  _assistantMsg(
                      text: 'nginx 和 app 日志占了 3.9G。旧的轮转日志可以安全删除，但我要先确认。'),
                  const SizedBox(height: 12),
                  // ASK 态：内联确认
                  _askCard(
                    cmd: 'rm -f /var/log/nginx/*.gz /var/log/app/*.1',
                    why: '门禁判定：ASK — 匹配规则「rm 删除操作需人工确认」',
                  ),
                  const SizedBox(height: 12),
                  // DENY 态：被拦截
                  _blockedCard(
                    cmd: 'rm -rf /var --no-preserve-root',
                    why: '门禁判定：DENY — 匹配规则「递归删除系统目录」，已阻止执行并回灌模型',
                  ),
                ],
              ),
            ),
          ),
          _inputBox(),
        ],
      ),
    );
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

  // 智能体消息（可选 reasoning 斜体 + 正文）
  Widget _assistantMsg({String? reasoning, required String text}) => Column(
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
          if (reasoning != null) ...[
            Container(
              padding: const EdgeInsets.only(left: 9),
              decoration: const BoxDecoration(
                border:
                    Border(left: BorderSide(color: AppColors.surface1, width: 2)),
              ),
              child: Text(reasoning,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.overlay)),
            ),
            const SizedBox(height: 4),
          ],
          Text(text,
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.text)),
        ],
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
                Text('需要确认 · 该命令会删除文件',
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
                _cardBtn('允许执行', danger: true),
                const SizedBox(width: 8),
                _cardBtn('拒绝', ghost: true),
                const SizedBox(width: 8),
                _cardBtn('总是允许此类', ghost: true),
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
  Widget _cardBtn(String label, {bool danger = false, bool ghost = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
      );

  // AI 输入框 + 快捷键提示
  Widget _inputBox() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.mantle,
          border: Border(top: BorderSide(color: AppColors.surface0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.base,
                border: Border.all(color: AppColors.surface1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Expanded(
                    child: Text('输入运维任务，或 @ 引用主机…',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.overlay)),
                  ),
                  Text('↵ 发送',
                      style: TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 12,
                          color: AppColors.blue)),
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
