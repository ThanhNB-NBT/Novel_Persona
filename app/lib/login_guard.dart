import 'data.dart';

/// Khoá tạm theo máy sau nhiều lần sai mật khẩu liên tiếp. Chỉ chặn thao tác nhầm/dò tay trên giao diện:
/// kẻ gọi thẳng /auth/v1/token bỏ qua được → giới hạn thật phải ở server (GoTrue rate limit / Cloudflare).
/// Mirror Gac_Truyen_Web/src/lib/login-guard.js.
class LoginGuard {
  static const maxFails = 5;
  static const _baseMs = 30000;
  static const _capMs = 900000;
  static const _key = 'login_guard';

  final int fails;
  final int untilMs; // epoch ms
  const LoginGuard(this.fails, this.untilMs);
  static const empty = LoginGuard(0, 0);

  /// Sai lần thứ n → khoá bao lâu: dưới ngưỡng 0, rồi 30s, 1', 2', 4'… tối đa 15'.
  static int lockMs(int fails) =>
      fails < maxFails ? 0 : (_baseMs * (1 << (fails - maxFails).clamp(0, 10))).clamp(0, _capMs);

  /// Còn bị khoá bao lâu. Kẹp trong 15' để chỉnh đồng hồ máy cũng không khoá vĩnh viễn.
  Duration wait([int? nowMs]) {
    final left = untilMs - (nowMs ?? DateTime.now().millisecondsSinceEpoch);
    return Duration(milliseconds: left.clamp(0, _capMs));
  }

  LoginGuard failed([int? nowMs]) {
    final n = fails + 1;
    return LoginGuard(n, (nowMs ?? DateTime.now().millisecondsSinceEpoch) + lockMs(n));
  }

  static LoginGuard read() {
    final s = prefs.getString(_key)?.split(',');
    final f = s != null && s.length == 2 ? int.tryParse(s[0]) : null;
    final u = s != null && s.length == 2 ? int.tryParse(s[1]) : null;
    return f != null && u != null && f >= 0 ? LoginGuard(f, u) : empty;
  }

  Future<void> save() => prefs.setString(_key, '$fails,$untilMs');
}
