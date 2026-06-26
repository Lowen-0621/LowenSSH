import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/config.dart';
import '../state/key_provider.dart';
import '../state/config_provider.dart';

/// 密钥库对话框 —— 管理 SSH 私钥（列表 + 粘贴 PEM 添加 + 删除）。
/// 私钥与 passphrase 加密落盘（复用 crypto.dart），绝不存明文。
Future<void> showKeysDialog(BuildContext context) {
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
          child: _KeysBody(),
        ),
      ),
    ),
  );
}

class _KeysBody extends ConsumerWidget {
  const _KeysBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(keyProvider);
    final hosts = ref.watch(configProvider).hosts;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题 + 添加
        Row(
          children: [
            const Icon(Icons.vpn_key_outlined, size: 16, color: AppColors.text),
            const SizedBox(width: 8),
            const Text('密钥库',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
            const SizedBox(width: 8),
            Text('共 ${keys.length} 把',
                style: const TextStyle(fontSize: 11, color: AppColors.overlay)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showAddKeyDialog(context, ref),
              icon: const Icon(Icons.add, size: 15, color: AppColors.blue),
              label: const Text('添加密钥',
                  style: TextStyle(fontSize: 12, color: AppColors.blue)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Flexible(
          child: keys.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('暂无密钥，点「添加密钥」粘贴私钥 PEM',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, color: AppColors.overlay)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: keys.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final k = keys[i];
                    // 统计引用该密钥的主机数
                    final usedBy =
                        hosts.where((h) => h.keyId == k.id).length;
                    return _keyRow(context, ref, k, usedBy);
                  },
                ),
        ),
      ],
    );
  }

  Widget _keyRow(
          BuildContext context, WidgetRef ref, SshKey k, int usedBy) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.surface0),
        ),
        child: Row(
          children: [
            const Icon(Icons.vpn_key, size: 15, color: AppColors.yellow),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k.name,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(
                      '${k.passphraseEnc != null ? '🔒 带 passphrase · ' : ''}'
                      '${usedBy > 0 ? '$usedBy 台主机使用' : '未被使用'}',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.overlay)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.red),
              splashRadius: 16,
              tooltip: '删除',
              onPressed: () => _confirmDelete(context, ref, k, usedBy),
            ),
          ],
        ),
      );

  void _confirmDelete(
      BuildContext context, WidgetRef ref, SshKey k, int usedBy) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.mantle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.surface0),
        ),
        title: const Text('删除密钥',
            style: TextStyle(fontSize: 15, color: AppColors.text)),
        content: Text(
            usedBy > 0
                ? '密钥「${k.name}」正被 $usedBy 台主机使用，删除后这些主机将解除密钥绑定（需重新配置认证）。确定删除？'
                : '确定删除密钥「${k.name}」？此操作不可撤销。',
            style: const TextStyle(fontSize: 13, color: AppColors.subtext)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消',
                style: TextStyle(color: AppColors.subtext)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: AppColors.crust),
            onPressed: () {
              ref.read(keyProvider.notifier).remove(k.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// 添加密钥子对话框：名称 + 粘贴 PEM + 可选 passphrase
void _showAddKeyDialog(BuildContext context, WidgetRef ref) {
  final name = TextEditingController();
  final pem = TextEditingController();
  final passphrase = TextEditingController();
  String? errorText;

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
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: const [
                    Icon(Icons.vpn_key_outlined,
                        size: 18, color: AppColors.blue),
                    SizedBox(width: 8),
                    Text('添加密钥',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text)),
                  ],
                ),
                const SizedBox(height: 16),
                _label('名称'),
                _input(name, hint: 'id_ed25519'),
                const SizedBox(height: 12),
                _label('私钥（PEM，粘贴 -----BEGIN ... 全文）'),
                _input(pem,
                    hint: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                    maxLines: 6, mono: true),
                const SizedBox(height: 12),
                _label('passphrase（私钥无加密则留空）'),
                _input(passphrase, obscure: true),
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
                      child: const Text('取消',
                          style: TextStyle(color: AppColors.subtext)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          foregroundColor: AppColors.crust),
                      onPressed: () {
                        final pemText = pem.text.trim();
                        // 基本校验：必须像 PEM
                        if (!pemText.contains('-----BEGIN')) {
                          setState(() =>
                              errorText = '私钥格式不对，应以 -----BEGIN 开头');
                          return;
                        }
                        final nm = name.text.trim().isEmpty
                            ? '未命名密钥'
                            : name.text.trim();
                        ref.read(keyProvider.notifier).add(
                              name: nm,
                              privateKeyPem: pemText,
                              passphrase: passphrase.text.isEmpty
                                  ? null
                                  : passphrase.text,
                            );
                        Navigator.pop(ctx);
                      },
                      child: const Text('保存'),
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

Widget _input(TextEditingController c,
        {String? hint,
        bool obscure = false,
        int maxLines = 1,
        bool mono = false}) =>
    TextField(
      controller: c,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      style: TextStyle(
          fontSize: mono ? 11 : 13,
          fontFamily: mono ? kMonoFont : null,
          color: AppColors.text),
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
