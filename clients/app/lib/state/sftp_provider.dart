import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ssh.dart';
import 'connection_provider.dart';

/// SFTP 浏览状态：当前路径 + 文件列表 + 加载/错误态
class SftpState {
  final String path;
  final List<RemoteFile> files;
  final bool loading;
  final String? error;

  const SftpState({
    this.path = '/',
    this.files = const [],
    this.loading = false,
    this.error,
  });

  SftpState copyWith({
    String? path,
    List<RemoteFile>? files,
    bool? loading,
    String? error,
  }) =>
      SftpState(
        path: path ?? this.path,
        files: files ?? this.files,
        loading: loading ?? this.loading,
        error: error,
      );
}

/// SFTP 浏览 Notifier —— 按主机分桶隔离（每台主机各自的浏览路径/列表）。
/// 当前展示哪台由 connectionProvider 的 host 决定，切主机自动切快照。
class SftpNotifier extends Notifier<SftpState> {
  final Map<String, SftpState> _byHost = {};
  String? _currentId;

  @override
  SftpState build() {
    ref.listen(connectionProvider.select((s) => s.host?.id), (prev, next) {
      _currentId = next;
      state = next == null
          ? const SftpState()
          : (_byHost[next] ?? const SftpState());
    });
    _currentId = ref.read(connectionProvider).host?.id;
    return _currentId == null
        ? const SftpState()
        : (_byHost[_currentId!] ?? const SftpState());
  }

  /// 列出指定目录（默认当前路径）。未连接则报错。
  Future<void> load([String? path]) async {
    final conn = ref.read(connectionProvider);
    final hostId = conn.host?.id;
    if (hostId == null || !conn.isConnected) {
      _set(hostId, const SftpState(error: '未连接主机'));
      return;
    }
    final prev = _byHost[hostId] ?? const SftpState();
    final target = path ?? prev.path;
    _set(hostId, prev.copyWith(loading: true, error: null, path: target));
    try {
      final files = await conn.client!.listDir(target);
      _set(hostId, SftpState(path: target, files: files, loading: false));
    } catch (e) {
      _set(hostId, SftpState(path: target, loading: false, error: e.toString()));
    }
  }

  /// 进入子目录
  Future<void> enter(RemoteFile dir) async {
    if (!dir.isDir) return;
    await load(dir.path);
  }

  /// 返回上级目录
  Future<void> goUp() async {
    final p = state.path;
    if (p == '/' || p.isEmpty) return;
    final trimmed = p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    final idx = trimmed.lastIndexOf('/');
    final parent = idx <= 0 ? '/' : trimmed.substring(0, idx);
    await load(parent);
  }

  /// 写入某主机的 SFTP 状态；若正是当前展示主机则同步刷新对外 state
  void _set(String? hostId, SftpState s) {
    if (hostId == null) {
      state = s;
      return;
    }
    _byHost[hostId] = s;
    if (hostId == _currentId) state = s;
  }
}

final sftpProvider =
    NotifierProvider<SftpNotifier, SftpState>(SftpNotifier.new);
