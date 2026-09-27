import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'data.dart' show prefs, sb;

/// Bắt + lưu lỗi runtime của app (local, vòng đệm ~60 lỗi) để xem trong màn "Nhật ký lỗi".
/// 2.1: bản release còn gửi lỗi về server (RPC log_client_error, bảng client_errors —
/// server giới hạn 30 lỗi/giờ/user) để admin thấy lỗi trên máy người khác.
class AppErrorLog {
  static const _key = 'app_error_log';
  static const _max = 60;

  /// Danh sách lỗi (mới nhất trước) — màn hình listen cái này để tự cập nhật.
  static final ValueNotifier<List<Map<String, dynamic>>> entries = ValueNotifier([]);

  static void _load() {
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      entries.value = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {}
  }

  static void add(String message, [String? stack]) {
    final e = {
      'time': DateTime.now().toIso8601String(),
      'message': message,
      // giữ vài dòng đầu stack cho gọn (đủ để lần ra chỗ lỗi)
      'stack': (stack ?? '').split('\n').take(8).join('\n').trim(),
    };
    final list = [e, ...entries.value];
    if (list.length > _max) list.removeRange(_max, list.length);
    entries.value = list;
    prefs.setString(_key, jsonEncode(list));
    _upload(message, e['stack'] as String);
  }

  static String? _version;
  static String? _lastSent; // lỗi dựng widget hay lặp mỗi frame → chỉ gửi 1 lần liền nhau

  static void _upload(String message, String stack) {
    if (kDebugMode || message == _lastSent) return;
    _lastSent = message;
    () async {
      try {
        if (sb.auth.currentUser == null) return;
        _version ??= (await PackageInfo.fromPlatform()).version;
        await sb.rpc('log_client_error', params: {
          'p_message': message,
          'p_stack': stack,
          'p_version': _version,
          'p_platform': defaultTargetPlatform.name,
        });
      } catch (_) {
        // mất mạng / Supabase chưa khởi tạo: lỗi vẫn nằm trong log local, không add() lại
        // (add lỗi của chính việc gửi lỗi là vòng lặp)
      }
    }();
  }

  static void clear() {
    entries.value = [];
    prefs.remove(_key);
  }

  /// Gắn vào main(): bắt lỗi widget (FlutterError) + lỗi async chưa bắt (PlatformDispatcher).
  static void install() {
    _load();
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      add(details.exceptionAsString(), details.stack?.toString());
      prev?.call(details); // vẫn in ra console như thường
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      add(error.toString(), stack.toString());
      return false; // để cơ chế mặc định xử lý tiếp
    };
  }
}
