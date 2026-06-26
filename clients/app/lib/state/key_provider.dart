import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config.dart';
import 'config_provider.dart';

/// 密钥库 Notifier —— 增删 SSH 私钥，落盘持久化。
/// 复用 config.json（与 hosts 同文件），变更后刷新 configProvider 让主机表单也能取到最新密钥。
class KeyNotifier extends Notifier<List<SshKey>> {
  @override
  List<SshKey> build() => loadConfig().keys;

  /// 新增密钥（私钥/passphrase 加密落盘）
  SshKey add({
    required String name,
    required String privateKeyPem,
    String? passphrase,
  }) {
    final k = addKey(
        name: name, privateKeyPem: privateKeyPem, passphrase: passphrase);
    _refresh();
    return k;
  }

  /// 删除密钥（引用主机自动解除绑定）
  void remove(String id) {
    removeKey(id);
    _refresh();
  }

  // 刷新自身 + configProvider（主机列表的 keyId 引用可能被清）
  void _refresh() {
    state = loadConfig().keys;
    ref.read(configProvider.notifier).reload();
  }
}

final keyProvider =
    NotifierProvider<KeyNotifier, List<SshKey>>(KeyNotifier.new);
