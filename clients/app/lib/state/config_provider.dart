import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config.dart';

/// 应用配置 provider —— 加载 ~/.lowenssh/config.json（主机簿 + LLM 配置）
/// Step 4：先只读；增删主机后续接 saveConfig 再 invalidate。
final configProvider = Provider<AppConfig>((ref) {
  return loadConfig();
});

/// 主机列表 provider（派生自 configProvider）
final hostsProvider = Provider<List<Host>>((ref) {
  return ref.watch(configProvider).hosts;
});
