import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../state/forward_provider.dart';
import '../state/connection_provider.dart';
import '../state/settings_provider.dart';

/// 端口转发对话框 —— 管理本地端口转发隧道（增删 + 启停）。
/// 隧道依附当前 SSH 连接（等价 ssh -L），绑定 127.0.0.1 仅本机可访问。
Future<void> showForwardDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.mantle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.surface0),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: _ForwardBody(),
        ),
      ),
    ),
  );
}

class _ForwardBody extends ConsumerWidget {
  const _ForwardBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(forwardProvider);
    final conn = ref.watch(connectionProvider);
    final l = ref.watch(l10nProvider);
    final hostName = conn.host?.alias?.isNotEmpty == true
        ? conn.host!.alias!
        : (conn.host?.host ?? '-');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题 + 添加
        Row(
          children: [
            const Icon(Icons.swap_horiz_outlined,
                size: 16, color: AppColors.text),
            const SizedBox(width: 8),
            Text(l.t('fwd.title'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
            const SizedBox(width: 8),
            Text(l.t('fwd.count', {'n': '${list.length}'}),
                style: const TextStyle(fontSize: 11, color: AppColors.overlay)),
            const Spacer(),
            TextButton.icon(
              onPressed: conn.isConnected
                  ? () => _showAddDialog(context, ref)
                  : null,
              icon: Icon(Icons.add,
                  size: 15,
                  color: conn.isConnected
                      ? AppColors.blue
                      : AppColors.overlay),
              label: Text(l.t('fwd.addTunnel'),
                  style: TextStyle(
                      fontSize: 12,
                      color: conn.isConnected
                          ? AppColors.blue
                          : AppColors.overlay)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 当前连接提示
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.base,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(conn.isConnected ? Icons.link : Icons.link_off,
                  size: 13,
                  color:
                      conn.isConnected ? AppColors.green : AppColors.overlay),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                    conn.isConnected
                        ? l.t('fwd.boundHint', {'host': hostName})
                        : l.t('fwd.notConnected'),
                    style: const TextStyle(
                        fontSize: 10.5, height: 1.4, color: AppColors.subtext)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(l.t('fwd.empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.overlay)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _row(ref, list[i]),
                ),
        ),
      ],
    );
  }

  Widget _row(WidgetRef ref, ForwardEntry e) {
    final l = ref.watch(l10nProvider);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.surface0),
        ),
        child: Row(
          children: [
            // 运行状态点
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: e.running ? AppColors.green : AppColors.overlay,
                shape: BoxShape.circle,
                boxShadow: e.running
                    ? [
                        BoxShadow(
                            color: AppColors.green.withValues(alpha: .6),
                            blurRadius: 6)
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'localhost:${e.localPort}  →  ${e.remoteHost}:${e.remotePort}',
                      style: const TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 12,
                          color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(
                      e.error != null
                          ? e.error!
                          : (e.running ? l.t('fwd.running') : l.t('fwd.stopped')),
                      style: TextStyle(
                          fontSize: 10,
                          color: e.error != null
                              ? AppColors.red
                              : AppColors.overlay)),
                ],
              ),
            ),
            // 启停
            IconButton(
              icon: Icon(
                  e.running
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                  size: 18,
                  color: e.running ? AppColors.yellow : AppColors.green),
              splashRadius: 16,
              tooltip: e.running ? l.t('fwd.stop') : l.t('fwd.start'),
              onPressed: () => ref.read(forwardProvider.notifier).toggle(e.id),
            ),
            // 删除
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.red),
              splashRadius: 16,
              tooltip: l.t('common.delete'),
              onPressed: () => ref.read(forwardProvider.notifier).remove(e.id),
            ),
          ],
        ),
      );
  }
}

// 添加隧道子对话框：本地端口 + 远程地址 + 远程端口
void _showAddDialog(BuildContext context, WidgetRef ref) {
  final localPort = TextEditingController();
  final remoteHost = TextEditingController(text: '127.0.0.1');
  final remotePort = TextEditingController();
  String? errorText;
  final l = ref.watch(l10nProvider);

  showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setState) => Dialog(
        backgroundColor: AppColors.mantle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.surface0),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.swap_horiz_outlined,
                        size: 18, color: AppColors.blue),
                    const SizedBox(width: 8),
                    Text(l.t('fwd.addTunnel'),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(l.t('fwd.addDesc'),
                    style: const TextStyle(
                        fontSize: 10.5, height: 1.4, color: AppColors.overlay)),
                const SizedBox(height: 14),
                _label(l.t('fwd.localPort')),
                _input(localPort, hint: l.t('fwd.localPortHint')),
                const SizedBox(height: 12),
                _label(l.t('fwd.remoteHost')),
                _input(remoteHost, hint: l.t('fwd.remoteHostHint')),
                const SizedBox(height: 12),
                _label(l.t('fwd.remotePort')),
                _input(remotePort, hint: l.t('fwd.remotePortHint')),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(errorText!,
                      style:
                          const TextStyle(fontSize: 11, color: AppColors.red)),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l.t('common.cancel'),
                          style: const TextStyle(color: AppColors.subtext)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          foregroundColor: AppColors.crust),
                      onPressed: () {
                        final lp = int.tryParse(localPort.text.trim());
                        final rp = int.tryParse(remotePort.text.trim());
                        final rh = remoteHost.text.trim();
                        if (lp == null || lp < 1 || lp > 65535) {
                          setState(() => errorText = l.t('fwd.errLocalPort'));
                          return;
                        }
                        if (rp == null || rp < 1 || rp > 65535) {
                          setState(() => errorText = l.t('fwd.errRemotePort'));
                          return;
                        }
                        if (rh.isEmpty) {
                          setState(() => errorText = l.t('fwd.errRemoteHost'));
                          return;
                        }
                        ref.read(forwardProvider.notifier).add(
                              localPort: lp,
                              remoteHost: rh,
                              remotePort: rp,
                            );
                        Navigator.pop(ctx);
                      },
                      child: Text(l.t('fwd.addStart')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: const TextStyle(fontSize: 11, color: AppColors.subtext)),
    );

Widget _input(TextEditingController c, {String? hint}) => TextField(
      controller: c,
      style: const TextStyle(fontSize: 13, color: AppColors.text),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: AppColors.overlay),
        filled: true,
        fillColor: AppColors.base,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.surface0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.blue),
        ),
      ),
    );
