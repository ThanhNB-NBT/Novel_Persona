"""Prompt dịch Trung → Việt cho tiểu thuyết mạng."""
from __future__ import annotations

import json

GLOSSARY_TEMPLATE = """
{persons_block}Bảng thuật ngữ BẮT BUỘC tuân theo (từ gốc → bản dịch đúng):
{terms}
"""

PERSONS_TEMPLATE = """BẢNG NHÂN VẬT — tra bảng này để chọn xưng hô đúng giới tính/vai vế; tên dịch BẮT BUỘC theo bảng:
{persons}

"""

# ponytail: chỉ chèn term thật sự xuất hiện trong đoạn → gọn prompt, đỡ model "bịa";
# trần 80 term/đoạn cho truyện nhiều thuật ngữ. Học từ GalTransl (selective injection).
MAX_TERMS_IN_PROMPT = 80

SYSTEM_STYLE = """Bạn là biên tập viên truyện dịch. Đọc metadata và đoạn mở đầu truyện Trung, lập HỒ SƠ VĂN PHONG ngắn để mọi chương sau dịch cùng một giọng. TUYỆT ĐỐI KHÔNG dịch nội dung.
Trả về DUY NHẤT một JSON object:
{"pov": "ngôi ba" | "ngôi nhất", "setting": "tu tiên cổ đại" | "đô thị hiện đại" | "huyền huyễn" | "lịch sử" | "võng du/hệ thống" | "xuyên không cổ đại" | ..., "han_viet": "đậm" | "vừa" | "nhạt", "tone": "vài từ tả nhịp văn (gọn/hài/lạnh/trang trọng/khẩu ngữ)"}
- "han_viet" đậm khi tu tiên/cổ trang thuần; nhạt khi đô thị hiện đại.
- Không thêm key khác, không tự đặt luật dịch, tên riêng, xưng hô hoặc thuật ngữ. Không markdown."""

SYSTEM_REVISE = """Bạn là biên tập viên bản dịch truyện Trung → Việt. Nhận danh sách CÂU LỖI trích từ bản dịch kèm lỗi bị đánh dấu. Sửa TỐI THIỂU từng câu: giữ nguyên nghĩa, giọng văn và mọi từ đúng; chỉ chữa đúng lỗi nêu ra, KHÔNG thêm ý, KHÔNG viết lại hoa mỹ hơn.
Cách sửa các lỗi thường gặp:
- "chẳng" → "không" (giữ "chẳng lẽ/chẳng qua" cố ý).
- Chữ đệm thừa cuối câu ("chăng", "chứ", "kia", "nha") → bỏ, hoặc diễn đạt gọn ("ngài cần phu nhân chăng?" → "ngài có cần phu nhân không?").
- Lỗi convert: "không khỏi" → "bất giác"; "căn bản là" → "vốn dĩ"; "trên thực tế" → "thật ra"; "cười một cái" → "bật cười".
- Câu lặp cùng một từ sát nhau → lược bớt hoặc thay từ đồng nghĩa cho xuôi.
Trả về DUY NHẤT một mảng JSON, mỗi phần tử {"line": N, "new": "..."}:
- "line" là SỐ DÒNG được ghi kèm câu lỗi trong yêu cầu — hệ thống thay theo số dòng bằng máy.
- "new" là TOÀN BỘ dòng đã sửa, không thêm nội dung mới.
- Không chắc cách sửa thì BỎ QUA dòng đó. Không giải thích, không markdown."""

