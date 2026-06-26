/// 审计日志持久化 —— 记录每条经过门禁的命令，存 $HOME/.lowenssh/audit.json。
/// 全局一个列表（每条标注来自哪台主机），最新在前，最多保留 _maxEntries 条防膨胀。
/// 与 config.json 同目录（macOS 沙盒重定向 HOME 同样适用）。
library;

import 'dart:convert';
import 'dart:io';

/// 一条审计记录
class AuditEntry {
  final String command;
  final String decision; // deny / ask / allow
  final bool executed; // 是否真正执行（deny/拒绝为 false）
  final String host; // 来源主机显示名（别名或 host）
  final DateTime time;

  const AuditEntry({
    required this.command,
    required this.decision,
    required this.executed,
    required this.host,
    required this.time,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        command: j['command'] as String? ?? '',
        decision: j['decision'] as String? ?? 'allow',
        executed: j['executed'] as bool? ?? false,
        host: j['host'] as String? ?? '-',
        time: DateTime.tryParse(j['time'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'command': command,
        'decision': decision,
        'executed': executed,
        'host': host,
        'time': time.toIso8601String(),
      };
}

/// 最多保留条数
const int _maxEntries = 500;

String get _file =>
    '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.lowenssh/audit.json';

/// 读全部审计记录（最新在前）。文件不存在/损坏返回空。
List<AuditEntry> loadAudit() {
  final file = File(_file);
  if (!file.existsSync()) return [];
  try {
    final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    return list
        .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

/// 追加一条审计记录（写整文件，超过上限丢弃最旧的）。返回更新后的列表。
List<AuditEntry> appendAudit(AuditEntry entry) {
  final list = [entry, ...loadAudit()];
  if (list.length > _maxEntries) list.removeRange(_maxEntries, list.length);
  _write(list);
  return list;
}

/// 清空审计
void clearAudit() => _write(const []);

void _write(List<AuditEntry> list) {
  final dir = Directory(File(_file).parent.path);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File(_file).writeAsStringSync(
      jsonEncode(list.map((e) => e.toJson()).toList()));
}
