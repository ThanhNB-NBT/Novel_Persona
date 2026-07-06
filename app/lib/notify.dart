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
        notificationDetails: const NotificationDetails(
          android: _androidChannel,
          // iOS: hiện banner + kêu cả khi app đang mở (foreground)
          iOS: DarwinNotificationDetails(
              presentAlert: true, presentBanner: true, presentSound: true),
        ),
      );
    } catch (_) {
      // nền tảng không hỗ trợ → bỏ qua
    }
  }
}

final chapterNotifier = ChapterNotifier();
