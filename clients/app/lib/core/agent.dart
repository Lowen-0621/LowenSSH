/// Agent 核心 —— 手写的 agentic loop + 安全门禁。
/// 移植自 TS 版 agent.ts（再上游 Java AgentService），对外用 async* 吐 7 类事件。
///
/// 循环结构（Claude Code 同款状态机）：
///   请求 → 模型返回 → 有 tool_call？
///     有 → 门禁预检 → 全放行才执行工具 → 结果回灌 → 带新历史再请求
///           任一被拒 → 不执行，回灌"拒绝"作为工具结果 → loop 继续让模型换方案
///     无 → 模型给出最终结论，循环结束
///   加最大轮数上限防死循环。
///
/// 安全是独立代码路径：门禁不写进工具、不靠模型自觉，越狱也绕不过。
library;

import 'dart:async';
import 'dart:convert';
import 'guard.dart';
import 'ssh.dart';
import 'glm.dart';
import 'context.dart';
import 'events.dart';

const int maxRounds = 40;
const String _execTool = 'execCommand';

const String systemPrompt = '''## 身份
你是 LowenSSH，一个面向 Linux 服务器的 SSH/SFTP 智能体。
你帮用户远程排查问题、执行命令、读取文件、查看日志，并在用户授权下完成文件传输等运维操作。
你的能力随工具集扩展——当前可用的工具见工具列表，只调用列表里实际存在的工具，不要臆造工具。

## 环境与安全
你执行的每条命令都会经过一道独立的安全门禁，危险命令会被拦截。
被拦时换一个更安全的方式达成目标，不要重复同一条被拒命令，也不要改用等价的危险命令绕过拦截。

## 工作方式
- 先理解任务目标再决定查什么，每步拿到结果后判断下一步，不要一次堆一堆命令。
- 优先用只读命令探查（df / free / ps / cat / tail），看清现状再动有副作用的操作。
- 命令输出可能被截断（节省 token），抓关键信息即可，需要时再精确查询。

## 输出格式
- 用中文，给出结论，不要只罗列原始命令输出。
- 简单结果用自然语言简短回答，多维度信息才用列表或表格。
- 关键数字（磁盘占用 %、内存、负载等）直接点出来，别让用户自己从输出里找。''';

/// 工具集 schema —— 与 Java 版 SshTools 的 @Tool 对齐
final List<ToolDef> tools = [
  const ToolDef(
    name: 'execCommand',
    description:
        '在目标服务器上执行一条 shell 命令，返回标准输出、错误输出和退出码。用于查看系统状态、进程、磁盘等运维操作。',
    parameters: {
      'type': 'object',
      'properties': {
        'command': {'type': 'string', 'description': "要执行的 shell 命令，例如 'df -h'"},
      },
      'required': ['command'],
    },
  ),
  const ToolDef(
    name: 'readRemoteFile',
    description: '读取目标服务器上指定路径的文本文件的完整内容。',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': "远程文件绝对路径，例如 '/etc/nginx/nginx.conf'"},
      },
      'required': ['path'],
    },
  ),
  const ToolDef(
    name: 'tailLog',
    description: '读取目标服务器上日志文件的末尾若干行，用于快速查看最新日志。',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '日志文件绝对路径'},
        'lines': {'type': 'number', 'description': '读取末尾的行数，例如 100'},
      },
      'required': ['path', 'lines'],
    },
  ),
  const ToolDef(
    name: 'listFiles',
    description: '列出目标服务器上指定目录的文件和子目录。',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': "目录绝对路径，例如 '/var/log'"},
      },
      'required': ['path'],
    },
  ),
];

/// 执行一个工具调用，返回喂回模型的文本结果。只读工具直接跑；execCommand 已过门禁。
Future<String> _runTool(SshClient ssh, String name, Map<String, dynamic> args) async {
  try {
    switch (name) {
      case 'execCommand':
        return _formatExec(await ssh.exec((args['command'] ?? '').toString()));
      case 'readRemoteFile':
        return _formatExec(await ssh.exec("cat '${args['path']}'"));
      case 'tailLog':
        final lines = (args['lines'] as num?)?.toInt() ?? 100;
        return _formatExec(await ssh.exec("tail -n $lines '${args['path']}'"));
      case 'listFiles':
        final files = await ssh.listDir((args['path'] ?? '').toString());
        if (files.isEmpty) return '（空目录）${args['path']}';
        final lines = files.map((f) =>
            '${f.isDir ? '[d]' : '[f]'} ${f.name}  ${f.isDir ? '-' : '${f.size}B'}  ${f.perms}');
        return '目录 ${args['path']} 共 ${files.length} 项:\n${lines.join('\n')}';
      default:
        return '未知工具: $name';
    }
  } catch (e) {
    // 工具内部异常不抛给 loop，作为"工具结果"回灌，让模型知道这步失败
    return '命令执行异常: $e';
  }
}

String _formatExec(ExecResult r) {
  var s = 'exitCode=${r.exitCode}\n';
  if (r.stdout.isNotEmpty) s += 'stdout:\n${r.stdout}';
  if (r.stderr.isNotEmpty) s += 'stderr:\n${r.stderr}';
  return s;
}

/// 从 tool_call 参数 JSON 取出 command 字段
String _extractCommand(String argsJson) {
  try {
    final obj = jsonDecode(argsJson) as Map<String, dynamic>;
    return obj['command'] as String? ?? '';
  } catch (_) {
    return '';
  }
}

