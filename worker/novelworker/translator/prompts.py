"""Prompt dịch Trung → Việt cho tiểu thuyết mạng."""
from __future__ import annotations

import json
import re

# ponytail: chỉ chèn term thật sự xuất hiện trong metadata → gọn prompt, đỡ model "bịa";
# trần 80 term cho truyện nhiều thuật ngữ. Học từ GalTransl (selective injection).
MAX_TERMS_IN_PROMPT = 80
CHAPTER_TEMPERATURE = 0.1

# Một nguồn duy nhất cho prompt production, validator retry và evaluator. Chỉ giữ
# danh xưng tự xưng có mẫu đủ rõ để tránh bắt oan từ ghép như 下面 / 老夫老妻.
SELF_REFERENCE_RULES = (
    (r"老夫(?!老妻)", "老夫", "lão phu", ("lão phu", "lão già này", "lão đây")),
    (r"老子", "老子", "ông đây/lão tử", ("lão tử", "ông đây", "bố đây", "ta đây", "bố mày", "ông mày")),
    (r"本座", "本座", "bổn tọa", ("bổn tọa", "bản tọa")),
    (r"在下(?![面方风头边来去])", "在下", "tại hạ", ("tại hạ",)),
    (r"晚辈", "晚辈", "vãn bối", ("vãn bối", "hậu bối")),
    (r"贫道", "贫道", "bần đạo", ("bần đạo",)),
    (r"贫僧", "贫僧", "bần tăng", ("bần tăng",)),
    (r"哀家", "哀家", "ai gia", ("ai gia",)),
    (r"朕", "朕", "trẫm", ("trẫm",)),
    (r"微臣", "微臣", "vi thần", ("vi thần",)),
    (r"臣妾", "臣妾", "thần thiếp", ("thần thiếp",)),
)


def self_reference_omissions(zh: str, vi: str) -> list[str]:
    """Danh xưng tự xưng có trong nguồn nhưng mất dấu vết trong bản dịch."""
    low = vi.lower()
    return [f"{m.group(0)} thiếu dấu vết ({'/'.join(accepted)})"
            for pattern, _source, _prompt, accepted in SELF_REFERENCE_RULES
            if (m := re.search(pattern, zh))
            and not any(term in low for term in accepted)]


def _self_reference_prompt() -> str:
    return ", ".join(f"{source}→{target}" for _pattern, source, target, _accepted
                     in SELF_REFERENCE_RULES)

SYSTEM_STYLE = """Bạn là biên tập viên truyện dịch. Đọc metadata và đoạn mở đầu truyện Trung, lập HỒ SƠ VĂN PHONG ngắn để mọi chương sau dịch cùng một giọng. TUYỆT ĐỐI KHÔNG dịch nội dung.
Trả về DUY NHẤT một JSON object:
{"pov": "ngôi ba" | "ngôi nhất", "setting": "tu tiên cổ đại" | "đô thị hiện đại" | "huyền huyễn" | "lịch sử" | "võng du/hệ thống" | "xuyên không cổ đại" | ..., "han_viet": "đậm" | "vừa" | "nhạt", "tone": "vài từ tả nhịp văn (gọn/hài/lạnh/trang trọng/khẩu ngữ)"}
- "han_viet" đậm khi tu tiên/cổ trang thuần; nhạt khi đô thị hiện đại.
- Không thêm key khác, không tự đặt luật dịch, tên riêng, xưng hô hoặc thuật ngữ. Không markdown."""

SYSTEM_REVISE = """Bạn là biên tập viên bản dịch truyện Trung → Việt. Nhận danh sách CÂU LỖI trích từ bản dịch kèm lỗi bị đánh dấu. Sửa TỐI THIỂU từng câu: giữ nguyên nghĩa, giọng văn và mọi từ đúng; chỉ chữa lỗi rõ ràng, KHÔNG thêm ý, KHÔNG viết lại hoa mỹ hơn.
Cách sửa:
- Ưu tiên câu tiếng Việt trực tiếp, gọn và hợp với văn phong của các câu xung quanh.
- Không thay từ chỉ vì một danh sách quy tắc cố định. Các từ như "chẳng", "không", "chứ", "không khỏi", "bất giác" đều có thể đúng tùy câu.
- Chỉ lược từ đệm, từ lặp hoặc đổi cách diễn đạt khi câu cụ thể bị vấp, lặp nghĩa hoặc sai sắc thái.
- Không biến lời kể thành văn nghị luận; không thêm cảm thán, giải thích hoặc mức độ nhấn mạnh không có trong nguyên tác.
Trả về DUY NHẤT một mảng JSON, mỗi phần tử {"line": N, "new": "..."}:
- "line" là SỐ DÒNG được ghi kèm câu lỗi trong yêu cầu — hệ thống thay theo số dòng bằng máy.
- "new" là TOÀN BỘ dòng đã sửa, không thêm nội dung mới.
- Không chắc cách sửa thì BỎ QUA dòng đó. Không giải thích, không markdown."""

