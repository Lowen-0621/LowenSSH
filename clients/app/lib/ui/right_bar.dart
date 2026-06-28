import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/i18n.dart';
import '../state/guard_provider.dart';
import '../state/connection_provider.dart';
import '../state/monitor_provider.dart';
import '../state/sftp_provider.dart';
import '../state/settings_provider.dart';

/// 右栏 —— 安全 / 文件 / 监控 三 Tab（宽 300px）
/// 对应设计稿 .rightbar。安全面板是差异化核心，重点还原。
class RightBar extends ConsumerStatefulWidget {
  const RightBar({super.key});

  @override
  ConsumerState<RightBar> createState() => _RightBarState();
}

class _RightBarState extends ConsumerState<RightBar> {
  // 当前 tab：sec / files / mon
  String _tab = 'sec';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.mantle,
      child: Column(
        children: [
          _tabs(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: switch (_tab) {
                'files' => const _FilesPanel(),
                'mon' => const _MonitorPanel(),
                _ => const _SecurityPanel(),
              },
            ),
          ),
        ],
      ),
    );
  }

  // 顶部三 tab，底部蓝条标记 active
  Widget _tabs() {
    final l = ref.watch(l10nProvider);
    Widget tab(String id, IconData icon, String label) {
      final active = _tab == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = id),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? AppColors.blue : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 14,
                    color: active ? AppColors.text : AppColors.subtext),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: active ? AppColors.text : AppColors.subtext)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surface0)),
      ),
      child: Row(
        children: [
          tab('sec', Icons.shield_outlined, l.t('right.tabSec')),
          tab('files', Icons.folder_outlined, l.t('right.tabFiles')),
          tab('mon', Icons.monitor_heart_outlined, l.t('right.tabMon')),
        ],
      ),
    );
  }
}

// ============ 安全策略面板（差异化核心）============

class _SecurityPanel extends ConsumerWidget {
  const _SecurityPanel();

  // 门禁规则展示（规则本身固定，来自 core/guard.dart 的 deny/ask 名单）。
  // 命中次数那列改为按三态聚合显示（guard 未按单条规则细分计数）。
  static const _rules = [
    ('deny', 'rm -rf · dd · mkfs · shutdown · fork炸弹'),
    ('ask', 'rm · kill · systemctl stop/restart'),
    ('ask', '> 重定向 · chmod · chown · apt install'),
    ('allow', 'ls · cat · df · du · tail（只读）'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(guardProvider);
    final l = ref.watch(l10nProvider);
    // 每条规则末尾显示对应三态的累计命中次数
    String hitsFor(String level) => switch (level) {
          'deny' => l.t('right.hits', {'n': '${stats.denyCount}'}),
          'ask' => l.t('right.hits', {'n': '${stats.askCount}'}),
          _ => l.t('right.hits', {'n': '${stats.allowCount}'}),
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 统计三卡：已阻止/待确认/已放行（真实数据）
        Row(
          children: [
            _stat('${stats.denyCount}', l.t('state.denied'), AppColors.red),
            const SizedBox(width: 8),
            _stat('${stats.askCount}', l.t('state.ask'), AppColors.yellow),
            const SizedBox(width: 8),
            _stat('${stats.allowCount}', l.t('state.allowed'), AppColors.green),
          ],
        ),
        const SizedBox(height: 14),
        _panelTitle(l.t('right.rulesTitle')),
        for (final r in _rules) _ruleRow(r.$1, r.$2, hitsFor(r.$1)),
        const SizedBox(height: 14),
        _panelTitle(l.t('right.blockHistory')),
        if (stats.blocked.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(l.t('right.noBlock'),
                style: TextStyle(fontSize: 11, color: AppColors.overlay)),
          )
        else
          for (final b in stats.blocked)
            _logItem(b.command,
                '${_fmtTime(b.time)} · ${b.level.toUpperCase()}', l),
      ],
    );
  }

  // 时间格式 HH:mm:ss
  static String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  // 统计卡
  Widget _stat(String num, String label, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.surface0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(num,
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: color)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 10, color: AppColors.overlay)),
            ],
          ),
        ),
      );

  // 规则行：tag + 模式 + 命中次数
  Widget _ruleRow(String level, String pattern, String hits) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            _tag(level),
            const SizedBox(width: 8),
            Expanded(
              child: Text(pattern,
                  style: TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11,
                      color: AppColors.subtext)),
            ),
            const SizedBox(width: 6),
            Text(hits,
                style:
                    TextStyle(fontSize: 10, color: AppColors.overlay)),
          ],
        ),
      );

  // 三态 tag（deny红 / ask黄 / allow绿，带半透明背景）
  Widget _tag(String level) {
    final (Color c, String text) = switch (level) {
      'deny' => (AppColors.red, 'DENY'),
      'ask' => (AppColors.yellow, 'ASK'),
      _ => (AppColors.green, 'ALLOW'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
              color: c)),
    );
  }

  // 拦截历史项（左边红条 + 命令 + 时间/可临时放行）
  Widget _logItem(String cmd, String meta, L10n l) => Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.all(Radius.circular(6)),
          border: Border(left: BorderSide(color: AppColors.red, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(cmd,
                style: TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 11,
                    color: AppColors.peach)),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(meta,
                    style: TextStyle(
                        fontSize: 10, color: AppColors.overlay)),
                Text(l.t('right.tempAllow'),
                    style: TextStyle(fontSize: 10, color: AppColors.blue)),
              ],
            ),
          ],
        ),
      );
}

// ============ 文件面板（轻量 SFTP，真实数据）============

class _FilesPanel extends ConsumerStatefulWidget {
  const _FilesPanel();

  @override
  ConsumerState<_FilesPanel> createState() => _FilesPanelState();
}

