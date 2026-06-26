import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connection_provider.dart';

/// 一台主机的实时监控指标（单次采样结果）
class Metrics {
  final double cpuPct; // CPU 使用率 0-1
  final double memPct; // 内存使用率 0-1
  final String memText; // "882M / 7.6G"
  final double diskPct; // 根分区使用率 0-1
  final String diskText; // "19G / 79G"
  final double load1; // 1 分钟负载
  final int cores; // 核数（算负载占比用）
  final double netRxBps; // 入站字节/秒
  final double netTxBps; // 出站字节/秒
  final bool loading;
  final String? error;

  const Metrics({
    this.cpuPct = 0,
    this.memPct = 0,
    this.memText = '-',
    this.diskPct = 0,
    this.diskText = '-',
    this.load1 = 0,
    this.cores = 1,
    this.netRxBps = 0,
    this.netTxBps = 0,
    this.loading = false,
    this.error,
  });
}

/// 采样间隔
const _interval = Duration(seconds: 4);

/// 监控 Notifier —— 定时 SSH 采样当前主机资源指标，按主机隔离。
/// 仅在面板可见且已连接时运行定时器（start/stop 由 UI 生命周期驱动），避免后台空跑。
class MonitorNotifier extends Notifier<Metrics> {
  Timer? _timer;
  bool _sampling = false;
  // 上次网络累计字节 + 时刻，用于算速率（两次采样差值）
  int? _lastRxBytes;
  int? _lastTxBytes;
  DateTime? _lastNetAt;
  String? _boundHostId; // 当前采样绑定的主机，切主机时重置网络基线

  @override
  Metrics build() {
    ref.onDispose(() => _timer?.cancel());
    return const Metrics();
  }

  /// 开始定时采样（面板可见时调用）。立即采一次，之后周期采。
  void start() {
    _timer?.cancel();
    _sample();
    _timer = Timer.periodic(_interval, (_) => _sample());
  }

  /// 停止采样（面板隐藏/断开时调用）
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sample() async {
    if (_sampling) return; // 上一次还没回来，跳过
    final conn = ref.read(connectionProvider);
    final hostId = conn.host?.id;
    if (hostId == null || !conn.isConnected) {
      state = const Metrics(error: '未连接主机');
      return;
    }
    // 切主机：重置网络基线，避免用别的主机的字节数算出错误速率
    if (hostId != _boundHostId) {
      _boundHostId = hostId;
      _lastRxBytes = null;
      _lastTxBytes = null;
      _lastNetAt = null;
      state = const Metrics(loading: true);
    }

    _sampling = true;
    try {
      final r = await conn.client!.exec(_probe);
      final m = _parse(r.stdout);
      if (m != null) state = m;
    } catch (e) {
      state = Metrics(error: e.toString());
    } finally {
      _sampling = false;
    }
  }

  /// 一条聚合探针命令：各段用标记分隔，便于解析。
  /// loadavg / 内存(KB) / 根分区 / cpu空闲% / 网络累计字节(排除lo)
  static const _probe = r'''
echo "===LOAD==="; cat /proc/loadavg; nproc;
echo "===MEM==="; cat /proc/meminfo | grep -E "^(MemTotal|MemAvailable):";
echo "===DISK==="; df -P / | tail -1;
echo "===CPU==="; top -bn1 | grep -i "^%Cpu" | head -1;
echo "===NET==="; cat /proc/net/dev | grep -vE "lo:|Inter-|face" ''';

