import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data.dart';
import '../../widgets.dart';
import 'tabs/crawl_tab.dart';
import 'tabs/cult_tab.dart';
import 'tabs/jobs_tab.dart';
import 'tabs/novels_tab.dart';
import 'tabs/reading_now_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/tokens_tab.dart';

/// Màn Quản trị (chỉ admin vào được — RLS + isAdminProvider chặn ở cả 2 đầu).
/// 7 tab: Worker (hàng đợi/lỗi), Crawl (nguồn + cấu hình), Đang đọc,
/// Truyện (ẩn/sửa), Token (chi phí LLM), Báo cáo, Tu Tiên.
/// Nội dung từng tab nằm trong thư mục tabs/ cùng cấp.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(isAdminProvider);
    return admin.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          body: AppError(e, onRetry: () => ref.invalidate(isAdminProvider))),
      data: (ok) {
        if (!ok) {
          return Scaffold(
            appBar: AppBar(title: const Text('Quản trị')),
            body: const Center(child: Text('Bạn không có quyền quản trị.')),
          );
        }
        return DefaultTabController(
          length: 7,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Quản trị'),
              actions: [
                IconButton(
                  tooltip: 'Chạy lại toàn bộ job lỗi + chương tải lỗi',
                  icon: const Icon(Icons.restart_alt_rounded),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final n = await retryAllFailed();
                      ref.invalidate(adminJobsProvider);
                      ref.invalidate(translateQueueProvider);
                      messenger.showSnackBar(SnackBar(
                          content: Text(n > 0
                              ? 'Đã đẩy lại $n job lỗi vào hàng đợi'
                              : 'Không có job lỗi nào')));
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Quét lỗi dịch (chương còn tiếng Trung / cụt / mất đoạn)',
                  icon: const Icon(Icons.fact_check_outlined),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await requestAudit();
                      messenger.showSnackBar(const SnackBar(
                          content: Text('Đã bắt đầu quét — chương lỗi sẽ tự '
                              'xếp lại dịch, xem tab Worker.')));
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                    }
                  },
                ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Worker'),
                  Tab(text: 'Crawl'),
                  Tab(text: 'Đang đọc'),
                  Tab(text: 'Truyện'),
                  Tab(text: 'Token'),
                  Tab(text: 'Báo cáo'),
                  Tab(text: 'Tu Tiên'),
                ],
              ),
            ),
            body: const TabBarView(children: [
              JobsTab(),
              CrawlTab(),
              ReadingNowTab(),
              NovelsTab(),
              TokensTab(),
              ReportsTab(),
              CultTab(),
            ]),
          ),
        );
      },
    );
  }
}