class AgentDeps {
  final GlmClient llm;
  final SshClient ssh;
  final Confirmer confirmer;

  /// 历史消息（多轮续聊）。首轮传空。loop 结束后调用方可读回更新后的历史。
  final List<ChatMessage>? history;

  const AgentDeps({
    required this.llm,
    required this.ssh,
    required this.confirmer,
    this.history,
  });
}

/// 单个 tool_call 过门禁后的结果：content 回灌给模型，rejected 表示被拒未执行。
class _ScreenResult {
  final String content;
  final bool rejected;
  const _ScreenResult(this.content, this.rejected);
}

/// 跑一轮 agent 任务，返回实时事件流。
/// 用 StreamController 让 token/reasoning 在到达时立即推给 UI（真流式），
/// 而非攒到整轮结束再一次性吐出。loop 跑完或抛错都会 close → 触发 onDone。
Stream<AgentEvent> runAgent(String task, AgentDeps deps) {
  late final StreamController<AgentEvent> controller;
  controller = StreamController<AgentEvent>(
    onListen: () => _runLoop(task, deps, controller),
  );
  return controller.stream;
}

Future<void> _runLoop(
  String task,
  AgentDeps deps,
  StreamController<AgentEvent> out,
) async {
  final llm = deps.llm;
  final ssh = deps.ssh;
  final ctx = ContextManager(llm);

  var messages = <ChatMessage>[
    ChatMessage.system(systemPrompt),
    ...(deps.history ?? const []),
    ChatMessage.user(task),
  ];

  try {
    for (var round = 1; round <= maxRounds; round++) {
      // 进模型前整理上下文：Layer 0 截断 + Layer 4 压缩
      messages = ctx.truncateToolResponses(messages);
      messages = await ctx.compressIfNeeded(messages);

      // 一次流式调用：token/reasoning 实时推给 UI
      final result = await llm.stream(
        messages,
        tools,
        StreamHandlers(
          onToken: (t) => out.add(TokenEvent(t)),
          onReasoning: (t) => out.add(ReasoningEvent(t)),
        ),
      );

      // 没有 tool_call：模型给出最终结论，结束。
      // 正文通常已通过 TokenEvent 流式显示，DoneEvent 仅作结束信号，UI 层去重。
      if (result.toolCalls.isEmpty) {
        out.add(DoneEvent(result.text.trim()));
        return;
      }

      // 落 assistant（文字 + tool_calls）
      final assistant = ChatMessage.assistant(
        result.text.isNotEmpty ? result.text : null,
        toolCalls: result.toolCalls,
      );
      // 先把本轮要调的工具吐出去
      for (final call in result.toolCalls) {
        out.add(ToolCallEvent(call.name, call.arguments));
      }

      // —— 门禁预检 + 执行（事件实时 add）——
      final toolResponses = <ChatMessage>[];
      for (final call in result.toolCalls) {
        final r = await _screenAndRun(call, ssh, deps.confirmer, out.add);
        toolResponses.add(ChatMessage.tool(call.id, r.content));
      }

      // 回灌历史：assistant + 所有 tool 结果（被拒的也回灌"拒绝"文本，让模型换方案）
      messages.add(assistant);
      messages.addAll(toolResponses);
    }

    out.add(DoneEvent('已达到最大循环轮数（$maxRounds），任务可能未完成。请拆分任务后重试。'));
  } catch (e) {
    out.add(ErrorEvent(e.toString()));
  } finally {
    await out.close();
  }
}

/// 对单个 tool_call 过门禁并执行。通过 emit 推 blocked / tool_result 事件。
Future<_ScreenResult> _screenAndRun(
  ToolCall call,
  SshClient ssh,
  Confirmer confirmer,
  void Function(AgentEvent) emit,
) async {
  final name = call.name;
  Map<String, dynamic> args = {};
  try {
    args = jsonDecode(call.arguments) as Map<String, dynamic>;
  } catch (_) {
    // 参数解析失败，交给工具自己处理（会报错回灌）
  }

  // 非 execCommand 的工具（读文件/看日志/列目录）只读，直接放行
  if (name != _execTool) {
    final content = await _runTool(ssh, name, args);
    emit(ToolResultEvent(name, _summarize(content), true));
    return _ScreenResult(content, false);
  }

  final command = _extractCommand(call.arguments);
  final verdict = evaluate(command);

  if (verdict.decision == Decision.deny) {
    final reason = verdict.reason;
    emit(BlockedEvent(command, reason));
    return _ScreenResult('命令被安全门禁拒绝执行（$reason）。请改用更安全的方式。', true);
  }

  if (verdict.decision == Decision.ask) {
    final ok = await confirmer(command, verdict.reason);
    if (!ok) {
      emit(BlockedEvent(command, '用户拒绝: ${verdict.reason}'));
      return const _ScreenResult('用户拒绝执行该命令。请换一种方式或询问用户。', true);
    }
  }

  // ALLOW 或 ASK 已批准：执行
  final content = await _runTool(ssh, name, args);
  emit(ToolResultEvent(name, _summarize(content), true));
  return _ScreenResult(content, false);
}

/// 工具结果摘要：超 500 字符截断（仅用于事件展示，回灌给模型的是完整内容）
String _summarize(String data) =>
    data.length > 500 ? '${data.substring(0, 500)}…' : data;
