"""Self-check bảng tra Hán-Việt + quy tắc reconcile (không mạng, không DB)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.translator.hanviet import han_viet, reconcile


def main() -> None:
    # tra bảng thuần
    assert han_viet("罗森") == "La Sâm"
    assert han_viet("张景四") == "Trương Cảnh Tứ"
    assert han_viet("筑基") == "Trúc Cơ"

    # LLM phiên bừa kiểu pinyin → thay bằng bản tra (bug "Lao Sen" 2026-07)
    assert reconcile("罗森", "Lao Sen", "person") == "La Sâm"
    # LLM phiên đúng → giữ nguyên (kể cả viết hoa của model)
    assert reconcile("林松", "Lâm Tùng", "person") == "Lâm Tùng"
    # tên ngoại/từ mượn trả về ASCII → giữ (đúng quy tắc prompt)
    assert reconcile("安娜", "Anna", "person") == "Anna"
    assert reconcile("哥布林", "goblin", "other") == "goblin"
    # phiên âm gạch nối có dấu (kiểu cấm, bug chương 43) → thay bằng bản tra;
    # gạch nối thuần ASCII là tên Tây hợp lệ → giữ
    assert reconcile("安德森", "An-đơ-sơn", "person") == han_viet("安德森")
    assert reconcile("让皮埃尔", "Jean-Pierre", "person") == "Jean-Pierre"
    # person toàn viết hoa nhưng LỆCH số từ ("Héc Nơ" 2 từ / 3 chữ) → phiên hỏng, tra thẳng
    assert reconcile("赫克诺", "Héc Nơ", "person") == han_viet("赫克诺")
    # place/sect lệch số từ toàn viết hoa vẫn giữ (có thể là dịch nghĩa kiểu tên gọi)
    assert reconcile("黑龙之城", "Thành Hắc Long", "place") == "Thành Hắc Long"
    # item/skill có thể dịch NGHĨA → không ép Hán-Việt
    assert reconcile("火焰剑", "Kiếm Lửa", "item") == "Kiếm Lửa"
    # chữ ngoài bảng → giữ nguyên, không đoán bừa
    assert reconcile("罗㜽", "Gì Đó", "person") == "Gì Đó"
    assert reconcile(None, "Ai Đó", "person") == "Ai Đó"
    # DỊCH NGHĨA (không phải khuôn phiên âm) → giữ nguyên, kể cả place/sect
    # (bài học chạy thật: "đồn cảnh sát"→"Phái Xuất Sở" là tệ đi)
    assert reconcile("派出所", "đồn cảnh sát", "place") == "đồn cảnh sát"
    assert reconcile("小溪", "suối nhỏ", "place") == "suối nhỏ"
    assert reconcile("清虚山", "núi Thanh Hư", "place") == "núi Thanh Hư"  # có từ thường "núi"
    # vi còn sót chữ Hán → tra thẳng
    assert reconcile("副官", "副官", "person") == "Phó Quan"
    # chữ đa âm 宁: ưu tiên "ninh" trong tên riêng (override _PREFERRED)
    assert reconcile("宁飞", "Nào Đó", "person") == "Ninh Phi"


if __name__ == "__main__":
    main()
    print("OK — test_hanviet pass")