SYSTEM_ANALYZE = """Bạn là trợ lý phân tích tiểu thuyết mạng Trung. Đọc đoạn văn sau, TUYỆT ĐỐI KHÔNG dịch nội dung.
Liệt kê MỌI tên riêng / thuật ngữ quan trọng xuất hiện (người, môn phái, địa danh, chiêu thức, pháp bảo, cảnh giới tu luyện) kèm phiên âm Hán-Việt chuẩn. Với "person": "note" BẮT BUỘC mở đầu bằng giới tính "nam"/"nữ" — suy từ 他/她, 少年/少女, danh xưng (公子/姑娘/小姐), tên gọi; thật sự không suy ra được mới ghi "?". Sau giới tính ghi vai vế/quan hệ (sư huynh, tỷ tỷ, chưởng môn...) — bảng này quyết định xưng hô khi dịch.
Tên vốn viết bằng chữ Latin/tiếng Anh → "vi" giữ nguyên tiếng Anh. Tên ngoại quốc viết bằng chữ Hán (安娜, 杰克, 伦敦, 汉森) → "vi" là dạng Latin thông dụng (Anna, Jack, London, Hansen), KHÔNG phiên âm Hán-Việt, KHÔNG phiên âm gạch nối ("An-đê-ri-an", "Héc-nơ" là SAI). Từ mượn fantasy/game phiên âm bằng chữ Hán → "vi" là từ tiếng Anh quen thuộc (哥布林→goblin, 史莱姆→slime, 兽人→orc), KHÔNG phiên âm Hán-Việt kiểu "Ca Bố Lâm".
Trả về DUY NHẤT một JSON object, không giải thích, không văn bản thừa:
{"terms": [{"zh": "林松", "vi": "Lâm Tùng", "type": "person", "note": "nam, sư huynh"}]}
type ∈ person|place|sect|item|skill|other. Không có tên riêng → "terms": [].
"""

SYSTEM_METADATA = """Bạn là biên tập viên truyện dịch kỳ cựu. Dịch metadata truyện Trung sau sang tiếng Việt cho độc giả Việt.

- title_vi: dịch như tên truyện xuất bản ở VN — ngắn, êm tai, gợi đúng chất truyện.
  · LUẬT CỨNG: KHÔNG nửa dịch nghĩa nửa phiên âm trong CÙNG một tên. Cả cụm phải NHẤT QUÁN — hoặc phiên âm Hán-Việt trọn cụm, hoặc dịch nghĩa trọn cụm. Sai điển hình: 赤心巡天 → "Tâm Đỏ Tuần Thiên" (nửa nghĩa "Tâm Đỏ" + nửa âm "Tuần Thiên"); ĐÚNG → "Xích Tâm Tuần Thiên" (phiên âm trọn).
  · Tu tiên/tiên hiệp/huyền huyễn/cổ đại/kiếm hiệp → MẶC ĐỊNH phiên âm Hán-Việt TRỌN cụm, kể cả chữ mang nghĩa (凡人修仙传 → "Phàm Nhân Tu Tiên", 斗破苍穹 → "Đấu Phá Thương Khung", 遮天 → "Già Thiên", 赤心巡天 → "Xích Tâm Tuần Thiên"). Chỉ dịch nghĩa khi cụm Hán-Việt nghe quá trúc trắc/vô nghĩa với độc giả.
  · Đô thị/hệ thống/võng du hiện đại → dịch NGHĨA tự nhiên (全民领主 → "Toàn Dân Lãnh Chúa" hoặc "Thời Đại Lãnh Chúa" tùy cái nào xuôi hơn); tránh chuỗi Hán-Việt trúc trắc khó hiểu.
  · Phần tên gốc Latin/tiếng Anh giữ nguyên (vd "Dragon Raja"). KHÔNG dịch word-by-word tối nghĩa.
- author_vi: phiên âm Hán-Việt.
- description_vi: dịch thoáng, mượt như lời giới thiệu bìa sách; giữ ngắt đoạn; BỎ rác nguồn ("本书又名...", "求收藏/求推荐/求月票", link, tag site, số liệu điểm/click). Không tự thêm cảm thán, slogan hoặc lời kêu gọi đọc truyện khi gốc không có.
- Tên riêng trong title/description: tên Trung → phiên âm Hán-Việt; tên ngoại quốc viết bằng chữ Hán → dạng Latin thông dụng (安娜→Anna, 汉森→Hansen), KHÔNG phiên âm Hán-Việt, KHÔNG phiên âm gạch nối ("An-đê-ri-an", "Héc-nơ" là SAI). Có bảng thuật ngữ kèm theo thì tên phải dịch ĐÚNG theo bảng.
- genres_vi: thuật ngữ quen thuộc (玄幻→Huyền huyễn, 都市→Đô thị, 修真/仙侠→Tiên hiệp, 言情→Ngôn tình, 网游→Võng du, 系统→Hệ thống, 无限流→Vô hạn lưu...).
- Không để nguyên ký tự Hán trong bất kỳ giá trị nào. Nếu không chắc một tên riêng, phiên âm Hán-Việt nhất quán thay vì chép nguyên chữ Hán.

Trả về DUY NHẤT một JSON object, không giải thích:
{"title_vi": "...", "author_vi": "...", "description_vi": "...", "genres_vi": ["..."]}"""

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


