/// AI 对话持久化 —— 每台主机一份对话存盘，重启后恢复。
/// 存 `$HOME/.lowenssh/chats/<hostId>.json`（与 config.json 同目录）。
///
/// macOS 沙盒会把 HOME 重定向到容器目录
/// (~/Library/Containers/cn.lowenssh.lowenssh/Data/)，这里复用同一套 $HOME 逻辑，
/// 保证对话文件和 config.json 落在同一个真实位置。
///
/// 一个文件存一台主机：{ "items": [...UI对话项], "history": [...core多轮历史] }。
/// 落盘时机：每轮任务结束写整文件（不做增量），不限条数。
library;

import 'dart:convert';
import 'dart:io';
import '../state/agent_provider.dart';
import 'glm.dart';

String get _chatsDir =>
    '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/.lowenssh/chats';

String _chatFile(String hostId) => '$_chatsDir/$hostId.json';

/// 一台主机的对话存档：UI 对话项 + core 多轮历史
class ChatArchive {
  final List<ChatItem> items;
  final List<ChatMessage> history;
  const ChatArchive({required this.items, required this.history});
}

/// 读取某主机的对话存档；文件不存在或损坏则返回空存档。
ChatArchive loadChat(String hostId) {
  final file = File(_chatFile(hostId));
  if (!file.existsSync()) {
    return const ChatArchive(items: [], history: []);
  }
  try {
    final parsed = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final items = (parsed['items'] as List<dynamic>? ?? [])
        .map((e) => ChatItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final history = (parsed['history'] as List<dynamic>? ?? [])
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    return ChatArchive(items: items, history: history);
  } catch (_) {
    // 存档损坏不影响使用，退回空存档
    return const ChatArchive(items: [], history: []);
  }
}

/// 写入某主机的对话存档（覆盖整文件）。
void saveChat(String hostId, List<ChatItem> items, List<ChatMessage> history) {
  final dir = Directory(_chatsDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final json = jsonEncode({
    'items': items.map((e) => e.toJson()).toList(),
    'history': history.map((e) => e.toJson()).toList(),
  });
  File(_chatFile(hostId)).writeAsStringSync(json);
}

/// 删除某主机的对话存档（删主机时调用）。
void deleteChat(String hostId) {
  final file = File(_chatFile(hostId));
  if (file.existsSync()) {
    try {
      file.deleteSync();
    } catch (_) {}
  }
}
