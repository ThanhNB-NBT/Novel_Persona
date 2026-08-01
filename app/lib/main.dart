import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'endpoint.dart';
import 'errorlog.dart';
import 'hanviet.dart';
import 'ink_transition.dart';
import 'notify.dart';
import 'theme.dart';
import 'screens/admin/admin.dart';
import 'screens/account/edit_profile.dart';
import 'screens/account/guide.dart';
import 'screens/cultivation/cultivation.dart';
import 'screens/admin/errors.dart';
import 'screens/novel/glossary.dart';
import 'screens/account/login.dart';
import 'screens/library/notifications.dart';
import 'screens/library/offline_library.dart';
import 'screens/novel/novel_detail.dart';
import 'screens/reader/reader.dart';
import 'screens/reader/reader_settings.dart';
import 'screens/explore/search.dart';
import 'screens/shell.dart';

// Key đặt trong app/.env (đã gitignore), chạy:
//   flutter run -d <android-device> --dart-define-from-file=.env
// SUPABASE_URL/ANON_KEY là ĐÍCH MẶC ĐỊNH nướng vào bản build (fallback cuối).
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _endpointAllowedHosts = String.fromEnvironment('ENDPOINT_ALLOWED_HOSTS');
// Chuyển kho lưu KHÔNG cần build lại: app đọc {url, anonKey} từ 1 file JSON tĩnh
// công khai lúc khởi động (đặt trên R2/GitHub raw — chỗ độc lập với chính Supabase,
// để lúc Supabase chết vẫn tải được). Lật kho = sửa 1 file JSON đó rồi mở lại app.
// Rỗng → giữ nguyên hành vi cũ (chỉ dùng đích nướng sẵn).
const _endpointConfigUrl = String.fromEnvironment('ENDPOINT_CONFIG_URL');

/// Chỉ chuyển sang đích mới khi Data API, Auth và Storage đều sẵn sàng. Nếu mọi đích đều
/// đang offline, vẫn khởi tạo bằng cache/default để người dùng vào thư viện offline.
Future<Endpoint> _resolveEndpoint() async {
  final candidates = <Endpoint>[];
  final allowedHosts = endpointAllowedHosts(supabaseUrl, _endpointAllowedHosts);
  void add(Endpoint? ep) {
    if (ep != null && !candidates.any((e) => e.url == ep.url)) {
      candidates.add(ep);
    }
  }

  if (_endpointConfigUrl.isNotEmpty) {
    candidates.addAll(
      endpointConfigCandidates(
        await _fetchJson(_endpointConfigUrl),
        allowedHosts: allowedHosts,
      ),
    );
  }
  final cached = endpointFromValues(
    prefs.getString('endpoint_url'),
    prefs.getString('endpoint_anon'),
    allowedHosts: allowedHosts,
  );
  add(cached);
  final builtIn = endpointFromValues(supabaseUrl, supabaseAnonKey);
  add(builtIn);
  if (candidates.isEmpty) {
    throw StateError(
      'Không có endpoint hợp lệ. Hãy kiểm tra SUPABASE_URL/ENDPOINT_CONFIG_URL.',
    );
  }

  final ready = await Future.wait(candidates.map(_endpointReady));
  for (var i = 0; i < candidates.length; i++) {
    if (!ready[i]) continue;
    final ep = candidates[i];
    await prefs.setString('endpoint_url', ep.url);
    await prefs.setString('endpoint_anon', ep.anonKey);
    return ep;
  }
  return cached ?? builtIn ?? candidates.first;
}

