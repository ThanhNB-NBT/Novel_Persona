import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';

/// Thông báo LOCAL (hiện trên thanh thông báo hệ thống, không cần push/Firebase):
/// nghe Realtime bảng chapters, chương của truyện trong tủ sách dịch xong thì bắn
/// notification. Hoạt động khi app đang mở HOẶC chạy nền (chưa bị OS kill hẳn —
/// lúc đó kết nối Realtime còn sống). App bị tắt hẳn thì cần push (ngoài phạm vi).
final _plugin = FlutterLocalNotificationsPlugin();

const _androidChannel = AndroidNotificationDetails(
  'chapters', 'Chương dịch xong',
  channelDescription: 'Báo khi chương truyện trong tủ sách được dịch xong',
  importance: Importance.high,
  priority: Priority.high,
);

const _details = NotificationDetails(
  android: _androidChannel,
  // iOS: hiện banner + kêu cả khi app đang mở (foreground)
  iOS: DarwinNotificationDetails(
      presentAlert: true, presentBanner: true, presentSound: true),
);

/// Gọi 1 lần khi khởi động app (trước chapterNotifier.start).
Future<void> initNotifications() async {
  try {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      ),
    );
    // xin quyền hiện thông báo (Android 13+, iOS)
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  } catch (_) {
    // nền tảng chưa hỗ trợ (vd Windows lúc dev) → bỏ qua, không chặn app
  }
}

class ChapterNotifier {
  RealtimeChannel? _channel;
  final Set<int> _seen = {}; // chapter id đã báo trong phiên — tránh báo lặp

  void start() {
    stop();
    final ch = sb.channel('chapter-notify').onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chapters',
          callback: _onUpdate,
        );
    _channel = ch;
    // Kênh rớt (mạng chập chờn/app nền lâu) mà không nối lại = "không bao giờ
    // thấy thông báo". Lỗi/đóng → thử nối lại sau 5s (chỉ khi chưa bị stop chủ động).
    ch.subscribe((status, [_]) {
      if ((status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed) &&
          identical(_channel, ch)) {
        Future.delayed(const Duration(seconds: 5), () {
          if (identical(_channel, ch)) start();
        });
      }
    });
  }

  void stop() {
    if (_channel != null) sb.removeChannel(_channel!);
    _channel = null;
  }

  Future<void> _onUpdate(PostgresChangePayload payload) async {
    final r = payload.newRecord;
    if (r['translation_status'] != 'done') return;
    if (sb.auth.currentUser == null) return;
    final chapterId = r['id'] as int;
    if (!_seen.add(chapterId)) return; // đã báo chương này rồi

    final novelId = r['novel_id'] as int;
    // chỉ báo truyện có trong tủ sách của user (RLS tự lọc theo auth.uid)
    final inLib = await sb
        .from('library')
        .select('novel_id')
        .eq('novel_id', novelId)
        .maybeSingle();
    if (inLib == null) return;

    final nv = await sb
        .from('novels')
        .select('title_vi, title_zh')
        .eq('id', novelId)
        .maybeSingle();
    final title = nv?['title_vi'] ?? nv?['title_zh'] ?? 'Truyện';
    final idx = r['chapter_index'];

    try {
      await _plugin.show(
        id: chapterId, // id notification = chapter id (thay thế nếu trùng)
        title: '$title',
        body: 'Chương $idx đã dịch xong',
        notificationDetails: _details,
      );
    } catch (_) {
      // nền tảng không hỗ trợ → bỏ qua
    }
  }
}

final chapterNotifier = ChapterNotifier();

/// Catch-up khi mở app / quay lại từ nền: realtime chỉ sống lúc app mở nên
/// chương dịch xong trong lúc app tắt KHÔNG BAO GIỜ được báo (lý do "chưa từng
/// thấy thông báo"). Quét chương dịch xong sau mốc lần kiểm trước, bắn dồn
/// theo truyện. Push thật (FCM) khi nào cần thì thêm sau.
Future<void> checkMissedChapters() async {
  if (sb.auth.currentUser == null) return;
  final last = prefs.getString('notify_last_check');
  await prefs.setString(
      'notify_last_check', DateTime.now().toUtc().toIso8601String());
  if (last == null) return; // lần đầu: chỉ đặt mốc, khỏi dội thông báo cũ

  final lib = await sb.from('library').select('novel_id');
  final ids = [for (final r in lib) r['novel_id'] as int];
  if (ids.isEmpty) return;
  final rows = List<Rec>.from(await sb
      .from('chapters')
      .select('chapter_index, novel_id, novels(title_vi, title_zh)')
      .inFilter('novel_id', ids)
      .eq('translation_status', 'done')
      .gt('translated_at', last));
  final byNovel = <int, List<Rec>>{};
  for (final r in rows) {
    (byNovel[r['novel_id'] as int] ??= []).add(r);
  }
  for (final e in byNovel.entries) {
    final nv = (e.value.first['novels'] as Map?) ?? const {};
    final title = nv['title_vi'] ?? nv['title_zh'] ?? 'Truyện';
    final latest = e.value
        .map((c) => c['chapter_index'] as int)
        .reduce((a, b) => a > b ? a : b);
    try {
      await _plugin.show(
        id: e.key, // id = novel id → mở app nhiều lần chỉ thay thế, không dồn rác
        title: '$title',
        body: e.value.length == 1
            ? 'Chương $latest đã dịch xong'
            : '${e.value.length} chương mới dịch xong (mới nhất: chương $latest)',
        notificationDetails: _details,
      );
    } catch (_) {
      // nền tảng không hỗ trợ → bỏ qua
    }
  }
}