SYSTEM_ANALYZE = """Bạn là trợ lý phân tích tiểu thuyết mạng Trung. Đọc đoạn văn sau, TUYỆT ĐỐI KHÔNG dịch nội dung.
Liệt kê MỌI tên riêng / thuật ngữ quan trọng xuất hiện (người, môn phái, địa danh, chiêu thức, pháp bảo, cảnh giới tu luyện) kèm phiên âm Hán-Việt chuẩn. Với "person": "note" BẮT BUỘC mở đầu bằng giới tính "nam"/"nữ" — suy từ 他/她, 少年/少女, danh xưng (公子/姑娘/小姐), tên gọi; thật sự không suy ra được mới ghi "?". Sau giới tính ghi vai vế/quan hệ (sư huynh, tỷ tỷ, chưởng môn...) — bảng này quyết định xưng hô khi dịch.
TUYỆT ĐỐI KHÔNG trả PINYIN: 仓库 → "Cangku" là SAI, phải là "Thương Khố"; 迅雷 → "Xunlei" SAI, phải "Tấn Lôi"; 体育馆 → "Tiyuguan" SAI, phải "Thể Dục Quán". Cũng KHÔNG dịch nghĩa sang tiếng Anh: 觉醒石 → "Awakening Stone" SAI, phải "Giác Tỉnh Thạch"; 七班 → "Class 7" SAI, phải "Lớp Bảy".
Tên vốn viết bằng chữ Latin/tiếng Anh → "vi" giữ nguyên tiếng Anh. Tên ngoại quốc viết bằng chữ Hán (安娜, 杰克, 伦敦, 汉森) → "vi" là dạng Latin thông dụng (Anna, Jack, London, Hansen), KHÔNG phiên âm Hán-Việt, KHÔNG phiên âm gạch nối ("An-đê-ri-an", "Héc-nơ" là SAI). Từ mượn fantasy/game phiên âm bằng chữ Hán → "vi" là từ tiếng Anh quen thuộc (哥布林→goblin, 史莱姆→slime, 兽人→orc), KHÔNG phiên âm Hán-Việt kiểu "Ca Bố Lâm".
Trả về DUY NHẤT một JSON object, không giải thích, không văn bản thừa:
{"terms": [{"zh": "林松", "vi": "Lâm Tùng", "type": "person", "note": "nam, sư huynh"}]}
type ∈ person|place|sect|item|skill|other. Không có tên riêng → "terms": [].
"""

