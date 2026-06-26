import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/port_forward.dart';
import 'connection_provider.dart';

/// 一条隧道的 UI 状态（含运行句柄）
class ForwardEntry {
  final String id;
  final int localPort;
  final String remoteHost;
  final int remotePort;
  final String hostId; //   绑定的主机（隧道依附其 SSH 连接）
  final bool running;
  final String? error;
  final ForwardTunnel? tunnel; // 运行句柄，停止时关闭

  const ForwardEntry({
    required this.id,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    required this.hostId,
    this.running = false,
    this.error,
    this.tunnel,
  });

  ForwardEntry copyWith({
    bool? running,
    String? error,
    ForwardTunnel? tunnel,
    bool clearError = false,
    bool clearTunnel = false,
  }) =>
      ForwardEntry(
        id: id,
        localPort: localPort,
        remoteHost: remoteHost,
        remotePort: remotePort,
        hostId: hostId,
        running: running ?? this.running,
        error: clearError ? null : (error ?? this.error),
        tunnel: clearTunnel ? null : (tunnel ?? this.tunnel),
      );
}

/// 端口转发 Notifier —— 管理隧道列表，依附当前 SSH 连接启停。
/// 隧道不落盘（依附连接，重启即失效），符合「连接级资源」语义。
class ForwardNotifier extends Notifier<List<ForwardEntry>> {
  int _seq = 0;

  @override
  List<ForwardEntry> build() => [];

  /// 添加并立即启动一条隧道。绑定当前已连接主机；未连接则记错误不启动。
  Future<void> add({
    required int localPort,
    required String remoteHost,
    required int remotePort,
  }) async {
    final conn = ref.read(connectionProvider);
    final id = 'fwd_${_seq++}';
    final entry = ForwardEntry(
      id: id,
      localPort: localPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
      hostId: conn.host?.id ?? '-',
    );
    state = [...state, entry];

    if (!conn.isConnected || conn.client == null) {
      _update(id, (e) => e.copyWith(error: '未连接主机，无法启动'));
      return;
    }
    await _start(id);
  }

  /// 启动指定隧道
  Future<void> _start(String id) async {
    final entry = state.where((e) => e.id == id).firstOrNull;
    if (entry == null) return;
    final conn = ref.read(connectionProvider);
    if (!conn.isConnected || conn.client == null) {
      _update(id, (e) => e.copyWith(error: '未连接主机，无法启动'));
      return;
    }
    try {
      final tunnel = await ForwardTunnel.start(
        conn.client!,
        localPort: entry.localPort,
        remoteHost: entry.remoteHost,
        remotePort: entry.remotePort,
      );
      _update(
          id, (e) => e.copyWith(running: true, tunnel: tunnel, clearError: true));
    } catch (e) {
      // 常见：本地端口被占用（bind 失败）
      _update(id, (e) => e.copyWith(error: _friendly(e.toString())));
    }
  }

  /// 启停切换
  Future<void> toggle(String id) async {
    final entry = state.where((e) => e.id == id).firstOrNull;
    if (entry == null) return;
    if (entry.running) {
      await entry.tunnel?.stop();
      _update(id, (e) => e.copyWith(running: false, clearTunnel: true));
    } else {
      await _start(id);
    }
  }

  /// 删除隧道（先停再移除，防泄漏）
  Future<void> remove(String id) async {
    final entry = state.where((e) => e.id == id).firstOrNull;
    await entry?.tunnel?.stop();
    state = state.where((e) => e.id != id).toList();
  }

  // 局部更新某条
  void _update(String id, ForwardEntry Function(ForwardEntry) fn) {
    state = state.map((e) => e.id == id ? fn(e) : e).toList();
  }

  String _friendly(String err) {
    if (err.contains('errno = 48') || err.contains('Address already in use')) {
      return '本地端口已被占用';
    }
    return err;
  }
}

final forwardProvider =
    NotifierProvider<ForwardNotifier, List<ForwardEntry>>(ForwardNotifier.new);
