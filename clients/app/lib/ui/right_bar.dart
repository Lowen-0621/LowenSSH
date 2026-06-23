import 'package:flutter/material.dart';
import '../theme.dart';

/// 右栏 —— 安全 / 文件 / 监控 三 Tab（宽 300px）
/// 对应设计稿 .rightbar。安全面板是差异化核心，重点还原。
class RightBar extends StatefulWidget {
  const RightBar({super.key});

  @override
  State<RightBar> createState() => _RightBarState();
}

class _RightBarState extends State<RightBar> {
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
    Widget tab(String id, String icon, String label) {
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
                Text(icon, style: const TextStyle(fontSize: 11.5)),
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surface0)),
      ),
      child: Row(
        children: [
          tab('sec', '🛡️', '安全'),
          tab('files', '📁', '文件'),
          tab('mon', '📊', '监控'),
        ],
      ),
    );
  }
}

// ============ 安全策略面板（差异化核心）============

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel();

  // 门禁规则占位 model（Step 4 接 core/guard.dart 统计）
  static const _rules = [
    ('deny', 'rm -rf / · :(){:|:&};:', '2 次'),
    ('ask', 'rm · kill · systemctl stop', '1 次'),
    ('ask', '> 重定向 · chmod · chown', '0 次'),
    ('allow', 'ls · cat · df · du · tail（只读）', '14 次'),
  ];

  // 拦截历史占位
  static const _logs = [
    ('rm -rf /var --no-preserve-root', '14:32:08 · DENY'),
    ('dd if=/dev/zero of=/dev/sda', '14:30:51 · DENY'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 统计三卡：已拦截/待确认/已放行
        Row(
          children: [
            _stat('2', '已阻止', AppColors.red),
            const SizedBox(width: 8),
            _stat('1', '待确认', AppColors.yellow),
            const SizedBox(width: 8),
            _stat('14', '已放行', AppColors.green),
          ],
        ),
        const SizedBox(height: 14),
        _panelTitle('门禁规则（按严格度）'),
        for (final r in _rules) _ruleRow(r.$1, r.$2, r.$3),
        const SizedBox(height: 14),
        _panelTitle('阻止历史'),
        for (final l in _logs) _logItem(l.$1, l.$2),
      ],
    );
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
                  style: const TextStyle(
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
                  style: const TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11,
                      color: AppColors.subtext)),
            ),
            const SizedBox(width: 6),
            Text(hits,
                style:
                    const TextStyle(fontSize: 10, color: AppColors.overlay)),
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
  Widget _logItem(String cmd, String meta) => Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: const BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.all(Radius.circular(6)),
          border: Border(left: BorderSide(color: AppColors.red, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(cmd,
                style: const TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 11,
                    color: AppColors.peach)),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(meta,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.overlay)),
                const Text('临时放行',
                    style: TextStyle(fontSize: 10, color: AppColors.blue)),
              ],
            ),
          ],
        ),
      );
}

// ============ 文件面板（轻量 SFTP）============

class _FilesPanel extends StatelessWidget {
  const _FilesPanel();

  static const _files = [
    ('📁', '..', null, true),
    ('📁', 'html', 'drwxr-xr-x', true),
    ('📁', 'logs', 'drwxr-xr-x', true),
    ('📄', 'nginx.conf', '1.2 KB', false),
    ('📄', 'index.html', '4.5 KB', false),
    ('📦', 'release.tar.gz', '48 MB', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 路径条 + 完整视图入口
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.base,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('/var/www',
                  style: TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11,
                      color: AppColors.subtext)),
              Text('⛶ 完整视图',
                  style: TextStyle(fontSize: 11, color: AppColors.blue)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final f in _files) _fileRow(f.$1, f.$2, f.$3, f.$4),
        // 拖拽上传区
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
                color: AppColors.surface1, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('⬆ 拖文件到此处上传到 /var/www',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.overlay)),
        ),
      ],
    );
  }

  Widget _fileRow(String icon, String name, String? perm, bool isDir) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          children: [
            SizedBox(
                width: 16,
                child: Text(icon, textAlign: TextAlign.center)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                  style: TextStyle(
                      fontSize: 12,
                      color: isDir ? AppColors.blue : AppColors.text)),
            ),
            if (perm != null)
              Text(perm,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.overlay)),
          ],
        ),
      );
}

// ============ 监控面板 ============

class _MonitorPanel extends StatelessWidget {
  const _MonitorPanel();

  // (标签, 百分比0-1, 显示值, 是否warn)
  static const _metrics = [
    ('CPU', 0.34, '34%', false),
    ('内存', 0.61, '61%', false),
    ('磁盘 /', 0.92, '92%', true),
    ('负载', 0.45, '1.8', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('资源占用'),
        for (final m in _metrics) _metric(m.$1, m.$2, m.$3, m.$4),
        const SizedBox(height: 6),
        _panelTitle('网络'),
        _netRow('↓ 入站', '2.4 MB/s'),
        _netRow('↑ 出站', '512 KB/s'),
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
                    style: const TextStyle(
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
                width: 38,
                child: Text(val,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.text))),
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
                style: const TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 11,
                    color: AppColors.subtext)),
            Text(val,
                style:
                    const TextStyle(fontSize: 10, color: AppColors.overlay)),
          ],
        ),
      );
}

// 面板小标题（大写灰字）—— 顶层共用
Widget _panelTitle(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              fontSize: 10.5, letterSpacing: 1, color: AppColors.overlay)),
    );
