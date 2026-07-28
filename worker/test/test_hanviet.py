"""Self-check bảng tra Hán-Việt + quy tắc reconcile (không mạng, không DB)."""
import os
import sys
from pathlib import Path

_WORKER = Path(__file__).resolve().parents[1]
_REPO = _WORKER.parent
sys.path.insert(0, str(_WORKER))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.translator.hanviet import (
    english_meaning, han_viet, reconcile, transliteration_suspect)


def main() -> None:
    # Bảng app và worker phải cùng một dữ liệu, nếu không form sửa và auto-glossary sẽ lệch nhau.
    assert (_REPO / "app/assets/hanviet.tsv").read_bytes() == (
        _WORKER / "novelworker/data/hanviet.tsv").read_bytes()

    # tra bảng thuần
    assert han_viet("罗森") == "La Sâm"
    assert han_viet("张景四") == "Trương Cảnh Tứ"
    assert han_viet("筑基") == "Trúc Cơ"
    assert han_viet("卧羡冨栅") == "Ngoạ Tiện Phú Sách"

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
    assert not transliteration_suspect("安娜", "Anna", "person")
    assert not transliteration_suspect("罗森", "La Sâm", "person")
    assert transliteration_suspect("白衣少女", "cô gái áo trắng", "person")

    # cụm tiếng Anh dịch nghĩa (rác model trích tên) → chặn
    assert english_meaning("觉醒石", "Awakening Stone", "item")
    assert english_meaning("七班", "Class 7", "sect")
    assert english_meaning("魔法高中", "Magic High School", "place")
    assert english_meaning("浸泡过丧尸病毒的生肉", "Raw Meat Soaked in Zombie Virus", "item")
    # tiếng Việt (có dấu hoặc Hán-Việt không dấu) → giữ
    assert not english_meaning("觉醒石", "Giác Tỉnh Thạch", "item")
    assert not english_meaning("龙家", "Long gia", "sect")
    assert not english_meaning("派出所", "đồn cảnh sát", "place")
    # một từ ASCII (từ mượn / tên ngoại) và tên người Latin ≤3 từ → giữ
    assert not english_meaning("哥布林", "goblin", "other")
    assert not english_meaning("安娜", "Anna", "person")
    assert not english_meaning("托尼·斯塔克", "Tony Stark", "person")
    assert not english_meaning(None, None, None)


if __name__ == "__main__":
    main()
    print("OK — test_hanviet pass")