def _build_glossary_block(glossary_terms: list[dict], content_zh: str = "") -> str:
    # Chỉ giữ term có chữ Trung xuất hiện trong đoạn đang dịch (nếu có đoạn để đối chiếu).
    # Term không có term_zh (góp ý chỉ mức tiếng Việt) do job "patch" xử lý bằng string-replace.
    relevant = [
        t for t in glossary_terms
        if t.get("term_zh") and (not content_zh or t["term_zh"] in content_zh)
    ][:MAX_TERMS_IN_PROMPT]
    if relevant:
        def line(t: dict) -> str:
            return (
                f"- {t['term_zh']} → {t['correct_vi']}"
                + (f" [{t['note']}]" if t.get("note") else "")
                # narrator reference: người kể gọi CỐ ĐỊNH một cách, model không tự đổi
                + (f" [người kể gọi: {t['narrator_term']}]" if t.get("narrator_term") else "")
                + (f" (KHÔNG dịch thành '{t['wrong_vi']}')" if t.get("wrong_vi") else "")
            )
        # nhân vật tách khối riêng: model tra giới tính/vai vế khi chọn xưng hô
        persons = [t for t in relevant if t.get("term_type") == "person"]
        others = [t for t in relevant if t.get("term_type") != "person"]
        persons_block = (
            PERSONS_TEMPLATE.format(persons="\n".join(line(t) for t in persons))
            if persons else ""
        )
        block = GLOSSARY_TEMPLATE.format(
            persons_block=persons_block,
            terms="\n".join(line(t) for t in others) if others else "(không có)",
        )
    else:
        block = ""
    return block


MAIN_CHAPTER_DIRECTIVE = """
[CHIẾN LƯỢC DỊCH PRODUCTION — KẾT HỢP REFERENCE + V2]

1. BẢO TOÀN NỘI DUNG — ưu tiên cao nhất
- Dịch đủ mọi đoạn, mọi tin tức, mọi câu và mọi mệnh đề theo đúng thứ tự.
- Không gộp hai đoạn, không bỏ ý, không tóm tắt danh sách, không tự thêm chi tiết.
- Không tự đổi sắc thái câu hỏi, phủ định, nghi vấn, mỉa mai hoặc mức độ chắc chắn.
- 追查 là điều tra/truy tìm; không dịch thành truy sát nếu không có ý giết hoặc tiêu diệt.

2. HIỂU NGỮ CẢNH TRƯỚC KHI VIẾT
- Xác định người nói, người nghe, giới tính, quan hệ và vai vế trước mỗi câu thoại.
- Giữ nhất quán cách xưng hô xuyên suốt truyện; không thay đổi chỉ vì câu riêng lẻ.
- Phân biệt người xuyên không với thân thể/tiền thân và các nhân vật trùng tên.

3. CÁCH VIẾT CHO NGƯỜI VIỆT ĐỌC
- Viết tiếng Việt tự nhiên, gọn và rõ, nhưng không phóng tác hoặc làm văn hoa hơn nguyên tác.
- Không ghép nửa dịch nghĩa nửa phiên âm trong một từ/cụm. 鲜血 trong cảnh cơ thể chảy/phun/trào máu → "máu tươi", tuyệt đối không "tươi Huyết"; nếu là TÊN vật phẩm/nguyên liệu/đạo cụ được định danh thì "Tiên Huyết" là đúng.
- Tránh văn convert: không lạm dụng "chẳng", chữ đệm cuối câu, "không khỏi", "trên thực tế", "tổng cảm thấy", "cười/nhìn một cái"; không lặp dày cùng một đại từ trong một câu.
- Giữ nhịp hội thoại và sắc thái thể loại; không tự thêm từ đệm, cảm thán hoặc cảm xúc.
- Giữ nguyên ký hiệu/ngoặc thể hiện tên dị năng, vật phẩm và thuật ngữ nếu bản gốc dùng chúng.
- Tên và thuật ngữ trong glossary bắt buộc dùng đúng một cách viết.

Nếu input có tiêu đề thì dịch tiêu đề; nếu không có thì không tự đặt tiêu đề.
Sau phần nội dung vẫn xuất SUMMARY và GLOSSARY_JSON đúng định dạng hệ thống để worker
duy trì ngữ cảnh chương sau; không xuất giải thích hay markdown.
"""


