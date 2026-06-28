import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config.dart';
import '../core/crypto.dart';
import '../core/ssh.dart';

/// 连接阶段
enum ConnPhase { idle, connecting, connected, error }

/// 连接状态：阶段 + 当前主机 + 错误信息 + 活动 SshClient
/// 对外仍暴露「当前展示主机」的连接快照，UI 用法不变（conn.client/.isConnected/.host）。
/// connectedIds：池中所有已连接主机的 id（多连接并存，左栏据此给每台标绿点）。
class ConnState {
  final ConnPhase phase;
  final Host? host;
  final String? error;
  final SshClient? client;
  final Set<String> connectedIds;

  const ConnState({
    this.phase = ConnPhase.idle,
    this.host,
    this.error,
    this.client,
    this.connectedIds = const {},
  });

  bool get isConnected =>
      phase == ConnPhase.connected && client?.isConnected() == true;

  ConnState copyWith({
    ConnPhase? phase,
    Host? host,
    String? error,
    SshClient? client,
    Set<String>? connectedIds,
  }) =>
      ConnState(
        phase: phase ?? this.phase,
        host: host ?? this.host,
        error: error,
        client: client ?? this.client,
        connectedIds: connectedIds ?? this.connectedIds,
      );
}

/// 连接池里的一台主机连接条目
class _ConnEntry {
  final Host host;
  ConnPhase phase;
  String? error;
  SshClient? client;
  DateTime lastUsed; // LRU：最近一次被选为当前主机的时刻

  _ConnEntry({
    required this.host,
    this.phase = ConnPhase.connecting,
  }) : lastUsed = DateTime.now();
}

/// 同时最多保活的连接数（LRU 上限）
const int kMaxLiveConns = 3;

/// 连接管理 Notifier —— 多连接池 + LRU。
/// 每台主机各自保活一条 SSH 连接，切主机不再断开旧连接（终端/SFTP 得以隔离保活）。
/// 对外 state 始终是「当前展示主机」的 ConnState。
class ConnectionNotifier extends Notifier<ConnState> {
  final Map<String, _ConnEntry> _pool = {};
  String? _currentId; // 当前展示主机 id

  /// 判断某主机的 AI 任务是否在跑（LRU 踢人时跳过它）。
  /// 由 agentProvider 注入回调，避免反向依赖。
  bool Function(String hostId)? isHostBusy;

  @override
  ConnState build() => const ConnState();

  /// 池里所有已连接主机的 id（供 UI 给每台标绿点）
  Set<String> get connectedIds => _pool.entries
      .where((e) => _isEntryConnected(e.value))
      .map((e) => e.key)
      .toSet();

  bool _isEntryConnected(_ConnEntry entry) =>
      entry.phase == ConnPhase.connected && entry.client?.isConnected() == true;

  String _closedMessage(Object? error) {
    final text = error?.toString().trim() ?? '';
    return text.isEmpty ? 'SSH 连接已断开' : 'SSH 连接已断开: $text';
  }

  void _markEntryDisconnected(_ConnEntry entry, Object? error) {
    final client = entry.client;
    entry
      ..client = null
      ..phase = ConnPhase.error
      ..error = _closedMessage(error);
    client?.close();
  }

  /// 把某条目投影成对外 state，并带上整池的 connectedIds
  void _publish(_ConnEntry entry) {
    if (entry.phase == ConnPhase.connected &&
        entry.client?.isConnected() != true) {
      _markEntryDisconnected(entry, null);
    }
    state = ConnState(
      phase: entry.phase,
      host: entry.host,
      error: entry.error,
      client: entry.client,
      connectedIds: connectedIds,
    );
  }

