import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';

/// Cập nhật trong app: đọc release mới nhất trên GitHub (repo public, khỏi cần
/// server riêng), so với version đang chạy → mời tải APK. iOS sideload thì chỉ
/// nhắc build qua SideStore (không tự cài được).
const _repo = 'ThanhNB-NBT/Novel_Persona';

typedef UpdateInfo = ({String version, String? apkUrl, String notes});

/// Release mới hơn bản đang chạy, null nếu đã mới nhất (hoặc lỗi mạng — im lặng).
final updateProvider = FutureProvider<UpdateInfo?>((ref) async {
  try {
    final cur = (await PackageInfo.fromPlatform()).version;
    final req = await HttpClient()
        .getUrl(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'));
    final resp = await req.close();
    if (resp.statusCode != 200) return null; // chưa có release nào / rate limit
    final r = jsonDecode(await resp.transform(utf8.decoder).join()) as Map;
    final latest = (r['tag_name'] as String? ?? '').replaceFirst('v', '');
    if (!_newer(latest, cur)) return null;
    final apk = (r['assets'] as List? ?? const [])
        .cast<Map>()
        .where((a) => '${a['name']}'.endsWith('.apk'))
        .firstOrNull;
    return (
      version: latest,
      apkUrl: apk?['browser_download_url'] as String?,
      notes: r['body'] as String? ?? '',
    );
  } catch (_) {
    return null; // offline/GitHub sập → coi như không có bản mới
  }
});

/// So version dạng x.y.z theo từng số (1.10.0 > 1.9.9).
bool _newer(String a, String b) {
  List<int> nums(String s) =>
      [for (final m in RegExp(r'\d+').allMatches(s)) int.parse(m.group(0)!)];
  final x = nums(a), y = nums(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

/// Gọi khi mở app: có bản mới thì hỏi (mỗi version chỉ hỏi 1 lần, bấm "Để sau"
/// không bị làm phiền lại — vẫn tải được chủ động trong Cài đặt).
Future<void> maybePromptUpdate(BuildContext context, WidgetRef ref) async {
  final info = await ref.read(updateProvider.future);
  if (info == null || !context.mounted) return;
  if (prefs.getString('update_dismissed') == info.version) return;
  await prefs.setString('update_dismissed', info.version);
  if (!context.mounted) return;
  showUpdateDialog(context, info);
}

void showUpdateDialog(BuildContext context, UpdateInfo info) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Có bản mới ${info.version}'),
      content: Text(
        Platform.isAndroid
            ? (info.notes.isEmpty
                ? 'Tải về rồi mở file APK để cài đè bản đang dùng.'
                : info.notes)
            : 'Build IPA mới qua GitHub Actions rồi cập nhật bằng SideStore.',
        maxLines: 10,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Để sau')),
        if (Platform.isAndroid && info.apkUrl != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(info.apkUrl!), mode: LaunchMode.externalApplication);
            },
            child: const Text('Tải bản mới'),
          )
        else
          // iOS (hoặc Android thiếu APK): không tự cài được → mở trang release
          // để xem ghi chú + tải asset, cài qua SideStore.
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse('https://github.com/$_repo/releases/latest'),
                  mode: LaunchMode.externalApplication);
            },
            child: const Text('Mở trang tải'),
          ),
      ],
    ),
  );
}