MAIN_SYSTEM_TEMPLATE = """Bạn là dịch giả tiểu thuyết mạng Trung → Việt chuyên nghiệp.
Mục tiêu là tạo bản dịch để người Việt đọc liền mạch: đúng nghĩa, đủ nội dung,
nhất quán xuyên truyện và tự nhiên vừa đủ; không phóng tác.

{glossary_block}

{main_directive}

QUY TẮC XƯNG HÔ BỔ SUNG
- Trước mỗi câu thoại, xác định người nói, người nghe, giới tính, quan hệ và vai vế.
- Giữ một cách xưng hô ổn định cho cùng một cặp nhân vật; chỉ đổi khi quan hệ thật sự đổi.
- Lời kể phải nhất quán với ngôi kể và giới tính; không tự đổi người kể giữa các đoạn.
- Giữ sắc thái tự xưng của nguyên văn, không san phẳng thành "ta": 老夫→lão phu, 老子→ông đây/lão tử theo giọng, 本座→bổn tọa, 在下→tại hạ, 晚辈→vãn bối, 贫道→bần đạo, 贫僧→bần tăng, 哀家→ai gia, 朕→trẫm, 微臣→vi thần, 臣妾→thần thiếp. 本尊 phải dịch theo nghĩa câu: bản tôn khi tự xưng, chân thân/bản thể khi đối lập với phân thân.
- KIỂM TRA BẮT BUỘC TRƯỚC KHI TRẢ KẾT QUẢ: nếu câu gốc có 本座/在下/晚辈 trong lời thoại hoặc độc thoại, bản dịch phải giữ đúng dấu vết tương ứng (bổn tọa/tại hạ/vãn bối hoặc biến thể tự nhiên cùng nghĩa). Không được lược bỏ, đổi thành tên nhân vật, hay rút thành "ta". Ví dụ: 本座今日便要取你性命→"Bổn tọa hôm nay sẽ lấy mạng ngươi"; 在下告辞→"Tại hạ xin cáo từ"; 晚辈拜见前辈→"Vãn bối bái kiến tiền bối".
- Tên người, địa danh, môn phái, dị năng, vật phẩm và cảnh giới phải theo glossary.

ĐỊNH DẠNG BẮT BUỘC
- Dịch đủ nội dung theo đúng thứ tự; không bỏ, gộp, tóm tắt hoặc thêm ý.
- Nếu input có tiêu đề, dòng đầu là tiêu đề đã dịch; nếu không có, không tự đặt tiêu đề.
- Sau phần dịch xuất đúng hai dòng cuối: SUMMARY: ... và GLOSSARY_JSON: [...].
- Không xuất giải thích, markdown hoặc nội dung ngoài bản dịch và hai dòng metadata.
"""


def build_main_chapter_system(glossary_terms: list[dict], content_zh: str = "") -> str:
    """Prompt production độc lập, dùng glossary chung nhưng không nối prompt legacy."""
    return MAIN_SYSTEM_TEMPLATE.format(
        glossary_block=_build_glossary_block(glossary_terms, content_zh),
        main_directive=MAIN_CHAPTER_DIRECTIVE,
    )


def build_chapter_user(
    title_zh: str | None, content_zh: str,
    prev_summary: str | None = None,
    prev_tail: str | None = None,
    novel_line: str | None = None,
    register_line: str | None = None,
    style_line: str | None = None,
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
        if t.get("term_zh") and t.get("correct_vi") and t["term_zh"] in src
    ][:MAX_TERMS_IN_PROMPT]
    if relevant:
        lines = "\n".join(f"- {t['term_zh']} → {t['correct_vi']}" for t in relevant)
        payload += "\n\nBảng thuật ngữ BẮT BUỘC tuân theo khi dịch:\n" + lines
    return payload