SYSTEM_METADATA = """Bạn là biên tập viên truyện dịch kỳ cựu. Dịch metadata truyện Trung sang tiếng Việt cho độc giả Việt.

title_vi — tên truyện như bản xuất bản ở VN: ngắn, êm tai, đúng chất truyện.
- LUẬT CỨNG: cả cụm NHẤT QUÁN — phiên âm Hán-Việt trọn cụm HOẶC dịch nghĩa trọn cụm, không nửa nọ nửa kia. Sai: 赤心巡天 → "Tâm Đỏ Tuần Thiên"; đúng: "Xích Tâm Tuần Thiên".
- Tu tiên/tiên hiệp/huyền huyễn/cổ đại/kiếm hiệp: MẶC ĐỊNH phiên âm Hán-Việt trọn cụm, kể cả chữ mang nghĩa (凡人修仙传 → "Phàm Nhân Tu Tiên", 斗破苍穹 → "Đấu Phá Thương Khung", 遮天 → "Già Thiên"). Chỉ dịch nghĩa khi cụm Hán-Việt quá trúc trắc/vô nghĩa.
- Đô thị/hệ thống/võng du hiện đại: dịch nghĩa tự nhiên (全民领主 → "Toàn Dân Lãnh Chúa").
- Phần vốn là Latin/tiếng Anh giữ nguyên ("Dragon Raja"). Không dịch word-by-word tối nghĩa.

author_vi — phiên âm Hán-Việt.

description_vi — lời giới thiệu bìa sách: dịch thoáng, mượt, giữ ngắt đoạn, không thêm cảm thán/slogan/lời kêu gọi đọc truyện mà gốc không có.
- Xưng hô phải KHỚP bản dịch chương (phong cổ): lời kể ngôi ba nam "hắn", nữ "nàng"; thoại/độc thoại mặc định "ta – ngươi", giữ vai vế khi có (bổn tọa, tại hạ, tiền bối...). CẤM trộn tôi/anh/em/cậu vào lời kể. Sai điển hình: "Cho tôi làm điệp viên?… các anh"; đúng: "Để ta làm gián điệp?… các ngươi".
- Câu ngắn theo nhịp Việt; một câu Trung dài nhiều dấu phẩy thường tách thành hai câu Việt.

Tên riêng (cả title lẫn description): tên Trung → phiên âm Hán-Việt trọn cụm, viết hoa từng âm; tên ngoại quốc viết bằng chữ Hán → dạng Latin thông dụng (安娜→Anna, 汉森→Hansen), KHÔNG phiên âm Hán-Việt, KHÔNG gạch nối ("An-đê-ri-an" là SAI). Có bảng thuật ngữ kèm theo thì phải theo ĐÚNG bảng.
Không để sót ký tự Hán trong bất kỳ giá trị nào; không chắc thì phiên âm Hán-Việt nhất quán.

Trả về DUY NHẤT một JSON object, không giải thích:
{"title_vi": "...", "author_vi": "...", "description_vi": "..."}"""

def build_style_line(style: dict | None) -> str | None:
    """Nén style bible JSON thành một dòng chỉ thị cho prompt dịch."""
    if not isinstance(style, dict) or not style:
        return None
    bits = []
    if style.get("pov"):
        bits.append(f"kể {style['pov']}")
    if style.get("setting"):
        bits.append(f"bối cảnh {style['setting']}")
    if style.get("han_viet"):
        bits.append(f"mức Hán-Việt {style['han_viet']}")
    if style.get("tone"):
        bits.append(f"nhịp văn {style['tone']}")
    return f"[Văn phong truyện — giữ xuyên suốt: {'; '.join(bits)}]" if bits else None


def _injectable(t: dict) -> bool:
    # term 'nghi sai' (phiên âm đáng ngờ) chỉ được vào prompt sau khi user duyệt
    return t.get("note") != "nghi sai" or t.get("approved") is True


MAIN_CHAPTER_DIRECTIVE = """Dịch đủ, đúng thứ tự từng đoạn; không bỏ, gộp, tóm tắt, thêm ý hay giải thích.
Viết tiếng Việt tự nhiên, gọn, không văn convert; giữ sắc thái thoại, mỉa mai, phủ định và câu hỏi.

Dùng phong cổ trong mọi trường hợp:
- Lời kể ngôi ba: nam là “hắn”, nữ là “nàng”.
- Thoại và độc thoại: mặc định “ta – ngươi”. Giữ đúng vai vế khi có: bổn tọa, tại hạ, vãn bối, tiền bối, đại nhân, huynh, tỷ...
- Không trộn tôi/anh/em/cậu/mày-tao với ta-ngươi.
- Danh xưng thân tộc theo lối cổ: 哥哥 là “ca ca”, 姐姐 “tỷ tỷ”, 妹妹 “muội muội”, 弟弟 “đệ đệ” — không dùng “anh trai/chị gái/em gái/em trai”.

Nhịp câu tiếng Việt, không bê nguyên dấu câu tiếng Trung: một câu Trung dài nhiều dấu phẩy thường phải tách thành hai câu Việt. Câu tiếng Việt hiếm khi nên dài quá 140 ký tự.

Tên người, địa danh, môn phái và danh xưng Trung: phiên âm Hán-Việt trọn cụm, viết hoa từng âm.
Tên ngoại quốc hoặc từ fantasy vốn là tên Latin: giữ dạng Latin quen thuộc; không phiên âm Hán-Việt hay gạch nối.
Kỹ năng, công pháp, cảnh giới, pháp bảo, vũ khí, vật phẩm có tên riêng: phiên âm Hán-Việt trọn cụm, viết hoa từng âm.
Danh từ, vật và địa điểm thông thường không phải tên riêng: dịch nghĩa tự nhiên.
Giữ nguyên ký hiệu, số, cấp bậc và định dạng gốc. Thuật ngữ game giữ quen tay người chơi: 冷却时间 là “CD”.
Chỉ trả bản dịch tiếng Việt; không xuất tiêu đề tự đặt, SUMMARY, JSON, markdown hay giải thích."""


