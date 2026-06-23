/// 上下文管理 —— 防止 agentic loop 多轮滚下来把模型上下文撑爆。
/// 移植自 TS 版 context.ts（再上游 Java ContextManager），只做两层（抄 Claude Code 思路）：
///
///  Layer 0 —— 大工具结果截断：单条工具结果超阈值截掉中段，留头尾 + 提示。
///             分级：最近 K 条用大阈值保细节，更早的用小阈值大力收紧 →
///             token 不随轮数线性膨胀，且按"距末尾距离"判定，跨轮稳定不破坏缓存前缀。
///
///  Layer 4 —— 历史压缩：整段估算 token 超阈值，把较早对话丢给 LLM 摘要成一条，
///             保留 system + 最近 K 条原文。成对约束：保留区不能以孤儿 tool 消息开头。
///             摘要连续失败到熔断阈值就停止压缩、裸跑兜底。
///
/// token 用字符数粗估：中英混合约 2.5 字符/token，不引 tokenizer。
library;

import 'glm.dart';

const double _charsPerToken = 2.5;
const String _truncateMarker = '完整结果见历史记录';

class ContextOptions {
  final int toolResultMaxChars; //    Layer 0 近区阈值
  final int oldToolResultMaxChars; // Layer 0 旧区阈值
  final int maxContextTokens; //      Layer 4 触发压缩阈值
  final int keepRecentMessages; //    Layer 4 保留最近条数
  final int circuitLimit; //          摘要连续失败熔断次数

  const ContextOptions({
    this.toolResultMaxChars = 8000,
    this.oldToolResultMaxChars = 800,
    this.maxContextTokens = 32000,
    this.keepRecentMessages = 6,
    this.circuitLimit = 3,
  });
}

const ContextOptions kDefaultContextOptions = ContextOptions();

const String _summaryPrompt = '''你是上下文压缩器。下面是一段 AI 运维助手与目标服务器之间的历史对话（含用户任务、助手发起的命令调用、命令执行结果）。
请把它压缩成简洁的中文摘要，必须保留以下信息，丢弃冗长的原始命令输出（只留结论）：
1. 用户的原始运维目标；
2. 已执行过的关键命令及其结果结论（例如磁盘占用多少、进程是否存活、配置是否正确）；
3. 已发现的问题或系统状态；
4. 被安全门禁拦截的危险操作（如果有）。
只输出摘要正文，不要解释你在做什么。''';

class ContextManager {
  final ContextOptions opts;
  final GlmClient llm;
  int _consecutiveFailures = 0;

  ContextManager(this.llm, [this.opts = kDefaultContextOptions]);

  // ===================== Layer 0：工具结果截断 =====================

  /// 对历史里所有工具结果做截断（幂等）。返回新列表，不改原列表。
  /// 分级：距末尾 keepRecentMessages 条内用大阈值，更早用小阈值。
  List<ChatMessage> truncateToolResponses(List<ChatMessage> messages) {
    final size = messages.length;
    final result = <ChatMessage>[];
    for (var i = 0; i < size; i++) {
      final msg = messages[i];
      if (msg.role != 'tool') {
        result.add(msg);
        continue;
      }
      final recent = size - i <= opts.keepRecentMessages;
      final limit = recent ? opts.toolResultMaxChars : opts.oldToolResultMaxChars;
      result.add(ChatMessage.tool(
        msg.toolCallId ?? '',
        _truncateText(msg.content ?? '', limit),
      ));
    }
    return result;
  }

  /// 截掉中段，保留头 60% / 尾 40%，中间塞提示。幂等：含哨兵跳过。
  String _truncateText(String text, int limit) {
    if (text.isEmpty || text.length <= limit) return text;
    if (text.contains(_truncateMarker)) return text;
    final headLen = (limit * 0.6).floor();
    final tailLen = limit - headLen;
    final cut = text.length - headLen - tailLen;
    final head = text.substring(0, headLen);
    final tail = text.substring(text.length - tailLen);
    return '$head\n...[已截断 $cut 字符，$_truncateMarker]...\n$tail';
  }

  // ===================== Layer 4：历史压缩 =====================

  /// 估算超阈值时压缩历史，否则原样返回。
  Future<List<ChatMessage>> compressIfNeeded(List<ChatMessage> messages) async {
    if (_consecutiveFailures >= opts.circuitLimit) return messages;
    if (estimateTokens(messages) <= opts.maxContextTokens) return messages;
    if (messages.length <= opts.keepRecentMessages + 1) return messages;

    var cutIndex = messages.length - opts.keepRecentMessages;
    // 保留区不能以孤儿 tool 消息开头（它的 tool_call 在 assistant 上，会被切走）
    while (cutIndex > 1 && messages[cutIndex].role == 'tool') {
      cutIndex--;
    }
    if (cutIndex <= 1) return messages;

    final summaryRegion = messages.sublist(1, cutIndex);
    final summary = await _summarize(summaryRegion);
    if (summary == null) {
      _consecutiveFailures++;
      return messages;
    }
    _consecutiveFailures = 0;

    return [
      messages[0], // system
      ChatMessage.user('以下是早先对话的摘要，供你继续任务时参考：\n$summary'),
      ...messages.sublist(cutIndex),
    ];
  }

  /// 调摘要 LLM 把一段历史压成结论文本；失败返回 null
  Future<String?> _summarize(List<ChatMessage> region) async {
    try {
      final rendered = _renderRegion(region);
      final text = await llm.complete([
        ChatMessage.system(_summaryPrompt),
        ChatMessage.user(rendered),
      ]);
      return text.trim().isNotEmpty ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// 把一段消息渲染成纯文本喂给摘要 LLM
  String _renderRegion(List<ChatMessage> region) {
    final lines = <String>[];
    for (final msg in region) {
      switch (msg.role) {
        case 'user':
          lines.add('用户: ${msg.content}');
        case 'assistant':
          if (msg.content != null && msg.content!.isNotEmpty) {
            lines.add('助手: ${msg.content}');
          }
          for (final call in msg.toolCalls ?? const <ToolCall>[]) {
            lines.add('助手调用工具 ${call.name}: ${call.arguments}');
          }
        case 'tool':
          lines.add('工具结果: ${msg.content}');
      }
    }
    return lines.join('\n');
  }

  // ===================== 工具方法 =====================

  /// 估算整段消息的 token 数（字符数粗估）
  int estimateTokens(List<ChatMessage> messages) {
    var chars = 0;
    for (final msg in messages) {
      if (msg.role == 'assistant') {
        chars += msg.content?.length ?? 0;
        for (final call in msg.toolCalls ?? const <ToolCall>[]) {
          chars += call.arguments.length;
        }
      } else {
        chars += msg.content?.length ?? 0;
      }
    }
    return (chars / _charsPerToken).floor();
  }
}