  /// 连接到指定主机：
  /// - 已在池中且已连 → 直接切为当前（不重连）
  /// - 否则新建连接，必要时按 LRU 踢掉最久未用的一台
  Future<void> connect(Host host) async {
    final existing = _pool[host.id];
    if (existing != null && _isEntryConnected(existing)) {
      _select(host.id);
      return;
    }
    if (existing != null) {
      _pool.remove(host.id);
      existing.client?.close();
    }

    // 新连接前先腾位置（不含正在连/将要连的这台）
    _evictIfNeeded(excludeId: host.id);

    final entry = _ConnEntry(host: host, phase: ConnPhase.connecting);
    _pool[host.id] = entry;
    _currentId = host.id;
    _publish(entry); // connecting

    try {
      late final SshClient client;
      client = SshClient(
        onClosed: (error, stackTrace) =>
            _handleClientClosed(host.id, client, error),
      );
      entry.client = client;
      // 优先密钥认证：主机指定了 keyId 且密钥仍存在则取私钥材料，否则回退密码
      String password = '';
      String? pem;
      String? passphrase;
      if (host.keyId != null) {
        final mat = getKeyMaterial(host.keyId!);
        if (mat != null) {
          pem = mat.pem;
          passphrase = mat.passphrase;
        }
      }
      // 没有可用私钥时才解密密码（密钥认证失败也保留密码兜底）
      password = decrypt(host.passwordEnc) ?? '';
      await client.connect(host.host, host.port, host.user, password,
          privateKeyPem: pem, passphrase: passphrase);
      entry
        ..client = client
        ..phase = ConnPhase.connected
        ..error = null
        ..lastUsed = DateTime.now();
    } catch (e) {
      entry.client?.close();
      entry
        ..client = null
        ..phase = ConnPhase.error
        ..error = e.toString();
    }
    // 连接期间用户可能已切到别的主机，只在仍停留此主机时刷新对外 state
    if (_currentId == host.id && identical(_pool[host.id], entry)) {
      _publish(entry);
    }
  }

  void _handleClientClosed(String hostId, SshClient client, Object? error) {
    final entry = _pool[hostId];
    if (entry == null || !identical(entry.client, client)) return;
    entry
      ..client = null
      ..phase = ConnPhase.error
      ..error = _closedMessage(error);
    if (_currentId == hostId) {
      _publish(entry);
    } else {
      state = ConnState(
        phase: state.phase,
        host: state.host,
        error: state.error,
        client: state.client,
        connectedIds: connectedIds,
      );
    }
  }

  /// 外层操作（终端/SFTP/监控）发现 transport 已关闭时，主动同步连接池状态。
  void markConnectionLost(String hostId, Object? error) {
    final entry = _pool[hostId];
    if (entry == null) return;
    _markEntryDisconnected(entry, error);
    if (_currentId == hostId) {
      _publish(entry);
    } else {
      state = ConnState(
        phase: state.phase,
        host: state.host,
        error: state.error,
        client: state.client,
        connectedIds: connectedIds,
      );
    }
  }

  /// 切换当前展示主机（点击左栏已连接的主机时）
  void _select(String hostId) {
    final entry = _pool[hostId];
    if (entry == null) return;
    _currentId = hostId;
    entry.lastUsed = DateTime.now();
    _publish(entry);
  }

  /// 公开的切换入口：已在池中就切过去并返回 true；否则返回 false（调用方去 connect）
  bool switchTo(String hostId) {
    if (_pool.containsKey(hostId)) {
      _select(hostId);
      return true;
    }
    return false;
  }

  /// LRU 腾位：池满时踢掉最久未用、且 AI 任务不在跑、且非当前主机的一台
  void _evictIfNeeded({String? excludeId}) {
    while (_pool.length >= kMaxLiveConns) {
      final candidates = _pool.entries
          .where((e) =>
              e.key != excludeId &&
              e.key != _currentId &&
              !(isHostBusy?.call(e.key) ?? false))
          .toList()
        ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
      if (candidates.isEmpty) break; // 没有可踢的（都在忙或就剩当前），放弃腾位
      final victim = candidates.first;
      _pool.remove(victim.key);
      victim.value.client?.close();
    }
  }

  /// 主动断开当前主机，从池移除，并切到池中另一台（若有）
  void disconnect() {
    final id = _currentId;
    if (id == null) return;
    final entry = _pool.remove(id);
    entry?.client?.close();
    // 切到剩下里最近用过的一台，没有则回到空态
    if (_pool.isEmpty) {
      _currentId = null;
      state = const ConnState();
    } else {
      final next = _pool.entries.reduce(
          (a, b) => a.value.lastUsed.isAfter(b.value.lastUsed) ? a : b);
      _select(next.key);
    }
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ConnState>(ConnectionNotifier.new);