// ponytail: HttpClient stdlib thay vì thêm package http. Timeout 4s cứng — chỗ host
// JSON (R2/GitHub) gần như luôn sống nên hiếm khi chạm; chạm thì rơi xuống cache/default.
Future<Map<String, dynamic>?> _fetchJson(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  try {
    final resp =
        await (await client
                .getUrl(Uri.parse(url))
                .timeout(const Duration(seconds: 4)))
            .close()
            .timeout(const Duration(seconds: 4));
    if (resp.statusCode != 200) return null;
    return jsonDecode(await resp.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  } catch (_) {
    return null; // offline / host JSON chết → caller dùng cache hoặc default
  } finally {
    client.close(force: true);
  }
}

Future<bool> _endpointReady(Endpoint ep) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  try {
    const paths = [
      '/rest/v1/novels?select=id&limit=1',
      '/auth/v1/health',
      '/storage/v1/status',
    ];
    final statuses = await Future.wait(
      paths.map((path) async {
        final request = await client
            .getUrl(Uri.parse('${ep.url}$path'))
            .timeout(const Duration(seconds: 4));
        request.headers
          ..set('apikey', ep.anonKey)
          ..set(HttpHeaders.authorizationHeader, 'Bearer ${ep.anonKey}');
        final response = await request.close().timeout(
          const Duration(seconds: 4),
        );
        await response.drain<void>();
        return response.statusCode;
      }),
    );
    return statuses.every((status) => status >= 200 && status < 300);
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  final ep = await _resolveEndpoint();
  activeEndpointUrl = ep.url;
  await Supabase.initialize(
    url: ep.url,
    publishableKey: ep.anonKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: SharedPreferencesLocalStorage(
        persistSessionKey: endpointAuthStorageKey(ep.url),
      ),
    ),
  );
  AppErrorLog.install(); // bắt lỗi runtime → xem ở màn "Nhật ký lỗi"
  await initNotifications();
  loadHanViet(); // bảng tra Hán-Việt cho form sửa dịch — nạp nền, không chặn khởi động
  chapterNotifier.start(); // thông báo khi chương trong tủ sách dịch xong
  // đăng nhập/xuất → nối lại kênh realtime (kênh mở trước khi login không mang auth)
  sb.auth.onAuthStateChange.listen((s) {
    chapterNotifier.start();
    // có phiên (khôi phục lúc mở app / vừa đăng nhập) → quét chương dịch xong
    // trong lúc app tắt (realtime không sống lúc đó nên phải quét bù)
    if (s.event == AuthChangeEvent.initialSession ||
        s.event == AuthChangeEvent.signedIn) {
      checkMissedChapters();
    }
  });
  // quay lại app từ nền: socket realtime thường đã bị OS ngắt → quét bù luôn
  // (binding giữ observer nên không cần giữ tham chiếu)
  AppLifecycleListener(onResume: checkMissedChapters);
  runApp(const ProviderScope(child: NovelApp()));
}

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, _) => const RootShell()),
  // Mọi màn push đi qua chuyển cảnh MỰC LOANG (ink_transition.dart) — chữ ký
  // chuyển động của app. Riêng màn đọc giữ transition riêng theo chế độ lật/cuộn.
  GoRoute(
      path: '/login',
      pageBuilder: (_, s) => inkPage(key: s.pageKey, child: const LoginScreen())),
  GoRoute(
      path: '/search',
      pageBuilder: (_, s) => inkPage(key: s.pageKey, child: const SearchScreen())),
  GoRoute(
      path: '/profile/edit',
      pageBuilder: (_, s) =>
          inkPage(key: s.pageKey, child: const EditProfileScreen())),
  GoRoute(
      path: '/offline',
      pageBuilder: (_, s) =>
          inkPage(key: s.pageKey, child: const OfflineLibraryScreen())),
  GoRoute(
      path: '/guide',
      pageBuilder: (_, s) => inkPage(key: s.pageKey, child: const GuideScreen())),
  GoRoute(
      path: '/notifications',
      pageBuilder: (_, s) =>
          inkPage(key: s.pageKey, child: const NotificationsScreen())),
  GoRoute(
      path: '/errors',
      pageBuilder: (_, s) => inkPage(key: s.pageKey, child: const ErrorLogScreen())),
  GoRoute(
      path: '/admin',
      pageBuilder: (_, s) => inkPage(key: s.pageKey, child: const AdminScreen())),
  GoRoute(
      path: '/cultivation',
      pageBuilder: (_, s) =>
          inkPage(key: s.pageKey, child: const CultivationScreen())),
  GoRoute(
    path: '/admin/novel/:id',
    pageBuilder: (_, s) => inkPage(
        key: s.pageKey,
        child: AdminNovelScreen(novelId: int.parse(s.pathParameters['id']!))),
  ),
  GoRoute(
    path: '/novel/:id',
    pageBuilder: (_, s) => inkPage(
        key: s.pageKey,
        child: NovelDetailScreen(novelId: int.parse(s.pathParameters['id']!))),
  ),
  GoRoute(
    path: '/novel/:id/glossary',
    pageBuilder: (_, s) => inkPage(
        key: s.pageKey,
        child: GlossaryScreen(novelId: int.parse(s.pathParameters['id']!))),
  ),
  GoRoute(
    path: '/novel/:id/read/:index',
    // Transition đổi chương theo chế độ đọc: lật trang giữ trượt NGANG (khớp thao tác
    // vuốt ngang); cuộn dọc dùng fade trung tính (trượt ngang lệch cảm giác cuộn).
    pageBuilder: (context, s) {
      final pageMode =
          ProviderScope.containerOf(context).read(readerSettingsProvider).pageMode;
      return CustomTransitionPage(
        key: s.pageKey,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, anim, _, child) => pageMode
            ? SlideTransition(
                position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                child: child)
            : FadeTransition(opacity: anim, child: child),
        child: ReaderScreen(
          novelId: int.parse(s.pathParameters['id']!),
          chapterIndex: int.parse(s.pathParameters['index']!),
        ),
      );
    },
  ),
]);