  /// 解析探针输出。任何一段缺失则该指标退化为 0，不整体失败。
  Metrics? _parse(String out) {
    final sections = <String, List<String>>{};
    String? cur;
    for (final line in out.split('\n')) {
      final t = line.trim();
      if (t.startsWith('===') && t.endsWith('===')) {
        cur = t.replaceAll('=', '');
        sections[cur] = [];
      } else if (cur != null && t.isNotEmpty) {
        sections[cur]!.add(t);
      }
    }

    // 负载 + 核数
    double load1 = 0;
    int cores = 1;
    final load = sections['LOAD'];
    if (load != null && load.isNotEmpty) {
      final parts = load[0].split(RegExp(r'\s+'));
      if (parts.isNotEmpty) load1 = double.tryParse(parts[0]) ?? 0;
      if (load.length > 1) cores = int.tryParse(load[1]) ?? 1;
    }

    // 内存：MemTotal/MemAvailable（KB）
    double memPct = 0;
    String memText = '-';
    final mem = sections['MEM'];
    if (mem != null) {
      int total = 0, avail = 0;
      for (final l in mem) {
        final v = int.tryParse(l.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (l.startsWith('MemTotal')) total = v;
        if (l.startsWith('MemAvailable')) avail = v;
      }
      if (total > 0) {
        memPct = (total - avail) / total;
        memText = '${_humanKB(total - avail)} / ${_humanKB(total)}';
      }
    }

    // 磁盘：df 根分区行 "Filesystem 1024-blocks Used Available Capacity Mounted"
    double diskPct = 0;
    String diskText = '-';
    final disk = sections['DISK'];
    if (disk != null && disk.isNotEmpty) {
      final p = disk[0].split(RegExp(r'\s+'));
      if (p.length >= 5) {
        final used = int.tryParse(p[2]) ?? 0; // KB
        final total = (int.tryParse(p[1]) ?? 0) + 0;
        final usedPlusAvail = used + (int.tryParse(p[3]) ?? 0);
        diskPct = (double.tryParse(p[4].replaceAll('%', '')) ?? 0) / 100;
        diskText = '${_humanKB(used)} / ${_humanKB(total > 0 ? total : usedPlusAvail)}';
      }
    }

    // CPU：top "%Cpu(s):  x.x us, ... y.y id, ..." 取 idle，使用率=100-idle
    double cpuPct = 0;
    final cpu = sections['CPU'];
    if (cpu != null && cpu.isNotEmpty) {
      final idle = RegExp(r'([\d.]+)\s*id').firstMatch(cpu[0]);
      if (idle != null) {
        final id = double.tryParse(idle.group(1)!) ?? 100;
        cpuPct = ((100 - id) / 100).clamp(0, 1);
      }
    }

    // 网络：累加所有非 lo 网卡的 rx/tx 字节，与上次比算速率
    double rxBps = 0, txBps = 0;
    final net = sections['NET'];
    if (net != null) {
      int rx = 0, tx = 0;
      for (final l in net) {
        // "eth0: rxBytes rxPackets ... txBytes ..." 冒号后第1列rx，第9列tx
        final afterColon = l.contains(':') ? l.split(':')[1] : l;
        final f = afterColon.trim().split(RegExp(r'\s+'));
        if (f.length >= 9) {
          rx += int.tryParse(f[0]) ?? 0;
          tx += int.tryParse(f[8]) ?? 0;
        }
      }
      final now = DateTime.now();
      if (_lastRxBytes != null && _lastNetAt != null) {
        final dt = now.difference(_lastNetAt!).inMilliseconds / 1000.0;
        if (dt > 0) {
          rxBps = ((rx - _lastRxBytes!) / dt).clamp(0, double.infinity);
          txBps = ((tx - _lastTxBytes!) / dt).clamp(0, double.infinity);
        }
      }
      _lastRxBytes = rx;
      _lastTxBytes = tx;
      _lastNetAt = now;
    }

    return Metrics(
      cpuPct: cpuPct,
      memPct: memPct,
      memText: memText,
      diskPct: diskPct,
      diskText: diskText,
      load1: load1,
      cores: cores,
      netRxBps: rxBps,
      netTxBps: txBps,
    );
  }

  /// KB 转人类可读（MemTotal 等单位是 KB）
  static String _humanKB(int kb) {
    if (kb >= 1024 * 1024) return '${(kb / 1024 / 1024).toStringAsFixed(1)}G';
    if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(0)}M';
    return '${kb}K';
  }
}

/// 字节/秒 转人类可读速率
String humanBps(double bps) {
  if (bps >= 1024 * 1024) return '${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s';
  if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
  return '${bps.toStringAsFixed(0)} B/s';
}

final monitorProvider =
    NotifierProvider<MonitorNotifier, Metrics>(MonitorNotifier.new);
