import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config.dart';
import '../core/crypto.dart';
import '../core/ssh.dart';

/// 连接阶段
enum ConnPhase { idle, connecting, connected, error }

/// 连接状态：阶段 + 当前主机 + 错误信息 + 活动 SshClient
class ConnState {
  final ConnPhase phase;
  final Host? host;
  final String? error;
  final SshClient? client;

  const ConnState({
    this.phase = ConnPhase.idle,
    this.host,
    this.error,
    this.client,
  });

  bool get isConnected => phase == ConnPhase.connected && client != null;

  ConnState copyWith({
    ConnPhase? phase,
    Host? host,
    String? error,
    SshClient? client,
  }) =>
      ConnState(
        phase: phase ?? this.phase,
        host: host ?? this.host,
        error: error,
        client: client ?? this.client,
      );
}

/// 连接管理 Notifier —— 连接/断开指定主机
class ConnectionNotifier extends Notifier<ConnState> {
  @override
  ConnState build() => const ConnState();

  /// 连接到指定主机（密码从 passwordEnc 解密）
  Future<void> connect(Host host) async {
    // 先断开旧连接
    state.client?.close();
    state = ConnState(phase: ConnPhase.connecting, host: host);

    try {
      final client = SshClient();
      final password = decrypt(host.passwordEnc) ?? '';
      await client.connect(host.host, host.port, host.user, password);
      state = ConnState(
        phase: ConnPhase.connected,
        host: host,
        client: client,
      );
    } catch (e) {
      state = ConnState(
        phase: ConnPhase.error,
        host: host,
        error: e.toString(),
      );
    }
  }

  /// 主动断开
  void disconnect() {
    state.client?.close();
    state = const ConnState();
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ConnState>(ConnectionNotifier.new);