/// Bỏ hiệu ứng kéo giãn (stretch) của Material 3, thay bằng vòng glow mờ ở mép
/// khi cuộn hết — nội dung đứng yên, người dùng biết đã hết.
class _GlowScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return GlowingOverscrollIndicator(
      axisDirection: details.direction,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
      child: child,
    );
  }
}

class NovelApp extends ConsumerWidget {
  const NovelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    return MaterialApp.router(
      title: 'Gác Truyện',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _GlowScrollBehavior(),
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: switch (mode) { 1 => ThemeMode.light, 2 => ThemeMode.dark, _ => ThemeMode.system },
      // Đổi theme TỨC THỜI (1 frame) — lerp theme theo từng frame là nguồn khựng
      // (cả cây rebuild mỗi frame). Cái "êm" giao cho lớp scrim bên dưới lo.
      themeAnimationDuration: Duration.zero,
      builder: (_, child) => _ThemeSwitchScrim(child: child!),
      routerConfig: _router,
    );
  }
}

/// Che khoảnh khắc đổi sáng/tối: phủ lớp tối mờ lóe lên nhanh rồi tan chậm.
/// Theme swap 1 frame dưới lớp phủ → không lóe trắng, không khựng kéo dài.
class _ThemeSwitchScrim extends StatefulWidget {
  final Widget child;
  const _ThemeSwitchScrim({required this.child});
  @override
  State<_ThemeSwitchScrim> createState() => _ThemeSwitchScrimState();
}

class _ThemeSwitchScrimState extends State<_ThemeSwitchScrim>
    with SingleTickerProviderStateMixin {
  late final _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _alpha = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.3).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30),
    TweenSequenceItem(
        tween: Tween(begin: 0.3, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 70),
  ]).animate(_ctrl);
  Brightness? _last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Theme.of(context).brightness;
    if (_last != null && b != _last) _ctrl.forward(from: 0);
    _last = b;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) => _ctrl.isAnimating
              ? Container(color: Colors.black.withValues(alpha: _alpha.value))
              : const SizedBox.shrink(),
        ),
      ),
    ]);
  }
}
