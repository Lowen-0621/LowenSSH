import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/config.dart';
import '../state/config_provider.dart';

/// 暗色对话框统一外壳
Future<T?> _showDark<T>(BuildContext context, Widget child) {
  return showDialog<T>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: AppColors.mantle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.surface0),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    ),
  );
}

/// 暗色输入框。密码框（obscure:true）带显示/隐藏切换按钮，
/// 避免不可见输入时丢字符却无从察觉。
class _Field extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  const _Field(this.controller, this.label, {this.hint, this.obscure = false});

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late bool _hidden = widget.obscure; // 密码框默认隐藏

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
              style: const TextStyle(fontSize: 11, color: AppColors.subtext)),
          const SizedBox(height: 4),
          TextField(
            controller: widget.controller,
            obscureText: _hidden,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hint,
              hintStyle:
                  const TextStyle(fontSize: 12, color: AppColors.overlay),
              filled: true,
              fillColor: AppColors.base,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              // 密码框右侧眼睛：点击切换明文/密文
              suffixIcon: widget.obscure
                  ? IconButton(
                      icon: Icon(
                        _hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16,
                        color: AppColors.overlay,
                      ),
                      splashRadius: 16,
                      onPressed: () => setState(() => _hidden = !_hidden),
                    )
                  : null,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.surface0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.blue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 兼容旧调用点的简写
Widget _field(TextEditingController c, String label,
        {String? hint, bool obscure = false}) =>
    _Field(c, label, hint: hint, obscure: obscure);

Widget _title(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.blue),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text)),
        ],
      ),
    );

Widget _actions(BuildContext context,
        {required VoidCallback onOk, String okLabel = '保存'}) =>
    Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消',
              style: TextStyle(color: AppColors.subtext)),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: onOk,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.blue,
              foregroundColor: AppColors.crust),
          child: Text(okLabel),
        ),
      ],
    );

/// 新建主机对话框
Future<void> showAddHostDialog(BuildContext context, WidgetRef ref) {
  final alias = TextEditingController();
  final host = TextEditingController();
  final port = TextEditingController(text: '22');
  final user = TextEditingController(text: 'root');
  final pwd = TextEditingController();

  return _showDark(
    context,
    StatefulBuilder(
      builder: (ctx, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(Icons.dns_outlined, '新建主机'),
          _field(alias, '别名（可选）', hint: 'web01'),
          _field(host, '主机地址', hint: '10.0.1.21 或 example.com'),
          _field(port, '端口', hint: '22'),
          _field(user, '用户名', hint: 'root'),
          _field(pwd, '密码', obscure: true),
          const SizedBox(height: 4),
          _actions(ctx, okLabel: '添加', onOk: () {
            if (host.text.trim().isEmpty) return;
            ref.read(configProvider.notifier).addHostEntry(
                  alias: alias.text.trim().isEmpty ? null : alias.text.trim(),
                  host: host.text.trim(),
                  port: int.tryParse(port.text.trim()) ?? 22,
                  user: user.text.trim().isEmpty ? 'root' : user.text.trim(),
                  password: pwd.text.isEmpty ? null : pwd.text,
                );
            Navigator.pop(ctx);
          }),
        ],
      ),
    ),
  );
}

/// LLM 设置对话框
Future<void> showLlmSettingsDialog(BuildContext context, WidgetRef ref) {
  final cfg = ref.read(configProvider).llm;
  final baseURL = TextEditingController(text: cfg.baseURL);
  final apiKey = TextEditingController(text: cfg.apiKey);
  final model = TextEditingController(text: cfg.model);

  return _showDark(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(Icons.settings_outlined, 'LLM 设置'),
        _field(baseURL, 'Base URL',
            hint: 'https://open.bigmodel.cn/api/paas/v4'),
        _field(apiKey, 'API Key', obscure: true),
        _field(model, '模型', hint: 'glm-4.6'),
        const SizedBox(height: 4),
        Builder(
          builder: (ctx) => _actions(ctx, onOk: () {
            ref.read(configProvider.notifier).updateLlm(LlmConfig(
                  baseURL: baseURL.text.trim(),
                  apiKey: apiKey.text.trim(),
                  model: model.text.trim(),
                ));
            Navigator.pop(ctx);
          }),
        ),
      ],
    ),
  );
}
