import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'data.dart' show prefs;

/// Bắt + lưu lỗi runtime của app (local, vòng đệm ~60 lỗi) để xem trong màn "Nhật ký lỗi".
/// Không gửi đâu cả — chỉ giúp tự debug khi test trên máy thật mà không nối debugger.
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
