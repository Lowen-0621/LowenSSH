import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/config.dart';
import '../state/config_provider.dart';
import '../state/key_provider.dart';

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
  // 认证方式：password / key
  String authMode = 'password';
  String? selectedKeyId;
  final keys = ref.read(keyProvider);

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
          // 认证方式切换
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('认证方式',
                style: TextStyle(fontSize: 11, color: AppColors.subtext)),
          ),
          Row(
            children: [
              _authTab('password', '密码', authMode,
                  () => setState(() => authMode = 'password')),
              const SizedBox(width: 8),
              _authTab('key', '密钥', authMode,
                  () => setState(() => authMode = 'key')),
            ],
          ),
          const SizedBox(height: 12),
          // 密码模式：密码框；密钥模式：密钥下拉
          if (authMode == 'password')
            _field(pwd, '密码', obscure: true)
          else
            _keyDropdown(keys, selectedKeyId,
                (id) => setState(() => selectedKeyId = id)),
          const SizedBox(height: 4),
          _actions(ctx, okLabel: '添加', onOk: () {
            if (host.text.trim().isEmpty) return;
            // 密钥模式必须选中一把密钥
            if (authMode == 'key' && selectedKeyId == null) return;
            ref.read(configProvider.notifier).addHostEntry(
                  alias: alias.text.trim().isEmpty ? null : alias.text.trim(),
                  host: host.text.trim(),
                  port: int.tryParse(port.text.trim()) ?? 22,
                  user: user.text.trim().isEmpty ? 'root' : user.text.trim(),
                  password: authMode == 'password' && pwd.text.isNotEmpty
                      ? pwd.text
                      : null,
                  keyId: authMode == 'key' ? selectedKeyId : null,
                );
            Navigator.pop(ctx);
          }),
        ],
      ),
    ),
  );
}

// 认证方式切换标签
Widget _authTab(String id, String label, String current, VoidCallback onTap) =>
    Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: current == id ? AppColors.surface1 : AppColors.base,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: current == id ? AppColors.blue : AppColors.surface0),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  color:
                      current == id ? AppColors.text : AppColors.subtext)),
        ),
      ),
    );

// 密钥下拉选择
Widget _keyDropdown(
    List<SshKey> keys, String? selectedId, ValueChanged<String?> onChanged) {
  if (keys.isEmpty) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.base,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.surface0),
      ),
      child: const Text('密钥库为空，请先到「密钥库」添加密钥',
          style: TextStyle(fontSize: 11.5, color: AppColors.overlay)),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: Text('选择密钥',
            style: TextStyle(fontSize: 11, color: AppColors.subtext)),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.base,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.surface0),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedId,
            isExpanded: true,
            dropdownColor: AppColors.mantle,
            hint: const Text('请选择…',
                style: TextStyle(fontSize: 12, color: AppColors.overlay)),
            style: const TextStyle(fontSize: 13, color: AppColors.text),
            items: [
              for (final k in keys)
                DropdownMenuItem(value: k.id, child: Text(k.name)),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    ],
  );
}

/// LLM 设置已迁移到设置中心（ui/settings_center.dart）。
