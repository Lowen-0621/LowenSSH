import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/agent.dart';
import '../core/chat_store.dart';
import '../core/agent_history_store.dart';
import '../core/events.dart';
import '../core/glm.dart';
import 'config_provider.dart';
import 'connection_provider.dart';
import 'guard_provider.dart';

/// UI 对话项类型 —— 对应 ai_pane 的几种卡片
enum ChatItemKind { user, assistant, reasoning, tool, blocked, ask }

/// UI 对话项（一条对话流里的一个气泡/卡片）
class ChatItem {
  final ChatItemKind kind;
  String text; // 正文（assistant/user/reasoning/blocked.reason）
  // tool 卡专用
  final String? toolName;
  String? toolArgs;
  String? toolResult;
  bool toolExecuted;
  // blocked/ask 卡专用
  final String? command;
  final String? reason;
  // reasoning 专用：开始时刻 + 思考耗时（秒），用于折叠标题"思考 Xs"
  final DateTime? reasoningStart;
  int? reasoningSec;

  ChatItem({
    required this.kind,
    this.text = '',
    this.toolName,
    this.toolArgs,
    this.toolResult,
    this.toolExecuted = false,
    this.command,
    this.reason,
    this.reasoningStart,
    this.reasoningSec,
  });

  /// 持久化序列化。reasoningStart 是运行时计时用，不存（存结果 reasoningSec 即可）。
  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'text': text,
        if (toolName != null) 'toolName': toolName,
        if (toolArgs != null) 'toolArgs': toolArgs,
        if (toolResult != null) 'toolResult': toolResult,
        'toolExecuted': toolExecuted,
        if (command != null) 'command': command,
        if (reason != null) 'reason': reason,
        if (reasoningSec != null) 'reasoningSec': reasoningSec,
      };

  factory ChatItem.fromJson(Map<String, dynamic> j) => ChatItem(
        kind: ChatItemKind.values.byName(j['kind'] as String),
        text: j['text'] as String? ?? '',
        toolName: j['toolName'] as String?,
        toolArgs: j['toolArgs'] as String?,
        toolResult: j['toolResult'] as String?,
        toolExecuted: j['toolExecuted'] as bool? ?? false,
        command: j['command'] as String?,
        reason: j['reason'] as String?,
        reasoningSec: (j['reasoningSec'] as num?)?.toInt(),
      );
}

/// 待确认请求（ASK 态）—— Completer 桥接 loop 与 UI
class PendingAsk {
  final String command;
  final String reason;
  final Completer<bool> completer;
  PendingAsk(this.command, this.reason) : completer = Completer<bool>();
}

/// 会话状态
class AgentState {
  final List<ChatItem> items;
  final bool running;
  final PendingAsk? pendingAsk; // 非 null 时 UI 显示确认卡
  final String? error;

  const AgentState({
    this.items = const [],
    this.running = false,
    this.pendingAsk,
    this.error,
  });

  AgentState copyWith({
    List<ChatItem>? items,
    bool? running,
    PendingAsk? pendingAsk,
    bool clearPending = false,
    String? error,
  }) =>
      AgentState(
        items: items ?? this.items,
        running: running ?? this.running,
        pendingAsk: clearPending ? null : (pendingAsk ?? this.pendingAsk),
        error: error,
      );
}

/// 单台主机的会话状态（内存隔离的最小单元）。
/// 每台主机一份：独立的对话项、core 多轮历史、运行态、挂起确认、事件订阅。
class _HostSession {
  final List<ChatItem> items = [];
  final List<ChatMessage> history = []; // core loop 多轮历史
  bool running = false;
  PendingAsk? pendingAsk;
  String? error;
  StreamSubscription<AgentEvent>? sub;
  int undoMark = 0; // 本轮发送前的 items 长度，中断时撤回到此
}

/// 会话 Notifier —— 按主机分桶隔离对话。
/// 内部维护 `Map<hostId, _HostSession>`；当前展示哪台由 connectionProvider 的 host 决定。
/// 关键：事件回调绑定「发起任务时的 hostId」，而非「当前展示的 host」，
/// 所以 A 主机任务运行时切到 B，A 的输出仍写进 A 的会话；切回 A 可看到继续更新。
class AgentNotifier extends Notifier<AgentState> {
  final Map<String, _HostSession> _sessions = {};
  String? _currentHostId; // 当前展示的主机 id

