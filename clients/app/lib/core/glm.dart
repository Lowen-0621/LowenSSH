/// GLM 接入 —— OpenAI 兼容协议封装，支持 function calling + streaming + reasoning_content。
/// 移植自 TS 版 glm.ts（CLI 用 openai sdk，这里用 dio 手写 SSE 解析）。
///
/// 模型无关设计：换模型只改 baseURL / model（GLM / 通义 / DeepSeek 都走 OpenAI 兼容协议）。
/// GLM 端点是 .../paas/v4/chat/completions，baseURL 指到 .../paas/v4 即可。
library;

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'config.dart';

/// 对话消息（OpenAI chat 格式子集，够 agent loop 用）。
/// 用一个类承载四种 role，toJson 按 role 产出对应字段。
class ChatMessage {
  final String role; // system | user | assistant | tool
  final String? content;
  final List<ToolCall>? toolCalls; // 仅 assistant
  final String? toolCallId; // 仅 tool

  const ChatMessage._({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
  });

  factory ChatMessage.system(String content) =>
      ChatMessage._(role: 'system', content: content);
  factory ChatMessage.user(String content) =>
      ChatMessage._(role: 'user', content: content);
  factory ChatMessage.assistant(String? content, {List<ToolCall>? toolCalls}) =>
      ChatMessage._(role: 'assistant', content: content, toolCalls: toolCalls);
  factory ChatMessage.tool(String toolCallId, String content) =>
      ChatMessage._(role: 'tool', content: content, toolCallId: toolCallId);

  Map<String, dynamic> toJson() {
    switch (role) {
      case 'assistant':
        return {
          'role': 'assistant',
          'content': content,
          if (toolCalls != null && toolCalls!.isNotEmpty)
            'tool_calls': toolCalls!.map((t) => t.toJson()).toList(),
        };
      case 'tool':
        return {'role': 'tool', 'tool_call_id': toolCallId, 'content': content};
      default:
        return {'role': role, 'content': content};
    }
  }

  /// 从持久化 JSON 还原（toJson 的逆）。用于重启后恢复多轮历史。
  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final tc = (j['tool_calls'] as List<dynamic>?)
        ?.map((e) => ToolCall.fromJson(e as Map<String, dynamic>))
        .toList();
    return ChatMessage._(
      role: j['role'] as String,
      content: j['content'] as String?,
      toolCalls: tc,
      toolCallId: j['tool_call_id'] as String?,
    );
  }
}

/// 一次工具调用
class ToolCall {
  final String id;
  final String name;
  final String arguments;
  const ToolCall({required this.id, required this.name, required this.arguments});

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': arguments},
      };

  /// 从持久化 JSON 还原（toJson 的逆）
  factory ToolCall.fromJson(Map<String, dynamic> j) {
    final fn = j['function'] as Map<String, dynamic>?;
    return ToolCall(
      id: j['id'] as String? ?? '',
      name: fn?['name'] as String? ?? '',
      arguments: fn?['arguments'] as String? ?? '',
    );
  }
}

/// 工具定义（function schema）
class ToolDef {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  const ToolDef({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

/// token 用量（用于缓存命中测量）
class Usage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int cachedTokens;
  const Usage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.cachedTokens = 0,
  });
}

/// 一次模型响应聚合结果
class ChatResult {
  final String text; // 正文 content 聚合
  final String reasoning; // 思考 reasoning_content 聚合（GLM 有时把结论放这里）
  final List<ToolCall> toolCalls;
  final Usage? usage;
  const ChatResult({
    required this.text,
    this.reasoning = '',
    required this.toolCalls,
    this.usage,
  });
}

/// 流式回调：边收边推
class StreamHandlers {
  final void Function(String text)? onToken;
  final void Function(String text)? onReasoning;
  const StreamHandlers({this.onToken, this.onReasoning});
}

class GlmClient {
  final Dio _dio;
  final String _model;

  GlmClient(LlmConfig cfg)
      : _model = cfg.model,
        _dio = Dio(BaseOptions(
          baseUrl: cfg.baseURL,
          headers: {
            'Authorization': 'Bearer ${cfg.apiKey}',
            'Content-Type': 'application/json',
          },
          // 流式响应不设接收超时，避免长思考被截断
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: null,
        ));

