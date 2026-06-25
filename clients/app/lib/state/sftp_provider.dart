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

/// SFTP 浏览 Notifier —— 列目录、进入子目录、返回上级。
/// 依赖 connectionProvider 的活动 SshClient。
class SftpNotifier extends Notifier<SftpState> {
  @override
  SftpState build() => const SftpState();

  /// 列出指定目录（默认当前路径）。未连接则报错。
  Future<void> load([String? path]) async {
    final conn = ref.read(connectionProvider);
    if (!conn.isConnected) {
      state = const SftpState(error: '未连接主机');
      return;
    }
    final target = path ?? state.path;
    state = state.copyWith(loading: true, error: null, path: target);
    try {
      final files = await conn.client!.listDir(target);
      state = SftpState(path: target, files: files, loading: false);
    } catch (e) {
      state = SftpState(path: target, loading: false, error: e.toString());
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
}

final sftpProvider =
    NotifierProvider<SftpNotifier, SftpState>(SftpNotifier.new);
