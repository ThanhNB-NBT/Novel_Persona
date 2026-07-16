import 'package:flutter/material.dart';

/// Màn HƯỚNG DẪN SỬ DỤNG: từng tính năng một mục, mỗi mục là các bước 1-2-3
/// (không gồm trang quản trị). Nội dung tĩnh — thêm tính năng mới thì thêm
/// _GuideSection tương ứng ở danh sách dưới.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Hướng dẫn sử dụng')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110), // chừa chỗ dock nổi
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
            child: Text(
              'App đọc truyện Trung dịch máy sang tiếng Việt. Mỗi mục dưới đây là '
              'một tính năng — bấm để xem các bước dùng.',
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          for (final s in _sections) _GuideCard(section: s),
        ],
      ),
    );
  }
}

class _GuideSection {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> steps;
  final String? tip;
  const _GuideSection(this.icon, this.title, this.subtitle, this.steps, {this.tip});
}

const _sections = [
  _GuideSection(
    Icons.swipe_rounded,
    'Làm quen với 5 tab',
    'Bố cục chính của app',
    [
      'Thanh dưới cùng có 5 tab: Tủ truyện · Khám phá · Tu Tiên (đĩa tròn ở giữa) · Hàng đợi · Cài đặt.',
      'Bấm vào tab hoặc VUỐT NGANG màn hình để chuyển qua lại.',
      'Chưa đăng nhập thì app mở tab Khám phá; đăng nhập rồi sẽ mở thẳng Tủ truyện của bạn.',
      'Đăng nhập ở tab Cài đặt (hoặc khi app yêu cầu) để dùng tủ sách, yêu cầu dịch và Tu Tiên.',
    ],
  ),
  _GuideSection(
    Icons.explore_rounded,
    'Khám phá & tìm truyện',
    'Duyệt kho, tìm kiếm, lọc thể loại',
    [
      'Tab Khám phá hiện các mục: truyện mới cập nhật, đề cử, theo thể loại… Kéo xuống để xem, bấm "Xem thêm" để mở cả mục.',
      'Bấm icon kính lúp để TÌM KIẾM — gõ tên tiếng Việt hoặc tiếng Trung đều được.',
      'Trong màn tìm kiếm có bộ LỌC theo thể loại / trạng thái (đang ra, hoàn thành).',
      'Bấm vào bìa truyện ở bất cứ đâu để mở trang thông tin truyện.',
    ],
    tip: 'Không thấy truyện muốn đọc? Sang tab Tủ truyện, bấm nút "Yêu cầu truyện mới" và '
        'nhập tên truyện (tiếng Việt hoặc tiếng Trung đều được) — hệ thống tự tìm tên gốc, '
        'crawl về và thêm thẳng vào tủ sách của bạn.',
  ),
  _GuideSection(
    Icons.menu_book_rounded,
    'Trang truyện & yêu cầu dịch',
    'Xem thông tin, mục lục, bắt đầu dịch',
    [
      'Trang truyện hiện bìa, tóm tắt, thể loại, trạng thái và mục lục chương.',
      'Truyện mới thường CHƯA dịch sẵn — bấm "Đọc" hoặc "Yêu cầu dịch" là hệ thống xếp hàng dịch, dịch tới đâu đọc tới đó.',
      'Chương đang dịch sẽ hiện tiến độ; theo dõi tất cả job ở tab Hàng đợi.',
      'Icon "Thuật ngữ" mở bảng tên riêng/thuật ngữ của truyện — xem cách app dịch tên nhân vật, môn phái…',
      'Bấm nút đánh dấu trên trang truyện để lưu vào tủ sách (truyện đang đọc dở cũng tự hiện ở tab Tủ truyện).',
    ],
  ),
  _GuideSection(
    Icons.chrome_reader_mode_rounded,
    'Đọc truyện',
    'Giao diện đọc, chuyển chương, tùy chỉnh',
    [
      'Chạm giữa màn hình để hiện/ẩn thanh công cụ khi đang đọc.',
      'Chuyển chương bằng nút ở thanh dưới, hoặc đọc hết chương tự sang chương kế.',
      'Mở CÀI ĐẶT ĐỌC (icon chữ Aa) để đổi: font, cỡ chữ, giãn dòng, màu nền, chế độ LẬT TRANG hay CUỘN DỌC — có khung xem trước, chỉnh gì thấy ngay.',
      'Cuối mỗi chương có khung BÌNH LUẬN — đọc và để lại cảm nghĩ.',
      'Đang đọc mà thấy hộp quà phát sáng thì bấm nhận — đó là cơ duyên Tu Tiên (xem mục Tu Tiên).',
    ],
    tip: 'Muốn NGHE truyện: bấm icon tai nghe trong màn đọc — app đọc thành tiếng '
        '(giọng tiếng Việt), tự chuyển chương, nghe được cả khi tắt màn hình.',
  ),
  _GuideSection(
    Icons.edit_note_rounded,
    'Sửa chỗ dịch sai',
    'Góp ý bản dịch ngay trong màn đọc',
    [
      'Thấy tên riêng/từ dịch sai khi đọc? CHẠM THẲNG vào từ đó trong trang — không cần bôi đen hay giữ.',
      'Form sửa hiện ra ngay dưới, có thể nới rộng vùng chọn thêm từ bên cạnh.',
      'App gợi ý sẵn phiên âm Hán-Việt và thuật ngữ liên quan — chọn gợi ý hoặc gõ bản đúng.',
      'Gửi xong bản sửa hiện NGAY trong chương; sửa tên/thuật ngữ thì hệ thống tự vá cho cả các chương khác.',
    ],
    tip: 'Sửa một lần, cả truyện được vá — không cần sửa từng chương.',
  ),
  _GuideSection(
    Icons.bookmarks_rounded,
    'Tủ truyện & tiến độ đọc',
    'Theo dõi truyện, đọc tiếp, chương mới',
    [
      'Tab Tủ truyện liệt kê truyện bạn theo dõi kèm thanh tiến độ đọc.',
      'Bấm nút ▶ trên dòng truyện để ĐỌC TIẾP đúng chương đang dở — một chạm.',
      'Truyện trong tủ ra chương mới sẽ có nhãn "Chương mới", và hệ thống TỰ DỊCH đuổi cho bạn.',
      'Icon chuông mở trang Thông báo: chương mới dịch xong của truyện trong tủ (7 ngày gần nhất).',
      'Muốn đọc không mạng: vào Cài đặt → "Bản offline" để tải chương về máy.',
    ],
  ),
  _GuideSection(
    Icons.hourglass_bottom_rounded,
    'Hàng đợi dịch',
    'Xem tiến độ dịch của cả hệ thống',
    [
      'Tab Hàng đợi hiện các truyện đang dịch và số chương chờ.',
      'Job của bạn yêu cầu sẽ được ưu tiên khi bạn đang đọc truyện đó.',
      'Chương lỗi sẽ được hệ thống tự quét và dịch lại định kỳ.',
    ],
  ),
  _GuideSection(
    Icons.self_improvement_rounded,
    'Tu Tiên — chơi trong lúc đọc',
    'Linh căn, cảnh giới, đan dược, trang bị',
    [
      'Tab giữa (đĩa tròn) là hệ thống Tu Tiên: nhân vật của bạn TỰ TU LUYỆN theo thời gian, đọc truyện để nhặt cơ duyên.',
      'Lần đầu mở, trời định cho bạn: chủng tộc (chọn một lần), BỘ HỆ linh căn (kim·mộc·thủy·hỏa·thổ, có thể trúng dị căn hiếm như Kiếm/Lôi/Thiên Linh Căn) và BẬC linh căn.',
      'BẬC linh căn quyết định tốc độ tu: Ngũ Hành Tạp chậm nhất → Đơn → Dị → Tiên Linh Căn nhanh nhất. Ăn đan luyện căn để cộng điểm thăng bậc — bậc càng cao càng tốn điểm. HỆ thì cố định, chỉ Chuyển Linh Đan mới tráo được.',
      'ĐỌC TRUYỆN để nhận quà: khoảng nửa số chương có cơ duyên (đan dược, công pháp, pháp bảo…) — bấm hộp quà hiện ra giữa chương.',
      'Vào tab Tu Tiên: học CÔNG PHÁP (hợp hệ linh căn được ×1.3 tốc độ), mặc trang bị, uống đan tăng tốc.',
      'Tu vi đầy thì ĐỘT PHÁ lên tầng/cảnh giới mới (có tỷ lệ thành công). Tới Độ Kiếp tầng 9 thì PHI THĂNG thành Tiên, mở thang bậc Tiên mới.',
      'Đồ trùng lặp trong kho có thể LUYỆN HÓA thành linh khí cộng thẳng vào tu vi.',
    ],
    tip: 'Tu Tiên chỉ để vui — không ảnh hưởng gì tới việc đọc. Càng đọc đều, cơ duyên càng nhiều.',
  ),
  _GuideSection(
    Icons.settings_rounded,
    'Cài đặt & tài khoản',
    'Giao diện, hồ sơ, chuỗi ngày đọc, cập nhật',
    [
      'Đổi giao diện Sáng/Tối/Theo hệ thống ở đầu tab Cài đặt.',
      'Thẻ tài khoản: sửa tên hiển thị, avatar; nút đăng xuất ở góc thẻ.',
      'Bảng thống kê hiện CHUỖI NGÀY ĐỌC liên tiếp (streak) — đọc mỗi ngày để giữ lửa.',
      '"Kiểm tra cập nhật" tải bản app mới nhất từ GitHub Releases; có bản mới app cũng tự mời.',
    ],
  ),
];

/// Thẻ mục hướng dẫn: header icon + tiêu đề, bung ra danh sách bước đánh số.
class _GuideCard extends StatelessWidget {
  final _GuideSection section;
  const _GuideCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Theme(
          // bỏ divider mặc định của ExpansionTile cho khối liền mạch
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(section.icon, size: 21, color: cs.primary),
            ),
            title: Text(section.title,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(section.subtitle,
                style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            children: [
              for (var i = 0; i < section.steps.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 2 : 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(top: 1),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: cs.primary.withValues(alpha: 0.45)),
                      ),
                      child: Text('${i + 1}',
                          style: t.labelSmall?.copyWith(
                              color: cs.primary, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(section.steps[i], style: t.bodyMedium)),
                  ]),
                ),
              if (section.tip != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lightbulb_rounded, size: 17, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(section.tip!,
                          style: t.bodyMedium
                              ?.copyWith(color: cs.onPrimaryContainer)),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
