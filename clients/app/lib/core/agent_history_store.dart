/// AI 会话历史归档 —— 关闭智能体面板时，把当前会话整段存档，
/// 之后可在历史列表里翻看/恢复。与 chat_store(当前会话) 分开存。
///
/// 存 `$HOME/.lowenssh/agent_history/<hostId>.json`，内容是一个数组，
/// 每个元素是一次会话快照：{ id, title, ts, items, history }。
/// 复用与 config.json 相同的 $HOME 逻辑（macOS 沙盒会重定向 HOME）。
library;

import 'dart:convert';
import 'dart:io';
import '../state/agent_provider.dart';
import 'glm.dart';

String get _historyDir =>
    '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.lowenssh/agent_history';

String _historyFile(String hostId) => '$_historyDir/$hostId.json';

/// 一条历史会话记录
class AgentHistoryEntry {
  final String id; // 唯一标识（时间戳毫秒字符串）
  final String title; // 列表展示标题（取首条用户消息摘要）
  final int ts; // 归档时刻（毫秒）
  final List<ChatItem> items; // UI 对话项
  final List<ChatMessage> history; // core 多轮历史

  const AgentHistoryEntry({
    required this.id,
    required this.title,
    required this.ts,
    required this.items,
    required this.history,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'ts': ts,
        'items': items.map((e) => e.toJson()).toList(),
        'history': history.map((e) => e.toJson()).toList(),
      };

  factory AgentHistoryEntry.fromJson(Map<String, dynamic> j) =>
      AgentHistoryEntry(
        id: j['id'] as String? ?? '${j['ts'] ?? 0}',
        title: j['title'] as String? ?? '',
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        items: (j['items'] as List<dynamic>? ?? [])
            .map((e) => ChatItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        history: (j['history'] as List<dynamic>? ?? [])
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 读取某主机的全部历史会话（按时间倒序，最新在前）；无文件返回空。
List<AgentHistoryEntry> loadAgentHistory(String hostId) {
  final file = File(_historyFile(hostId));
  if (!file.existsSync()) return [];
  try {
    final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    final entries = list
        .map((e) => AgentHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    entries.sort((a, b) => b.ts.compareTo(a.ts)); // 最新在前
    return entries;
  } catch (_) {
    return [];
  }
}

/// 追加一条历史会话存档（写整文件）。items 为空则跳过（不存空会话）。
void appendAgentHistory(
    String hostId, List<ChatItem> items, List<ChatMessage> history) {
  if (items.isEmpty) return;
  final dir = Directory(_historyDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final now = DateTime.now().millisecondsSinceEpoch;
  // 标题取首条用户消息，截断 30 字；无则用「未命名会话」
  String title = '';
  for (final it in items) {
    if (it.kind == ChatItemKind.user && it.text.trim().isNotEmpty) {
      title = it.text.trim();
      break;
    }
  }
  if (title.isEmpty) title = items.first.text.trim();
  if (title.length > 30) title = '${title.substring(0, 30)}…';

  final entry = AgentHistoryEntry(
    id: '$now',
    title: title,
    ts: now,
    items: items,
    history: history,
  );

  final existing = loadAgentHistory(hostId);
  existing.insert(0, entry); // 最新在前
  File(_historyFile(hostId))
      .writeAsStringSync(jsonEncode(existing.map((e) => e.toJson()).toList()));
}

/// 删除某主机某条历史会话。
void deleteAgentHistoryEntry(String hostId, String entryId) {
  final existing = loadAgentHistory(hostId);
  existing.removeWhere((e) => e.id == entryId);
  final dir = Directory(_historyDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File(_historyFile(hostId))
      .writeAsStringSync(jsonEncode(existing.map((e) => e.toJson()).toList()));
}
