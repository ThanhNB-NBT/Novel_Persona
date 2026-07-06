"""Self-check prompts: chèn glossary chọn lọc + lắp ráp prompt chương (không mạng)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.translator.prompts import (
    MAX_TERMS_IN_PROMPT, build_chapter_system, build_chapter_user,
)


def main() -> None:
    terms = [
        {"term_zh": "林松", "correct_vi": "Lâm Tùng", "note": "nam, sư huynh"},
        {"term_zh": "苏雨", "correct_vi": "Tô Vũ", "wrong_vi": "Tô Vu"},
        {"term_zh": "不出现", "correct_vi": "Không Xuất Hiện"},  # không có trong chunk
        {"correct_vi": "chỉ mức tiếng Việt"},  # không có term_zh → job patch lo, bỏ qua
    ]

    # chỉ chèn term THẬT SỰ xuất hiện trong chunk; kèm note + cảnh báo wrong_vi
    sys_p = build_chapter_system(terms, "林松看着苏雨。")
    assert "林松 → Lâm Tùng" in sys_p and "[nam, sư huynh]" in sys_p
    assert "KHÔNG dịch thành 'Tô Vu'" in sys_p
    assert "不出现" not in sys_p

    # không có content đối chiếu → chèn mọi term có term_zh
    assert "不出现" in build_chapter_system(terms, "")

    # chunk không khớp term nào → không có khối glossary
    assert "Bảng thuật ngữ" not in build_chapter_system(terms, "无关内容")

    # trần số term trong prompt
    many = [{"term_zh": f"名{i}", "correct_vi": f"Danh {i}"} for i in range(200)]
    chunk = "".join(t["term_zh"] for t in many)
    injected = build_chapter_system(many, chunk)
    assert injected.count("→ Danh") == MAX_TERMS_IN_PROMPT

    # build_chapter_user: đủ 4 phần đúng thứ tự; phần thiếu thì không chèn nhãn thừa
    u = build_chapter_user("第一章", "内容", prev_summary="tóm tắt",
                           prev_tail="…đuôi dịch trước", novel_line="Truyện A — thể loại: Tiên hiệp")
    for i in range(len(order := ["[Truyện:", "[Ngữ cảnh chương trước:",
                                 "[Đoạn dịch LIỀN TRƯỚC", "Tiêu đề chương:", "Nội dung chương:"]) - 1):
        assert u.index(order[i]) < u.index(order[i + 1]), order[i]
    bare = build_chapter_user(None, "内容")
    assert bare == "Nội dung chương:\n内容"


if __name__ == "__main__":
    main()
    print("OK — test_prompts pass")