  /// 一次流式调用：透传 token / reasoning 增量，聚合成完整结果返回。
  /// 关闭框架自动工具执行——工具调用聚合后交回上层 loop 过门禁再执行。
  Future<ChatResult> stream(
    List<ChatMessage> messages,
    List<ToolDef> tools,
    StreamHandlers handlers,
  ) async {
    final resp = await _dio.post<ResponseBody>(
      '/chat/completions',
      data: {
        'model': _model,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (tools.isNotEmpty) 'tools': tools.map((t) => t.toJson()).toList(),
        'stream': true,
        'stream_options': {'include_usage': true},
      },
      options: Options(responseType: ResponseType.stream),
    );

    var text = '';
    var reasoningText = ''; // 聚合 reasoning_content（GLM 有时把结论放这里）
    // tool_calls 在流式下分片到达，按 index 累积
    final toolAcc = <int, _ToolAcc>{};
    Usage? usage;

    // SSE 按行解析：data: {...}\n\n，可能跨 chunk，需缓冲。
    // 关键：用 utf8.decoder 流式解码，它会自动缓存跨 chunk 的多字节字符尾巴，
    // 避免一个中文字（3 字节）被 chunk 边界切断后解成乱码 �。
    final decoded = utf8.decoder.bind(resp.data!.stream);
    var buffer = '';

    await for (final chunkText in decoded) {
      buffer += chunkText;
      // 按 SSE 事件分隔（\n 行）逐行处理，保留最后不完整行到 buffer
      final lines = buffer.split('\n');
      buffer = lines.removeLast(); // 最后一段可能不完整，留待下个 chunk

      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') continue;

        final Map<String, dynamic> json;
        try {
          json = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue; // 跳过无法解析的行
        }

        final choices = json['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final delta = (choices[0] as Map<String, dynamic>)['delta']
                  as Map<String, dynamic>? ??
              {};

          // GLM 思考阶段：reasoning_content 增量，单独推 + 聚合（结论可能在此）
          final reasoning = delta['reasoning_content'] as String?;
          if (reasoning != null && reasoning.isNotEmpty) {
            reasoningText += reasoning;
            handlers.onReasoning?.call(reasoning);
          }
          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            text += content;
            handlers.onToken?.call(content);
          }
          final tcs = delta['tool_calls'] as List<dynamic>?;
          if (tcs != null) {
            for (final tcRaw in tcs) {
              final tc = tcRaw as Map<String, dynamic>;
              final index = (tc['index'] as num?)?.toInt() ?? 0;
              final cur = toolAcc.putIfAbsent(index, () => _ToolAcc());
              if (tc['id'] != null) cur.id = tc['id'] as String;
              final fn = tc['function'] as Map<String, dynamic>?;
              if (fn != null) {
                if (fn['name'] != null) cur.name = fn['name'] as String;
                if (fn['arguments'] != null) cur.args += fn['arguments'] as String;
              }
            }
          }
        }

        // usage 通常在最后一个 chunk（include_usage）
        final u = json['usage'] as Map<String, dynamic>?;
        if (u != null) {
          final details = u['prompt_tokens_details'] as Map<String, dynamic>?;
          usage = Usage(
            promptTokens: (u['prompt_tokens'] as num?)?.toInt() ?? 0,
            completionTokens: (u['completion_tokens'] as num?)?.toInt() ?? 0,
            totalTokens: (u['total_tokens'] as num?)?.toInt() ?? 0,
            cachedTokens: (details?['cached_tokens'] as num?)?.toInt() ?? 0,
          );
        }
      }
    }

    final toolCalls = (toolAcc.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => ToolCall(id: e.value.id, name: e.value.name, arguments: e.value.args))
        .toList();

    return ChatResult(
        text: text, reasoning: reasoningText, toolCalls: toolCalls, usage: usage);
  }

  /// 非流式调用：用于上下文压缩的摘要请求（纯文本进出，不带工具）
  Future<String> complete(List<ChatMessage> messages) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/chat/completions',
      data: {
        'model': _model,
        'messages': messages.map((m) => m.toJson()).toList(),
        'stream': false,
      },
    );
    final choices = resp.data?['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return '';
    final msg = (choices[0] as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    return msg?['content'] as String? ?? '';
  }
}

/// 流式累积 tool_call 分片的可变容器
class _ToolAcc {
  String id = '';
  String name = '';
  String args = '';
}
