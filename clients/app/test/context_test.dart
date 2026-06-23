import 'package:flutter_test/flutter_test.dart';
import 'package:lowenssh/core/context.dart';
import 'package:lowenssh/core/config.dart';
import 'package:lowenssh/core/glm.dart';

void main() {
  // 用一个不真正发请求的占位 client（这些测试只覆盖纯逻辑：截断 + token 估算）
  final cm = ContextManager(
    GlmClient(const LlmConfig(baseURL: 'http://x', apiKey: 'k', model: 'm')),
  );

  group('ContextManager Layer 0 截断', () {
    test('短工具结果不截断', () {
      final msgs = [ChatMessage.tool('c1', '短结果')];
      final out = cm.truncateToolResponses(msgs);
      expect(out[0].content, '短结果');
    });

    test('近区长结果按大阈值截断并含哨兵', () {
      final huge = 'x' * 9000; // > toolResultMaxChars(8000)
      final out = cm.truncateToolResponses([ChatMessage.tool('c1', huge)]);
      expect(out[0].content!.length, lessThan(9000));
      expect(out[0].content, contains('完整结果见历史记录'));
    });

    test('截断幂等：二次截断不再变化', () {
      final huge = 'y' * 9000;
      final once = cm.truncateToolResponses([ChatMessage.tool('c1', huge)]);
      final twice = cm.truncateToolResponses(once);
      expect(twice[0].content, once[0].content);
    });

    test('非 tool 消息原样保留', () {
      final msgs = [ChatMessage.user('hi'), ChatMessage.system('sys')];
      final out = cm.truncateToolResponses(msgs);
      expect(out[0].content, 'hi');
      expect(out[1].content, 'sys');
    });
  });

  group('ContextManager token 估算', () {
    test('按 2.5 字符/token 粗估', () {
      // 10 个字符 → floor(10/2.5)=4
      final msgs = [ChatMessage.user('0123456789')];
      expect(cm.estimateTokens(msgs), 4);
    });

    test('assistant 的 tool_calls arguments 计入字符数', () {
      final msgs = [
        ChatMessage.assistant('ab', toolCalls: [
          const ToolCall(id: 'i', name: 'n', arguments: '12345'),
        ]),
      ];
      // 'ab'(2) + '12345'(5) = 7 → floor(7/2.5)=2
      expect(cm.estimateTokens(msgs), 2);
    });
  });
}
