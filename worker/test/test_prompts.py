"""Self-check prompts: chèn glossary chọn lọc + lắp ráp prompt chương (không mạng)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.translator.prompts import (
    MAX_TERMS_IN_PROMPT, build_chapter_system, build_main_chapter_system,
    build_reference_chapter_system,
    build_chapter_user, build_metadata_user,
)


def main() -> None:
    terms = [
        {"term_zh": "林松", "correct_vi": "Lâm Tùng", "note": "nam, sư huynh", "term_type": "person"},
        {"term_zh": "苏雨", "correct_vi": "Tô Vũ", "wrong_vi": "Tô Vu"},
        {"term_zh": "不出现", "correct_vi": "Không Xuất Hiện"},  # không có trong chunk
        {"correct_vi": "chỉ mức tiếng Việt"},  # không có term_zh → job patch lo, bỏ qua
    ]

    # chỉ chèn term THẬT SỰ xuất hiện trong chunk; kèm note + cảnh báo wrong_vi
    sys_p = build_chapter_system(terms, "林松看着苏雨。")
    assert "林松 → Lâm Tùng" in sys_p and "[nam, sư huynh]" in sys_p
    assert "KHÔNG dịch thành 'Tô Vu'" in sys_p
    assert "不出现" not in sys_p
    # person tách vào BẢNG NHÂN VẬT (chọn xưng hô), term thường ở khối thuật ngữ
    assert "BẢNG NHÂN VẬT — tra bảng này" in sys_p
    assert sys_p.index("林松") < sys_p.index("Bảng thuật ngữ") < sys_p.index("苏雨")
    # chunk chỉ có term thường → không chèn khối nhân vật rỗng
    assert "BẢNG NHÂN VẬT — tra bảng này" not in build_chapter_system(terms, "苏雨来了。")

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

    # build_metadata_user: chỉ chèn term xuất hiện trong title/description; không glossary → JSON trần
    novel = {"title_zh": "林松传", "description_zh": "讲述林松的故事", "author_zh": "作者", "genres": []}
    meta = build_metadata_user(novel, terms)
    assert "林松 → Lâm Tùng" in meta and "苏雨" not in meta
    assert "Bảng thuật ngữ" not in build_metadata_user(novel)
    reference = build_reference_chapter_system(terms, "林松看着苏雨。")
    assert "CHIẾN LƯỢC DỊCH CHÍNH" in reference
    assert "SUMMARY và GLOSSARY_JSON" in reference
    main = build_main_chapter_system(terms, "林松看着苏雨。")
    assert "KẾT HỢP REFERENCE + V2" in main
    assert "Xác định người nói" in main
    assert "Không gộp hai đoạn" in main


if __name__ == "__main__":
    main()
    print("OK — test_prompts pass")
