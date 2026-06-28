import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../core/i18n.dart';
import '../core/lock_store.dart';
import '../state/settings_provider.dart';

/// 解锁界面 —— 已设主密码时，启动先过这一关，验证通过才进 AppShell。
class LockScreen extends ConsumerStatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    // 校验（多轮哈希，几十 ms，同步可接受）
    final ok = verifyMasterPassword(_ctrl.text);
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _checking = false;
        _error = _isZh ? '密码错误' : 'Wrong password';
        _ctrl.clear();
      });
      _focus.requestFocus();
    }
  }

  bool get _isZh => ref.read(settingsProvider).lang == AppLang.zh;

  @override
  Widget build(BuildContext context) {
    final zh = _isZh;
    return Scaffold(
      backgroundColor: AppColors.base,
      body: Center(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('◈',
                  style: TextStyle(fontSize: 40, color: AppColors.blue)),
              const SizedBox(height: 12),
              Text('LowenSSH',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.lavender,
                      letterSpacing: .5)),
              const SizedBox(height: 6),
              Text(zh ? '已锁定，请输入主密码' : 'Locked. Enter master password',
                  style: TextStyle(fontSize: 12.5, color: AppColors.overlay)),
              const SizedBox(height: 22),
              TextField(
                controller: _ctrl,
                focusNode: _focus,
                obscureText: true,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                style: TextStyle(fontSize: 14, color: AppColors.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.mantle,
                  hintText: zh ? '主密码' : 'Master password',
                  hintStyle: TextStyle(color: AppColors.overlay),
                  prefixIcon:
                      Icon(Icons.lock_outline, size: 18, color: AppColors.overlay),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: _error != null
                            ? AppColors.red
                            : AppColors.surface0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.blue),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!,
                      style: TextStyle(fontSize: 12, color: AppColors.red)),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _checking ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(zh ? '解锁' : 'Unlock',
                      style: TextStyle(
                          color: AppColors.crust,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
