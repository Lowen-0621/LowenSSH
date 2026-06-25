import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 主机搜索关键词 —— 顶栏搜索框写入，左栏主机列表据此过滤。
final hostSearchProvider = NotifierProvider<HostSearchNotifier, String>(
    HostSearchNotifier.new);

class HostSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String q) => state = q;
}