SYSTEM_SYNOPSIS = """Bạn nén bối cảnh truyện thành một đoạn văn tiếng Việt không quá 600 ký tự.
Chỉ giữ sự kiện và trạng thái nhân vật chính; tên riêng phải giữ đúng theo glossary đã có.
Không bình luận, cảm nghĩ, markdown hay nhãn."""


MAIN_SYSTEM_TEMPLATE = """Bạn dịch tiểu thuyết Trung → Việt.

{main_directive}

Giữ đúng sắc thái tự xưng của nguyên văn khi xuất hiện: {self_reference_map}."""


def build_main_chapter_system() -> str:
    """Prompt production: luật xưng hô và nội dung; metadata có prompt riêng."""
    return MAIN_SYSTEM_TEMPLATE.format(
        main_directive=MAIN_CHAPTER_DIRECTIVE,
        self_reference_map=_self_reference_prompt(),
    )


def build_chapter_user(
    title_zh: str | None, content_zh: str,
    prev_summary: str | None = None,
    prev_tail: str | None = None,
    novel_line: str | None = None,
    register_line: str | None = None,
    style_line: str | None = None,
    synopsis: str | None = None,
) -> str:
    parts = []
    # tên truyện + thể loại → model chọn ĐÚNG register xưng hô (tu tiên: ta-ngươi;
    # đô thị: tôi-cậu) ngay từ câu đầu thay vì tự đoán từ 1 khúc chương
    if novel_line:
        parts.append(f"[Truyện: {novel_line}]")
    # chỉ thị xưng hô CHỐT từ tag thể loại (worker._register_directive) — quyết định
    # thay model, khỏi để nội dung game/mua bán làm nó nhầm sang tôi–anh
    if register_line:
        parts.append(register_line)
    # style bible của truyện — sinh 1 lần từ chương 1, giữ giọng xuyên suốt (Q1)
    if style_line:
        parts.append(style_line)
    if synopsis:
        parts.append(f"[Bối cảnh truyện đến nay: {synopsis}]")
    if prev_summary:
        parts.append(f"[Ngữ cảnh chương trước: {prev_summary}]")
    # đuôi bản dịch liền trước → nối mạch giọng văn + xưng hô qua ranh giới chương/chunk
    if prev_tail:
        parts.append(f"[Đoạn dịch LIỀN TRƯỚC — nối tiếp đúng giọng văn và xưng hô, KHÔNG dịch lại phần này:\n…{prev_tail}]")
    if title_zh:
        parts.append(f"Tiêu đề chương: {title_zh}")
    parts.append("Nội dung chương:\n" + content_zh)
    return "\n\n".join(parts)


def build_metadata_user(novel: dict, glossary_terms: list[dict] | None = None) -> str:
    payload = json.dumps(
        {
            "title_zh": novel.get("title_zh"),
            "author_zh": novel.get("author_zh"),
            "description_zh": novel.get("description_zh"),
            "genres_zh": novel.get("genres") or [],
        },
        ensure_ascii=False,
    )
    # dịch lại metadata khi glossary đã có → tên trong giới thiệu khớp tên trong chương
    # (lần dịch đầu glossary rỗng nên khối này thường không xuất hiện)
    src = f"{novel.get('title_zh') or ''}{novel.get('description_zh') or ''}"
    relevant = [
        t for t in (glossary_terms or [])
        if t.get("term_zh") and t.get("correct_vi") and _injectable(t) and t["term_zh"] in src
    ][:MAX_TERMS_IN_PROMPT]
    if relevant:
        lines = "\n".join(f"- {t['term_zh']} → {t['correct_vi']}" for t in relevant)
        payload += "\n\nBảng thuật ngữ BẮT BUỘC tuân theo khi dịch:\n" + lines
    return payload
