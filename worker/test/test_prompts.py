"""Self-check prompts: prompt chương GỌN (không glossary) + metadata (vẫn có glossary)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.translator.prompts import (
    build_main_chapter_system, build_chapter_user, build_metadata_user,
)


def main() -> None:
    terms = [
        {"term_zh": "林松", "correct_vi": "Lâm Tùng", "note": "nam, sư huynh", "term_type": "person"},
        {"term_zh": "苏雨", "correct_vi": "Tô Vũ", "wrong_vi": "Tô Vu"},
    ]

    # Prompt chương GỌN (nhánh B G3): chỉ luật xưng hô + nội dung. KHÔNG chèn glossary
    # Không bắt model xuất SUMMARY/GLOSSARY_JSON.
    sys_p = build_main_chapter_system()
    assert "林松" not in sys_p and "Bảng thuật ngữ" not in sys_p and "BẢNG NHÂN VẬT" not in sys_p
    # lệnh CŨ bắt model xuất SUMMARY/GLOSSARY_JSON đã gỡ (giờ chỉ còn lệnh CẤM xuất)
    assert "xuất đúng hai dòng cuối" not in sys_p
    assert "vẫn xuất SUMMARY và GLOSSARY_JSON" not in sys_p
    assert "Chỉ trả bản dịch tiếng Việt" in sys_p
    assert "ta – ngươi" in sys_p
    assert "Tên ngoại quốc" in sys_p
    assert "vật phẩm có tên riêng" in sys_p
    assert "KẾT HỢP REFERENCE + V2" not in sys_p
    assert "Cao Đống" not in sys_p

    # build_chapter_user: các phần đúng thứ tự; phần thiếu thì không chèn nhãn thừa.
    # (Hàm vẫn nhận prev_summary/synopsis/prev_tail cho eval/legacy; production G3 bỏ không truyền.)
    u = build_chapter_user("第一章", "内容", prev_summary="tóm tắt", synopsis="bối cảnh",
                           prev_tail="…đuôi dịch trước", novel_line="Truyện A — thể loại: Tiên hiệp")
    for i in range(len(order := ["[Truyện:", "[Bối cảnh truyện đến nay:", "[Ngữ cảnh chương trước:",
                                 "[Đoạn dịch LIỀN TRƯỚC", "Tiêu đề chương:", "Nội dung chương:"]) - 1):
        assert u.index(order[i]) < u.index(order[i + 1]), order[i]
    bare = build_chapter_user(None, "内容")
    assert bare == "Nội dung chương:\n内容"
    assert "[Bối cảnh truyện đến nay:" not in build_chapter_user(None, "内容", prev_summary="tóm tắt")

    # build_metadata_user VẪN chèn glossary (title/desc khớp tên trong chương); chỉ chèn
    # term xuất hiện trong title/description → JSON trần khi không có term khớp.
    novel = {"title_zh": "林松传", "description_zh": "讲述林松的故事", "author_zh": "作者", "genres": []}
    meta = build_metadata_user(novel, terms)
    assert "林松 → Lâm Tùng" in meta and "苏雨" not in meta
    assert "Bảng thuật ngữ" not in build_metadata_user(novel)
    # term nghi sai chưa duyệt không được lọt vào prompt metadata
    ngo = {"term_zh": "林松", "correct_vi": "người họ Lâm", "note": "nghi sai", "approved": False}
    assert "người họ Lâm" not in build_metadata_user(novel, [ngo])
    ngo["approved"] = True
    assert "người họ Lâm" in build_metadata_user(novel, [ngo])


if __name__ == "__main__":
    main()
    print("OK — test_prompts pass")