class _FilesPanelState extends ConsumerState<_FilesPanel> {
  @override
  void initState() {
    super.initState();
    // 首次进入文件 tab 时，若已连接则加载当前目录
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final conn = ref.read(connectionProvider);
      final sftp = ref.read(sftpProvider);
      if (conn.isConnected && sftp.files.isEmpty && !sftp.loading) {
        ref.read(sftpProvider.notifier).load('/');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);
    final sftp = ref.watch(sftpProvider);
    final l = ref.watch(l10nProvider);

    // 切到已连接的新主机时，若其 SFTP 还没加载过则自动列根目录
    ref.listen(connectionProvider.select((s) => s.host?.id), (prev, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = ref.read(connectionProvider);
        final s = ref.read(sftpProvider);
        if (c.isConnected && s.files.isEmpty && !s.loading) {
          ref.read(sftpProvider.notifier).load('/');
        }
      });
    });

    if (!conn.isConnected) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(l.t('right.filesEmpty'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.overlay)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 路径条 + 刷新
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.base,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(sftp.path,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 11,
                        color: AppColors.subtext)),
              ),
              InkWell(
                onTap: () => ref.read(sftpProvider.notifier).load(),
                child: Icon(Icons.refresh,
                    size: 13, color: AppColors.blue),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (sftp.loading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.blue),
              ),
            ),
          )
        else if (sftp.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l.t('right.loadFail', {'err': '${sftp.error}'}),
                style: TextStyle(fontSize: 11, color: AppColors.red)),
          )
        else ...[
          // 顶部 .. 返回上级（非根目录时）
          if (sftp.path != '/' && sftp.path.isNotEmpty)
            InkWell(
              onTap: () => ref.read(sftpProvider.notifier).goUp(),
              child: _fileRow(Icons.folder_outlined, '..', null, true),
            ),
          for (final f in sftp.files)
            InkWell(
              onTap: f.isDir
                  ? () => ref.read(sftpProvider.notifier).enter(f)
                  : null,
              child: _fileRow(
                f.isDir
                    ? Icons.folder_outlined
                    : Icons.description_outlined,
                f.name,
                f.isDir ? f.perms : _fmtSize(f.size),
                f.isDir,
              ),
            ),
          if (sftp.files.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l.t('right.emptyDir'),
                  style: TextStyle(fontSize: 11, color: AppColors.overlay)),
            ),
        ],
      ],
    );
  }

  // 文件大小友好显示
  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}M';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)}G';
  }

  Widget _fileRow(IconData icon, String name, String? meta, bool isDir) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          children: [
            Icon(icon,
                size: 15, color: isDir ? AppColors.blue : AppColors.subtext),
            const SizedBox(width: 9),
            Expanded(
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: isDir ? AppColors.blue : AppColors.text)),
            ),
            if (meta != null)
              Text(meta,
                  style: TextStyle(
                      fontSize: 10, color: AppColors.overlay)),
          ],
        ),
      );
}

// ============ 监控面板 ============

class _MonitorPanel extends ConsumerStatefulWidget {
  const _MonitorPanel();

  @override
  ConsumerState<_MonitorPanel> createState() => _MonitorPanelState();
}

class _MonitorPanelState extends ConsumerState<_MonitorPanel> {
  @override
  void initState() {
    super.initState();
    // 面板可见即开始采样；销毁（切走其它 tab）即停止，避免后台空跑
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(monitorProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    ref.read(monitorProvider.notifier).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);
    final m = ref.watch(monitorProvider);
    final l = ref.watch(l10nProvider);

    if (!conn.isConnected) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(l.t('right.monEmpty'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.overlay)),
      );
    }

    // 负载占比：load1 / 核数（>1 视为满载），用于进度条
    final loadPct = m.cores > 0 ? (m.load1 / m.cores).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle(l.t('right.resUsage')),
        _metric('CPU', m.cpuPct, '${(m.cpuPct * 100).toStringAsFixed(0)}%',
            m.cpuPct > 0.9),
        _metric(l.t('right.mem'), m.memPct, m.memText, m.memPct > 0.9),
        _metric(l.t('right.disk'), m.diskPct,
            '${(m.diskPct * 100).toStringAsFixed(0)}%', m.diskPct > 0.9),
        _metric(l.t('right.load'), loadPct, m.load1.toStringAsFixed(2),
            loadPct > 0.9),
        const SizedBox(height: 6),
        _panelTitle(l.t('right.network')),
        _netRow(l.t('right.netIn'), humanBps(m.netRxBps)),
        _netRow(l.t('right.netOut'), humanBps(m.netTxBps)),
        if (m.error != null) ...[
          const SizedBox(height: 8),
          Text(l.t('right.sampleFail', {'err': '${m.error}'}),
              style: TextStyle(fontSize: 10, color: AppColors.red)),
        ],
      ],
    );
  }

  // 资源条：标签 + 进度条(warn红) + 数值
  Widget _metric(String label, double pct, String val, bool warn) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          children: [
            SizedBox(
                width: 48,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.subtext))),
            const SizedBox(width: 9),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 7,
                  backgroundColor: AppColors.base,
                  valueColor: AlwaysStoppedAnimation(
                      warn ? AppColors.red : AppColors.blue),
                ),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
                width: 64,
                child: Text(val,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5, color: AppColors.text))),
          ],
        ),
      );

  Widget _netRow(String label, String val) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 11,
                    color: AppColors.subtext)),
            Text(val,
                style:
                    TextStyle(fontSize: 10, color: AppColors.overlay)),
          ],
        ),
      );
}

// 面板小标题（大写灰字）—— 顶层共用
Widget _panelTitle(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 10.5, letterSpacing: 1, color: AppColors.overlay)),
    );
