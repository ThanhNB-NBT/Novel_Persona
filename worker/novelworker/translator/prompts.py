"""Prompt dịch Trung → Việt cho tiểu thuyết mạng."""
from __future__ import annotations

import json

SYSTEM_CHAPTER = """Bạn là dịch giả tiểu thuyết mạng Trung → Việt chuyên nghiệp.

Quy tắc:
- Dịch tự nhiên, văn phong tiểu thuyết mạng Việt Nam, KHÔNG dịch word-by-word kiểu convert.
- Tên người, môn phái, địa danh, chiêu thức: dùng phiên âm Hán-Việt (林松 → Lâm Tùng), TUYỆT ĐỐI không dịch nghĩa tên riêng.
- Giữ xưng hô phù hợp thể loại (tu tiên/cổ đại: ta–ngươi, huynh–đệ; đô thị hiện đại: tôi–cậu/anh–em).
- Giữ nguyên cấu trúc đoạn văn (số đoạn tương ứng bản gốc).
- Không thêm lời bình, không tóm tắt, không bỏ sót câu.
{glossary_block}
Sau bản dịch, trên dòng cuối cùng, xuất JSON danh sách tên riêng phát hiện trong chương theo định dạng:
GLOSSARY_JSON: [{{"zh": "林松", "vi": "Lâm Tùng", "type": "person"}}]
"""

GLOSSARY_TEMPLATE = """
Bảng thuật ngữ BẮT BUỘC tuân theo (từ gốc → bản dịch đúng):
{terms}
"""

SYSTEM_METADATA = """Bạn là dịch giả tiểu thuyết mạng Trung → Việt. Dịch metadata truyện sau sang tiếng Việt.
Tên truyện dịch hay, tự nhiên như tên truyện xuất bản ở VN. Tên tác giả phiên âm Hán-Việt.
Thể loại dùng thuật ngữ quen thuộc với độc giả VN (玄幻→Huyền huyễn, 都市→Đô thị, 言情→Ngôn tình...).
Trả về DUY NHẤT một JSON object, không giải thích:
{"title_vi": "...", "author_vi": "...", "description_vi": "...", "genres_vi": ["..."]}"""

SYSTEM_COMMENTS = """Dịch các bình luận độc giả sau từ tiếng Trung sang tiếng Việt, giữ giọng điệu tự nhiên
như bình luận trên mạng (có thể giữ meme/teencode hợp ngữ cảnh). Trả về DUY NHẤT JSON:
{"translations": [{"id": "...", "vi": "..."}]}"""


def build_chapter_system(glossary_terms: list[dict]) -> str:
    if glossary_terms:
        lines = "\n".join(
            f"- {t.get('term_zh') or '(?)'} → {t['correct_vi']}"
            + (f" (KHÔNG dịch thành '{t['wrong_vi']}')" if t.get("wrong_vi") else "")
            for t in glossary_terms
        )
        block = GLOSSARY_TEMPLATE.format(terms=lines)
    else:
        block = ""
    return SYSTEM_CHAPTER.format(glossary_block=block)


def build_chapter_user(title_zh: str | None, content_zh: str, prev_summary: str | None = None) -> str:
    parts = []
    if prev_summary:
        parts.append(f"[Ngữ cảnh chương trước: {prev_summary}]")
    if title_zh:
        parts.append(f"Tiêu đề chương: {title_zh}")
    parts.append("Nội dung chương:\n" + content_zh)
    return "\n\n".join(parts)


def build_metadata_user(novel: dict) -> str:
    return json.dumps(
        {
            "title_zh": novel.get("title_zh"),
            "author_zh": novel.get("author_zh"),
            "description_zh": novel.get("description_zh"),
            "genres_zh": novel.get("genres") or [],
        },
        ensure_ascii=False,
    )


def build_comments_user(comments: list[dict]) -> str:
    return json.dumps(
        [{"id": str(c["id"]), "zh": c["content_zh"]} for c in comments],
        ensure_ascii=False,
    )
