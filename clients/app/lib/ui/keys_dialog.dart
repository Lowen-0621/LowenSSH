import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/config.dart';
import '../state/key_provider.dart';
import '../state/config_provider.dart';
import '../state/settings_provider.dart';

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
    final l = ref.watch(l10nProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题 + 添加
        Row(
          children: [
            const Icon(Icons.vpn_key_outlined, size: 16, color: AppColors.text),
            const SizedBox(width: 8),
            Text(l.t('keys.title'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
            const SizedBox(width: 8),
            Text(l.t('keys.count', {'n': '${keys.length}'}),
                style: const TextStyle(fontSize: 11, color: AppColors.overlay)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showAddKeyDialog(context, ref),
              icon: const Icon(Icons.add, size: 15, color: AppColors.blue),
              label: Text(l.t('keys.add'),
                  style: const TextStyle(fontSize: 12, color: AppColors.blue)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Flexible(
          child: keys.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(l.t('keys.empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.overlay)),
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
          BuildContext context, WidgetRef ref, SshKey k, int usedBy) {
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
                      '${k.passphraseEnc != null ? l.t('keys.withPassphrase') : ''}'
                      '${usedBy > 0 ? l.t('keys.usedBy', {'n': '$usedBy'}) : l.t('keys.unused')}',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.overlay)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.red),
              splashRadius: 16,
              tooltip: l.t('common.delete'),
              onPressed: () => _confirmDelete(context, ref, k, usedBy),
            ),
          ],
        ),
      );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, SshKey k, int usedBy) {
    final l = ref.watch(l10nProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.mantle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.surface0),
        ),
        title: Text(l.t('keys.deleteKey'),
            style: const TextStyle(fontSize: 15, color: AppColors.text)),
        content: Text(
            usedBy > 0
                ? l.t('keys.deleteUsed', {'name': k.name, 'n': '$usedBy'})
                : l.t('keys.deleteConfirm', {'name': k.name}),
            style: const TextStyle(fontSize: 13, color: AppColors.subtext)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('common.cancel'),
                style: const TextStyle(color: AppColors.subtext)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: AppColors.crust),
            onPressed: () {
              ref.read(keyProvider.notifier).remove(k.id);
              Navigator.pop(ctx);
            },
            child: Text(l.t('common.delete')),
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
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.vpn_key_outlined,
                        size: 18, color: AppColors.blue),
                    const SizedBox(width: 8),
                    Text(l.t('keys.add'),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text)),
                  ],
                ),
                const SizedBox(height: 16),
                _label(l.t('keys.name')),
                _input(name, hint: 'id_ed25519'),
                const SizedBox(height: 12),
                _label(l.t('keys.pem')),
                _input(pem,
                    hint: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                    maxLines: 6, mono: true),
                const SizedBox(height: 12),
                _label(l.t('keys.passphrase')),
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
                      child: Text(l.t('common.cancel'),
                          style: const TextStyle(color: AppColors.subtext)),
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
                              errorText = l.t('keys.errPem'));
                          return;
                        }
                        final nm = name.text.trim().isEmpty
                            ? l.t('keys.unnamed')
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
                      child: Text(l.t('common.save')),
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
