import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config.dart';
import '../core/chat_store.dart';

/// 应用配置 Notifier —— 加载/增删主机/改 LLM，变更后刷新依赖此 provider 的 UI
class ConfigNotifier extends Notifier<AppConfig> {
  @override
  AppConfig build() => loadConfig();

  /// 新增主机（密码加密落库），返回新建主机
  Host addHostEntry({
    String? alias,
    required String host,
    int port = 22,
    String user = 'root',
    String? password,
    String? keyId,
  }) {
    final h = addHost(
        alias: alias,
        host: host,
        port: port,
        user: user,
        password: password,
        keyId: keyId);
    state = loadConfig(); // 刷新
    return h;
  }

  /// 删除主机（连同其对话存档一起清理）
  void deleteHost(String id) {
    removeHost(id);
    deleteChat(id); // 清理落盘的对话历史
    state = loadConfig();
  }

  /// 更新某供应商的配置（apiKey/model/baseURL）
  void updateProvider(String id,
      {String? apiKey, String? model, String? baseURL}) {
    final cfg = loadConfig();
    final providers = cfg.providers
        .map((p) => p.id == id
            ? p.copyWith(apiKey: apiKey, model: model, baseURL: baseURL)
            : p)
        .toList();
    saveConfig(cfg.copyWith(providers: providers));
    state = loadConfig();
  }

  /// 切换当前激活的供应商
  void setActiveProvider(String id) {
    final cfg = loadConfig();
    saveConfig(cfg.copyWith(activeProviderId: id));
    state = loadConfig();
  }

  /// 重新从盘加载（密钥库变更后，主机的 keyId 引用可能被清，需同步刷新）
  void reload() => state = loadConfig();
}

final configProvider =
    NotifierProvider<ConfigNotifier, AppConfig>(ConfigNotifier.new);

/// 主机列表 provider（派生）
final hostsProvider = Provider<List<Host>>((ref) {
  return ref.watch(configProvider).hosts;
});
