import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Nhập email hợp lệ');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Mật khẩu tối thiểu 6 ký tự');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await sb.auth.signInWithPassword(email: email, password: _password.text);
      if (mounted) context.pop(); // provider phụ thuộc auth tự nạp lại (authStateProvider)
    } catch (e) {
      setState(() => _error = _friendly('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('invalid login')) return 'Sai email hoặc mật khẩu.';
    if (s.contains('network') || s.contains('socket')) return 'Lỗi mạng — kiểm tra kết nối.';
    return 'Đăng nhập thất bại. Thử lại.';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final deep = Color.lerp(cs.primary, Colors.black, 0.42)!;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(children: [
            _hero(context, cs, t, deep),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Đăng nhập', style: t.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Dùng tài khoản được cấp để đọc và yêu cầu dịch.', style: t.bodyMedium),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                        icon: Icon(_obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(children: [
                        Icon(Icons.error_outline_rounded, size: 16, color: cs.error),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_error!, style: t.bodySmall?.copyWith(color: cs.error))),
                      ]),
                    ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.onPrimary))
                          : const Text('Đăng nhập'),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Hero gradient: logo phát sáng + tên thương hiệu, cảm giác "công nghệ".
  Widget _hero(BuildContext context, ColorScheme cs, TextTheme t, Color deep) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 34),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, deep],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
        Stack(children: [
          // vân sáng mờ phía sau logo
          Positioned(
            left: 6, top: -6,
            child: Icon(Icons.auto_stories_rounded,
                size: 96, color: Colors.white.withValues(alpha: 0.10)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            // logo tile phát sáng
            Container(
              width: 62, height: 62,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 20, spreadRadius: -4),
                ],
              ),
              child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 16),
            Text('TÀNG THƯ CÁC · TRUY CẬP',
                style: t.labelSmall?.copyWith(
                    letterSpacing: 3, color: Colors.white.withValues(alpha: 0.85))),
            const SizedBox(height: 4),
            Text('Kho truyện dịch của bạn',
                style: t.displaySmall?.copyWith(color: Colors.white, height: 1.05)),
          ]),
        ]),
      ]),
    );
  }
}
