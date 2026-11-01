import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../data.dart';
import '../../login_guard.dart';
import '../../widgets.dart';

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
  Duration _wait = LoginGuard.read().wait();
  Timer? _tick;

  void _startTick() {
    _tick?.cancel();
    if (_wait == Duration.zero) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _wait = LoginGuard.read().wait());
      if (_wait == Duration.zero) _tick?.cancel();
    });
  }

  @override
  void initState() {
    super.initState();
    _startTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final left = LoginGuard.read().wait();
    if (left > Duration.zero) {
      setState(() => _wait = left); // đang khoá: không gọi API
      _startTick();
      return;
    }
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
      await LoginGuard.empty.save();
      // Tới màn này bằng 2 đường: push từ Cài đặt (pop về chỗ cũ), hoặc bị
      // _authGate đẩy tới — lúc đó ngăn xếp có thể rỗng, pop là kẹt màn trắng.
      // Provider phụ thuộc auth tự nạp lại (authStateProvider).
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      }
    } catch (e) {
      // Chỉ lỗi do thông tin sai / bị server giới hạn mới tính; mất mạng thì không phạt.
      if (e is AuthException && (e.statusCode == '400' || e.statusCode == '429')) {
        final g = LoginGuard.read().failed();
        await g.save();
        _wait = g.wait();
        _startTick();
      }
      if (mounted) setState(() => _error = loiDeHieu(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                  if (_wait > Duration.zero)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('Sai quá nhiều lần — thử lại sau ${_wait.inSeconds + 1} giây',
                          style: t.bodySmall?.copyWith(color: cs.error)),
                    )
                  else if (_error != null)
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
                      onPressed: _busy || _wait > Duration.zero ? null : _submit,
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
                style: t.displayMedium?.copyWith(color: Colors.white, height: 1.02)),
          ]),
        ]),
      ]),
    );
  }
}
