/// 命令片段持久化 —— 预置/自定义常用运维命令，存 $HOME/.lowenssh/snippets.json。
/// 与 config.json 同目录（macOS 沙盒同样重定向 HOME，落在容器目录）。
/// 点击片段会把命令填进 AI 输入框，由用户编辑后发送（不直接执行，走门禁更安全）。
library;

import 'dart:convert';
import 'dart:io';

/// 一条命令片段
class Snippet {
  final String label; // 显示名，如「查看磁盘占用」
  final String command; // 实际命令，如 df -h

  const Snippet({required this.label, required this.command});

  factory Snippet.fromJson(Map<String, dynamic> j) => Snippet(
        label: j['label'] as String? ?? '',
        command: j['command'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'label': label, 'command': command};
}

String get _file =>
    '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.lowenssh/snippets.json';

/// 预置片段（首次无文件时写入）—— 均为只读/低风险运维命令
const List<Snippet> _defaults = [
  Snippet(label: '磁盘占用', command: 'df -h'),
  Snippet(label: '内存使用', command: 'free -h'),
  Snippet(label: 'CPU/负载', command: 'top -bn1 | head -15'),
  Snippet(label: '占用CPU最高的进程', command: 'ps aux --sort=-%cpu | head -10'),
  Snippet(label: '占用内存最高的进程', command: 'ps aux --sort=-%mem | head -10'),
  Snippet(label: '监听端口', command: 'ss -tlnp'),
  Snippet(label: '系统日志(最近50行)', command: 'journalctl -n 50 --no-pager'),
  Snippet(label: '当前目录大文件', command: 'du -ah . | sort -rh | head -20'),
  Snippet(label: 'Docker 容器', command: 'docker ps'),
  Snippet(label: '系统负载', command: 'uptime'),
  Snippet(label: '已登录用户', command: 'who'),
  Snippet(label: '网络连接数', command: 'ss -s'),
];

/// 读片段；文件不存在则写入并返回默认集，损坏则返回默认集（不覆盖文件）
List<Snippet> loadSnippets() {
  final file = File(_file);
  if (!file.existsSync()) {
    saveSnippets(_defaults);
    return List.of(_defaults);
  }
  try {
    final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    return list
        .map((e) => Snippet.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return List.of(_defaults);
  }
}

/// 写片段（覆盖整文件）
void saveSnippets(List<Snippet> snippets) {
  final dir = Directory(File(_file).parent.path);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File(_file).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(
          snippets.map((s) => s.toJson()).toList()));
}
