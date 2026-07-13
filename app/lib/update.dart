import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';

/// Cập nhật trong app: đọc release mới nhất trên GitHub (repo public, khỏi cần
/// server riêng), so version → tải THẲNG trong app.
///   Android: tải APK rồi gọi trình cài hệ thống cài đè (1 hộp thoại xác nhận).
///   iOS sideload: tải IPA rồi mở khay chia sẻ để lưu vào Tệp / mở bằng SideStore
///                 (iOS cấm app tự cài app khác — SideStore mới cài được).
const _repo = 'ThanhNB-NBT/Novel_Persona';

typedef Asset = ({String name, String url});
typedef UpdateInfo = ({String version, Asset? apk, Asset? ipa, String notes});

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
    final assets = (r['assets'] as List? ?? const []).cast<Map>();
    Asset? pick(String ext) {
      final a = assets.where((a) => '${a['name']}'.toLowerCase().endsWith(ext)).firstOrNull;
      return a == null ? null : (name: '${a['name']}', url: '${a['browser_download_url']}');
    }

    return (
      version: latest,
      apk: pick('.apk'),
      ipa: pick('.ipa'),
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
  // Android cần APK, iOS cần IPA. Thiếu asset đúng nền → chỉ mở trang release.
  final asset = Platform.isAndroid ? info.apk : (Platform.isIOS ? info.ipa : null);
  final body = Platform.isAndroid
      ? (info.notes.isEmpty ? 'Tải bản mới rồi cài đè bản đang dùng.' : info.notes)
      : 'Tải IPA về máy rồi lưu vào Tệp / mở bằng SideStore để cài đè.';
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Có bản mới ${info.version}'),
      content: Text(body, maxLines: 12, overflow: TextOverflow.ellipsis),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Để sau')),
        if (asset != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndInstall(context, asset);
            },
            child: Text(Platform.isAndroid ? 'Tải & cài' : 'Tải về máy'),
          )
        else
          // nền không có asset (vd web) → mở trang release
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

/// Tải asset (apk/ipa) kèm thanh tiến trình → Android gọi trình cài; iOS mở khay
/// chia sẻ để lưu Tệp / mở SideStore. Dùng chung cho hộp thoại tự-hỏi lẫn nút
/// "Kiểm tra cập nhật" trong Cài đặt.
Future<void> _downloadAndInstall(BuildContext context, Asset asset) async {
  final progress = ValueNotifier<double>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Đang tải bản mới…'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, p, _) => Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: p > 0 ? p : null),
          const SizedBox(height: 10),
          Text(p > 0 ? '${(p * 100).toStringAsFixed(0)}%' : 'Bắt đầu tải…'),
        ]),
      ),
    ),
  );
  try {
    // Tải mới vào thư mục tạm (ghi đè bản tải dở lần trước).
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${asset.name}');
    final req = await HttpClient().getUrl(Uri.parse(asset.url)); // theo 302 tới CDN
    final resp = await req.close();
    if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
    final total = resp.contentLength;
    final sink = file.openWrite();
    var got = 0;
    await for (final chunk in resp) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) progress.value = got / total;
    }
    await sink.close();
    if (context.mounted) Navigator.pop(context); // đóng thanh tiến trình

    if (Platform.isAndroid) {
      // mở APK → trình cài hệ thống (cần quyền REQUEST_INSTALL_PACKAGES)
      final res = await OpenFilex.open(file.path);
      if (res.type != ResultType.done && context.mounted) {
        _snack(context, 'Không mở được trình cài: ${res.message}');
      }
    } else {
      // iOS: khay chia sẻ → "Lưu vào Tệp" hoặc mở thẳng SideStore
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: asset.name,
        text: 'Bản cập nhật Gác Truyện — mở bằng SideStore để cài.',
      ));
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      _snack(context, 'Tải bản mới lỗi: $e');
    }
  }
}

void _snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