  @override
  AgentState build() {
    // 监听主机切换：切到哪台就把 state 换成那台会话的快照
    ref.listen(connectionProvider.select((s) => s.host?.id), (prev, next) {
      _currentHostId = next;
      _syncState();
    });
    _currentHostId = ref.read(connectionProvider).host?.id;
    ref.onDispose(() {
      for (final s in _sessions.values) {
        s.sub?.cancel();
      }
    });
    return _snapshot(_currentHostId);
  }

  /// 取某主机会话（不存在则从磁盘加载存档建一份）
  _HostSession _session(String hostId) =>
      _sessions.putIfAbsent(hostId, () {
        final s = _HostSession();
        // 懒加载：首次访问该主机时恢复落盘的对话 + 多轮历史
        final archive = loadChat(hostId);
        s.items.addAll(archive.items);
        s.history.addAll(archive.history);
        return s;
      });

  /// 把某主机会话落盘（每轮结束/中断后调用）
  void _persist(String hostId) {
    final s = _sessions[hostId];
    if (s == null) return;
    saveChat(hostId, s.items, s.history);
  }

  /// 某主机是否有 AI 任务正在运行（供连接池 LRU 判断「忙的不踢」）
  bool isBusy(String hostId) => _sessions[hostId]?.running ?? false;

  /// 取主机显示名（别名优先），用于审计标注来源
  String _hostName(String hostId) {
    final cfg = ref.read(configProvider);
    for (final h in cfg.hosts) {
      if (h.id == hostId) {
        return h.alias?.isNotEmpty == true ? h.alias! : h.host;
      }
    }
    return hostId;
  }

  /// 从工具名 + 参数 JSON 提取可读命令，用于审计展示。
  /// execCommand 取 command；只读工具取 path；解析失败退回工具名。
  String _readableCmd(String tool, String? argsJson) {
    if (argsJson == null) return tool;
    try {
      final obj = jsonDecode(argsJson) as Map<String, dynamic>;
      final cmd = obj['command'] ?? obj['path'];
      if (cmd != null) return tool == 'execCommand' ? '$cmd' : '$tool: $cmd';
      return tool;
    } catch (_) {
      return tool;
    }
  }

  /// 把某会话投影成对外 AgentState（会触发懒加载，恢复落盘的对话）
  AgentState _snapshot(String? hostId) {
    if (hostId == null) return const AgentState();
    final s = _session(hostId); // 首次访问自动从磁盘恢复
    return AgentState(
      items: s.items,
      running: s.running,
      pendingAsk: s.pendingAsk,
      error: s.error,
    );
  }

  /// 若传入的 hostId 正是当前展示主机，则刷新对外 state（驱动 UI 重建）
  void _refreshIfCurrent(String hostId) {
    if (hostId == _currentHostId) _syncState();
  }

  /// 用当前展示主机的会话刷新对外 state
  void _syncState() {
    state = _snapshot(_currentHostId);
  }

  /// 用户发送一条运维任务（落到当前展示主机的会话）
  Future<void> send(String task) async {
    if (task.trim().isEmpty) return;

    final conn = ref.read(connectionProvider);
    final hostId = conn.host?.id;
    if (hostId == null || !conn.isConnected) {
      // 未连接：临时挂一条阻断提示到当前会话（若有），否则忽略
      if (hostId != null) {
        final s = _session(hostId);
        s.items.add(ChatItem(
            kind: ChatItemKind.blocked,
            command: task,
            reason: '尚未连接主机，请先在左栏选择并连接一台主机。'));
        _refreshIfCurrent(hostId);
      }
      return;
    }

    final s = _session(hostId);
    if (s.running) return; // 该主机已有任务在跑

    final cfg = ref.read(configProvider);
    // 记录撤回点（user 气泡之前），中断时回到这里
    s.undoMark = s.items.length;
    s.items.add(ChatItem(kind: ChatItemKind.user, text: task));
    s.running = true;
    s.error = null;
    _refreshIfCurrent(hostId);

    final deps = AgentDeps(
      llm: GlmClient(cfg.llm),
      ssh: conn.client!,
      confirmer: (cmd, reason) => _confirm(hostId, cmd, reason), // ASK 桥接（绑定 hostId）
      history: s.history,
    );

    // 消费事件流：所有回调绑定 hostId，写进对应会话
    s.sub = runAgent(task, deps).listen(
      (ev) => _onEvent(hostId, ev),
      onError: (e) {
        s.error = e.toString();
        s.running = false;
        _refreshIfCurrent(hostId);
        _persist(hostId); // 出错也落盘（保留已产生的对话）
      },
      onDone: () {
        s.running = false;
        _refreshIfCurrent(hostId);
        _persist(hostId); // 一轮结束落盘
      },
    );
  }

