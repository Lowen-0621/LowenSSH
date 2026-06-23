import 'package:flutter/material.dart';
import '../theme.dart';

/// 终端面板 —— 静态命令输出（Step 4 替换为 xterm TerminalView）
/// 对应设计稿 .pane.terminal
class TerminalPane extends StatelessWidget {
  const TerminalPane({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.crust,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        child: DefaultTextStyle(
          style: const TextStyle(
              fontFamily: kMonoFont, fontSize: 12, height: 1.55),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _promptLine('df -h'),
              _out('Filesystem      Size  Used Avail Use% Mounted on'),
              _outWithWarn('/dev/sda1        50G   46G  1.5G  ', '92%', ' /'),
              _out('tmpfs           3.9G     0  3.9G   0% /dev/shm'),
              _promptLine('du -sh /var/log/*'),
              _out('2.1G  /var/log/nginx'),
              _out('1.8G  /var/log/app'),
              _out('512M  /var/log/syslog'),
              // 光标行
              Row(
                children: [
                  _prompt(),
                  const SizedBox(width: 4),
                  Container(width: 7, height: 14, color: AppColors.text),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 提示符 root@web01:~#
  Widget _prompt() => RichText(
        text: const TextSpan(
          style: TextStyle(fontFamily: kMonoFont, fontSize: 12),
          children: [
            TextSpan(text: 'root@web01', style: TextStyle(color: AppColors.green)),
            TextSpan(text: ':', style: TextStyle(color: AppColors.text)),
            TextSpan(text: '~', style: TextStyle(color: AppColors.blue)),
            TextSpan(text: '# ', style: TextStyle(color: AppColors.text)),
          ],
        ),
      );

  // 提示符 + 已输入命令
  Widget _promptLine(String cmd) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Row(
          children: [
            _prompt(),
            Text(cmd,
                style: const TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 12,
                    color: AppColors.text)),
          ],
        ),
      );

  Widget _out(String text) => Text(text,
      style: const TextStyle(
          fontFamily: kMonoFont, fontSize: 12, color: AppColors.subtext));

  // 输出行中高亮某段（如 92% 用黄色警告）
  Widget _outWithWarn(String pre, String warn, String post) => RichText(
        text: TextSpan(
          style: const TextStyle(
              fontFamily: kMonoFont, fontSize: 12, color: AppColors.subtext),
          children: [
            TextSpan(text: pre),
            TextSpan(text: warn, style: const TextStyle(color: AppColors.yellow)),
            TextSpan(text: post),
          ],
        ),
      );
}
