import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data.dart';
import '../neo_theme.dart';
import '../neo_widgets.dart';

/// Đăng nhập kiểu "truy cập hệ thống" — logic port từ app cũ, UI HUD mới.
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
      setState(() => _error = 'NHẬP EMAIL HỢP LỆ');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'MẬT KHẨU TỐI THIỂU 6 KÝ TỰ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await sb.auth.signInWithPassword(email: email, password: _password.text);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = _friendly('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('invalid login')) return 'SAI EMAIL HOẶC MẬT KHẨU';
    if (s.contains('network') || s.contains('socket')) return 'LỖI MẠNG — KIỂM TRA KẾT NỐI';
    return 'TRUY CẬP BỊ TỪ CHỐI — THỬ LẠI';
  }

  @override
  Widget build(BuildContext context) {
    return NeoScaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 100, maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Neo.dim),
                    onPressed: () => context.pop(),
                  ),
                ),
                const SizedBox(height: 20),
                Text('NEO // XÁC THỰC', style: Neo.mono(11, color: Neo.cyan, spacing: 4)),
                const SizedBox(height: 8),
                Text('Truy cập\nkho truyện', style: Neo.display(36)),
                const SizedBox(height: 28),
                NeoPanel(
                  glowColor: Neo.plasma,
                  borderColor: Neo.plasma.withValues(alpha: 0.35),
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      style: Neo.mono(14, color: Neo.text),
                      decoration: const InputDecoration(
                        labelText: 'EMAIL',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      style: Neo.mono(14, color: Neo.text),
                      decoration: InputDecoration(
                        labelText: 'MẬT KHẨU',
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text('! $_error', style: Neo.mono(11, color: Neo.danger)),
                    ],
                    const SizedBox(height: 22),
                    NeoButton(label: 'KẾT NỐI', busy: _busy, onPressed: _submit),
                  ]),
                ),
                const SizedBox(height: 16),
                Text('DÙNG TÀI KHOẢN ĐƯỢC CẤP · KHÔNG TỰ ĐĂNG KÝ',
                    textAlign: TextAlign.center, style: Neo.mono(9, spacing: 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
