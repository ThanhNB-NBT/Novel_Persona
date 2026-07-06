"""Self-check dedup Phase 2: chuẩn hoá khoá trùng + chọn bản canonical."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.sync import _pick_canonical, dedup_key


def main() -> None:
    # cùng truyện, khác định dạng (space/dấu câu/full-width) → CÙNG key
    assert dedup_key("全职法师", "乱") == dedup_key(" 全职法师 ", "乱")
    assert dedup_key("全职法师！", "乱") == dedup_key("全职法师", "乱")
    # chữ Hán được giữ (là \w unicode) → key không rỗng
    assert dedup_key("全职法师", "乱").split("|")[0] == "全职法师"
    # khác tác giả → khác key (truyện cùng tên khác người viết)
    assert dedup_key("斗破苍穹", "天蚕土豆") != dedup_key("斗破苍穹", "某人")
    # thiếu tác giả không nổ
    assert dedup_key("孤本", None) == "孤本|"

    # canonical: meta_priority nhỏ nhất thắng
    prio = {1: 10, 2: 20}  # nguồn 1 ưu tiên cao hơn
    rows = [
        {"id": 100, "source_id": 2, "chapter_count_source": 999},
        {"id": 101, "source_id": 1, "chapter_count_source": 50},
    ]
    assert _pick_canonical(rows, prio)["id"] == 101  # prio thắng dù ít chương hơn

    # hoà meta_priority → nhiều chương hơn thắng
    prio2 = {1: 10, 2: 10}
    rows2 = [
        {"id": 200, "source_id": 1, "chapter_count_source": 50},
        {"id": 201, "source_id": 2, "chapter_count_source": 3000},
    ]
    assert _pick_canonical(rows2, prio2)["id"] == 201

    # nguồn không có trong prio → 999 (thua)
    rows3 = [
        {"id": 300, "source_id": 9, "chapter_count_source": 5000},  # lạ
        {"id": 301, "source_id": 1, "chapter_count_source": 1},
    ]
    assert _pick_canonical(rows3, {1: 10})["id"] == 301

    # chapter_count_source None không nổ
    rows4 = [
        {"id": 400, "source_id": 1, "chapter_count_source": None},
        {"id": 401, "source_id": 1, "chapter_count_source": 10},
    ]
    assert _pick_canonical(rows4, {1: 10})["id"] == 401


if __name__ == "__main__":
    main()
    print("OK — dedup test pass")
