import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/agent.dart';
import '../core/events.dart';
import '../core/glm.dart';
import 'config_provider.dart';
import 'connection_provider.dart';

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

/// 会话 Notifier —— 发送任务、消费事件流、桥接 ASK 确认
class AgentNotifier extends Notifier<AgentState> {
  // core 多轮历史（loop 内部用），与 UI items 分离
  final List<ChatMessage> _history = [];
  StreamSubscription<AgentEvent>? _sub;
  int _undoMark = 0; // 本轮发送前的 items 长度，中断时撤回到此

  @override
  AgentState build() {
    ref.onDispose(() => _sub?.cancel());
    return const AgentState();
  }

  /// 用户发送一条运维任务
  Future<void> send(String task) async {
    if (state.running || task.trim().isEmpty) return;

    final conn = ref.read(connectionProvider);
    if (!conn.isConnected) {
      _append(ChatItem(
          kind: ChatItemKind.blocked,
          command: task,
          reason: '尚未连接主机，请先在左栏选择并连接一台主机。'));
      return;
    }

    final cfg = ref.read(configProvider);
    // 记录撤回点（user 气泡之前），中断时回到这里
    _undoMark = state.items.length;
    // 追加用户气泡
    _append(ChatItem(kind: ChatItemKind.user, text: task));
    state = state.copyWith(running: true, error: null);

    final deps = AgentDeps(
      llm: GlmClient(cfg.llm),
      ssh: conn.client!,
      confirmer: _confirm, // ASK 桥接
      history: _history,
    );

    // 消费事件流
    _sub = runAgent(task, deps).listen(
      _onEvent,
      onError: (e) {
        state = state.copyWith(running: false, error: e.toString());
      },
      onDone: () {
        state = state.copyWith(running: false);
      },
    );
  }

  /// Confirmer：loop 遇到 ASK 命令时调用，挂起等 UI 决断
  Future<bool> _confirm(String command, String reason) {
    final ask = PendingAsk(command, reason);
    state = state.copyWith(pendingAsk: ask);
    return ask.completer.future;
  }

  /// UI 点击 ASK 卡片的「允许/拒绝」
  void resolveAsk(bool allow) {
    final ask = state.pendingAsk;
    if (ask == null || ask.completer.isCompleted) return;
    ask.completer.complete(allow);
    state = state.copyWith(clearPending: true);
  }

  /// 中断当前任务：停止流，并撤回本轮的用户输入与 AI 输出（回到发送前）
  void abort() {
    _sub?.cancel();
    _sub = null;
    // 若有挂起确认，按拒绝处理
    final ask = state.pendingAsk;
    if (ask != null && !ask.completer.isCompleted) {
      ask.completer.complete(false);
    }
    // 撤回到本轮发送前的对话项
    final kept = _undoMark <= state.items.length
        ? state.items.sublist(0, _undoMark)
        : state.items;
    state = AgentState(items: kept, running: false);
  }

  // 把 core 事件映射成 UI 对话项
  void _onEvent(AgentEvent ev) {
    switch (ev) {
      case ReasoningEvent(:final text):
        _appendOrExtend(ChatItemKind.reasoning, text);
      case TokenEvent(:final text):
        _appendOrExtend(ChatItemKind.assistant, text);
      case ToolCallEvent(:final name, :final args):
        _append(ChatItem(
            kind: ChatItemKind.tool, toolName: name, toolArgs: args));
      case ToolResultEvent(:final name, :final summary, :final executed):
        // 回填最近一个同名 tool 卡
        final list = [...state.items];
        for (var i = list.length - 1; i >= 0; i--) {
          if (list[i].kind == ChatItemKind.tool &&
              list[i].toolName == name &&
              list[i].toolResult == null) {
            list[i].toolResult = summary;
            list[i].toolExecuted = executed;
            break;
          }
        }
        state = state.copyWith(items: list);
      case BlockedEvent(:final command, :final reason):
        _append(ChatItem(
            kind: ChatItemKind.blocked, command: command, reason: reason));
      case DoneEvent(:final finalText):
        final t = finalText.trim();
        if (t.isEmpty) break; // 空结论：正文已流式显示完，无需追加
        // 去重：若最后一条 assistant 正文已是同样内容（流式已显示过），不再重复追加
        final last = state.items.isNotEmpty ? state.items.last : null;
        if (last != null &&
            last.kind == ChatItemKind.assistant &&
            last.text.trim() == t) {
          break;
        }
        _append(ChatItem(kind: ChatItemKind.assistant, text: t));
      case ErrorEvent(:final message):
        state = state.copyWith(error: message);
    }
  }

  void _append(ChatItem item) {
    state = state.copyWith(items: [...state.items, item]);
  }

  /// 同类型连续增量（reasoning/assistant 流式 token）拼到末尾同类项。
  /// reasoning 额外记录开始时刻并实时更新耗时（秒）。
  void _appendOrExtend(ChatItemKind kind, String delta) {
    final list = [...state.items];
    if (list.isNotEmpty && list.last.kind == kind) {
      list.last.text += delta;
      if (kind == ChatItemKind.reasoning && list.last.reasoningStart != null) {
        list.last.reasoningSec =
            DateTime.now().difference(list.last.reasoningStart!).inSeconds;
      }
      state = state.copyWith(items: list);
    } else {
      _append(ChatItem(
        kind: kind,
        text: delta,
        reasoningStart:
            kind == ChatItemKind.reasoning ? DateTime.now() : null,
        reasoningSec: kind == ChatItemKind.reasoning ? 0 : null,
      ));
    }
  }
}

final agentProvider =
    NotifierProvider<AgentNotifier, AgentState>(AgentNotifier.new);