  /// Confirmer：loop 遇到 ASK 命令时调用，挂起等 UI 决断
  Future<bool> _confirm(String hostId, String command, String reason) {
    ref.read(guardProvider.notifier).recordAsk(); // 记一次待确认
    final ask = PendingAsk(command, reason);
    _session(hostId).pendingAsk = ask;
    _refreshIfCurrent(hostId);
    return ask.completer.future;
  }

  /// UI 点击 ASK 卡片的「允许/拒绝」（作用于当前展示主机）
  void resolveAsk(bool allow) {
    final hostId = _currentHostId;
    if (hostId == null) return;
    final s = _sessions[hostId];
    final ask = s?.pendingAsk;
    if (s == null || ask == null || ask.completer.isCompleted) return;
    ask.completer.complete(allow);
    s.pendingAsk = null;
    _refreshIfCurrent(hostId);
  }

  /// 中断当前展示主机的任务：停止流，撤回本轮的用户输入与 AI 输出
  void abort() {
    final hostId = _currentHostId;
    if (hostId == null) return;
    final s = _sessions[hostId];
    if (s == null) return;
    s.sub?.cancel();
    s.sub = null;
    // 若有挂起确认，按拒绝处理
    final ask = s.pendingAsk;
    if (ask != null && !ask.completer.isCompleted) {
      ask.completer.complete(false);
    }
    s.pendingAsk = null;
    // 撤回到本轮发送前的对话项
    if (s.undoMark <= s.items.length) {
      s.items.removeRange(s.undoMark, s.items.length);
    }
    s.running = false;
    _refreshIfCurrent(hostId);
    _persist(hostId); // 撤回后落盘（与磁盘保持一致）
  }

  // 把 core 事件映射成 UI 对话项，写进指定 hostId 的会话
  void _onEvent(String hostId, AgentEvent ev) {
    final s = _sessions[hostId];
    if (s == null) return;
    // reasoning 块在下一个非 reasoning 事件到来时定格耗时，避免一直显示「思考中…」
    if (ev is! ReasoningEvent) _sealReasoning(s);
    switch (ev) {
      case ReasoningEvent(:final text):
        _appendOrExtend(hostId, s, ChatItemKind.reasoning, text);
      case TokenEvent(:final text):
        _appendOrExtend(hostId, s, ChatItemKind.assistant, text);
      case ToolCallEvent(:final name, :final args):
        s.items.add(ChatItem(
            kind: ChatItemKind.tool, toolName: name, toolArgs: args));
        _refreshIfCurrent(hostId);
      case ToolResultEvent(:final name, :final summary, :final executed):
        // 回填最近一个同名 tool 卡，并取出其命令文本用于审计
        String? auditCmd;
        for (var i = s.items.length - 1; i >= 0; i--) {
          if (s.items[i].kind == ChatItemKind.tool &&
              s.items[i].toolName == name &&
              s.items[i].toolResult == null) {
            s.items[i].toolResult = summary;
            s.items[i].toolExecuted = executed;
            auditCmd = _readableCmd(name, s.items[i].toolArgs);
            break;
          }
        }
        if (executed) {
          // 成功执行计入已放行 + 落审计（带具体命令）
          ref.read(guardProvider.notifier).recordAllow(
              auditCmd ?? name,
              host: _hostName(hostId));
        }
        _refreshIfCurrent(hostId);
      case BlockedEvent(:final command, :final reason):
        ref
            .read(guardProvider.notifier)
            .recordDeny(command, host: _hostName(hostId)); // 计入已阻止+历史+审计
        s.items.add(ChatItem(
            kind: ChatItemKind.blocked, command: command, reason: reason));
        _refreshIfCurrent(hostId);
      case DoneEvent(:final finalText):
        final t = finalText.trim();
        if (t.isEmpty) break; // 空结论：正文已流式显示完，无需追加
        // 去重：若最后一条 assistant 正文已是同样内容（流式已显示过），不再重复追加
        final last = s.items.isNotEmpty ? s.items.last : null;
        if (last != null &&
            last.kind == ChatItemKind.assistant &&
            last.text.trim() == t) {
          break;
        }
        s.items.add(ChatItem(kind: ChatItemKind.assistant, text: t));
        _refreshIfCurrent(hostId);
      case ErrorEvent(:final message):
        s.error = message;
        _refreshIfCurrent(hostId);
    }
  }

