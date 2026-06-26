import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/snippet_store.dart';

/// 命令片段列表 Notifier —— 加载/增删，变更后落盘。
class SnippetNotifier extends Notifier<List<Snippet>> {
  @override
  List<Snippet> build() => loadSnippets();

  /// 新增片段
  void add(String label, String command) {
    final next = [...state, Snippet(label: label, command: command)];
    saveSnippets(next);
    state = next;
  }

  /// 删除指定下标的片段
  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    final next = [...state]..removeAt(index);
    saveSnippets(next);
    state = next;
  }
}

final snippetProvider =
    NotifierProvider<SnippetNotifier, List<Snippet>>(SnippetNotifier.new);

/// AI 输入框桥接 —— 外部（如命令片段）往输入框塞文本。
/// ai_pane 监听此 provider，非空时把文本写进 TextField 并清空本 provider。
/// 用「自增序号 + 文本」避免连续塞同一文本时 ai_pane 监听不到变化。
class ComposerRequest {
  final int seq;
  final String text;
  const ComposerRequest(this.seq, this.text);
}

class ComposerNotifier extends Notifier<ComposerRequest?> {
  int _seq = 0;

  @override
  ComposerRequest? build() => null;

  /// 请求把 text 填进 AI 输入框
  void fill(String text) {
    state = ComposerRequest(++_seq, text);
  }

  /// ai_pane 消费后清空
  void clear() {
    state = null;
  }
}

final composerProvider =
    NotifierProvider<ComposerNotifier, ComposerRequest?>(ComposerNotifier.new);