  /// 定格最后一个 reasoning 块的耗时（思考结束、转入工具/正文时调用）。
  /// 避免「思考中…」不消失：用 reasoningStart 算最终秒数，不足 1 秒按 1 秒计。
  /// 顺便丢弃纯空白的思考块（GLM 偶尔吐单个换行的空 reasoning，会显示成空白块）。
  void _sealReasoning(_HostSession s) {
    if (s.items.isEmpty) return;
    final last = s.items.last;
    if (last.kind != ChatItemKind.reasoning) return;
    if (last.text.trim().isEmpty) {
      s.items.removeLast(); // 空思考块，丢弃
      return;
    }
    if (last.reasoningStart != null) {
      final sec = DateTime.now().difference(last.reasoningStart!).inSeconds;
      last.reasoningSec = sec < 1 ? 1 : sec;
    } else {
      last.reasoningSec ??= 1;
    }
  }

  /// 同类型连续增量（reasoning/assistant 流式 token）拼到末尾同类项。
  /// reasoning 额外记录开始时刻并实时更新耗时（秒）。
  void _appendOrExtend(
      String hostId, _HostSession s, ChatItemKind kind, String delta) {
    final items = s.items;
    if (items.isNotEmpty && items.last.kind == kind) {
      items.last.text += delta;
      if (kind == ChatItemKind.reasoning && items.last.reasoningStart != null) {
        items.last.reasoningSec =
            DateTime.now().difference(items.last.reasoningStart!).inSeconds;
      }
    } else {
      items.add(ChatItem(
        kind: kind,
        text: delta,
        reasoningStart:
            kind == ChatItemKind.reasoning ? DateTime.now() : null,
        reasoningSec: kind == ChatItemKind.reasoning ? 0 : null,
      ));
    }
    _refreshIfCurrent(hostId);
  }

  /// 关闭智能体面板：把当前展示主机的会话归档到历史，然后清空当前会话。
  /// 当前会话存盘(chat_store)也一并清空，重启后当前会话为空（历史仍在）。
  void archiveAndClear() {
    final hostId = _currentHostId;
    if (hostId == null) return;
    final s = _sessions[hostId];
    if (s == null) return;
    if (s.running) return; // 任务运行中不归档，避免截断
    // 有内容才归档
    if (s.items.isNotEmpty) {
      appendAgentHistory(hostId, List.of(s.items), List.of(s.history));
    }
    s.items.clear();
    s.history.clear();
    s.error = null;
    _persist(hostId); // 清空当前会话存档
    _refreshIfCurrent(hostId);
  }

  /// 读取当前展示主机的历史会话列表（供历史面板展示）。
  List<AgentHistoryEntry> historyEntries() {
    final hostId = _currentHostId;
    if (hostId == null) return [];
    return loadAgentHistory(hostId);
  }

  /// 从历史恢复一条会话到当前会话（先把当前会话归档，避免覆盖丢失）。
  void restoreHistory(String entryId) {
    final hostId = _currentHostId;
    if (hostId == null) return;
    final s = _session(hostId);
    if (s.running) return;
    final entries = loadAgentHistory(hostId);
    AgentHistoryEntry? target;
    for (final e in entries) {
      if (e.id == entryId) {
        target = e;
        break;
      }
    }
    if (target == null) return;
    // 当前会话非空则先归档，再载入历史
    if (s.items.isNotEmpty) {
      appendAgentHistory(hostId, List.of(s.items), List.of(s.history));
    }
    s.items
      ..clear()
      ..addAll(target.items);
    s.history
      ..clear()
      ..addAll(target.history);
    s.error = null;
    _persist(hostId);
    _refreshIfCurrent(hostId);
  }

  /// 删除一条历史会话。
  void deleteHistory(String entryId) {
    final hostId = _currentHostId;
    if (hostId == null) return;
    deleteAgentHistoryEntry(hostId, entryId);
    _refreshIfCurrent(hostId);
  }
}

final agentProvider =
    NotifierProvider<AgentNotifier, AgentState>(AgentNotifier.new);
