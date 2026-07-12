"""Consumer hàng đợi dịch: metadata / chapter / patch / audit."""
from __future__ import annotations

import json
import logging
import re
import threading
import time

from .. import db
from ..config import settings
from . import hanviet, prompts
from . import providers
from .providers import build_chain

log = logging.getLogger(__name__)

# nhận cả khi model bọc mảng trong ```json fence (hay gặp) — trước đây trượt là
# cả cục JSON rơi nguyên vào nội dung chương (lỗi "phình 5-6x" trong quality report)
GLOSSARY_LINE = re.compile(
    r"GLOSSARY_JSON:\s*(?:```(?:json)?\s*)?(\[.*\])\s*(?:```)?\s*$", re.S)

# Lặp CỤM 2+ từ liền nhau ("cuối câu cuối câu") = model nói lắp; KHÔNG bắt lặp 1 từ
# vì tiếng Việt có từ láy hợp lệ ("xanh xanh", "từ từ"). Dùng chung với lệnh quality.
DUP_PHRASE = re.compile(r"(?i)\b([\wÀ-ỹ]+(?:\s+[\wÀ-ỹ]+)+)\s+\1\b")


def _clean_output(text: str) -> str:
    """Dọn rác model hay chèn vào bản dịch — chạy sau khi đã bóc GLOSSARY/SUMMARY."""
    i = text.find("GLOSSARY_JSON")
    if i != -1:
        text = text[:i]  # regex trượt (định dạng lạ) → cắt thô: thà mất bảng tên còn hơn dính JSON
    text = re.sub(r"^```\w*\s*$", "", text, flags=re.M)  # code fence sót
    text = text.replace("**", "")  # markdown đậm
    # gộp cụm nói lắp: "cuối câu cuối câu" → "cuối câu"; lặp lại vì lặp 3+ lần gộp 1 lượt còn sót
    while True:
        new = DUP_PHRASE.sub(r"\1", text)
        if new == text:
            break
        text = new
    return text.strip()


def _strip_meta(text: str) -> str:
    """Bỏ khối GLOSSARY_JSON + dòng SUMMARY để đo chất lượng trên phần THÂN bản dịch
    (fuse đo trên res.text thô sẽ lệch độ dài vì phần meta có thể tới 1-2KB)."""
    m = GLOSSARY_LINE.search(text)
    if m:
        text = text[: m.start()]
    i = text.find("GLOSSARY_JSON")
    if i != -1:
        text = text[:i]
    body, _ = _pop_summary(text.rstrip())
    return body


class MissingContentError(RuntimeError):
    pass


def _is_unique_violation(exc: Exception) -> bool:
    return getattr(exc, "code", None) == "23505" or "duplicate key" in str(exc).lower()


def _keep_job_lock(job_id: int, worker_id: str, stop: threading.Event, interval: float) -> None:
    while not stop.wait(interval):
        try:
            db.refresh_job_lock(job_id, worker_id)
        except Exception:
            log.exception("Job #%s: không gia hạn được lease", job_id)


HAN_CHARS = re.compile(r"[一-鿿㐀-䶿]")


def han_ratio(text: str) -> float:
    """Tỷ lệ ký tự Hán trong bản dịch — dùng làm cầu chì chất lượng."""
    return len(HAN_CHARS.findall(text)) / max(len(text), 1)


# Hư từ Hán-Việt dày đặc = model PHIÊN ÂM từng chữ thay vì dịch nghĩa (novel 1052:
# "chủ phong cao sủng nhập vân, thường niên vân vụ liễu nhiễu" — 0% chữ Hán nên các
# fuse khác đều lọt). Văn Việt thật các từ này hiếm ("mục đích/giai đoạn/chi phí"
# chỉ vài lần/chương) → mật độ cao là phiên âm chắc chắn.
_TRANSLIT_MARKERS = re.compile(
    r"\b(?:(?<!mục )đích(?! thân| thị| đáng)|chi(?! phí| tiêu| tiết| nhánh)"
    r"|hữu(?! ích| hạn| nghị| dụng)|(?<!quy )(?<!nguyên )tắc|giai(?! đoạn| nhân| điệu)"
    r"|(?<!hài )(?<!nữ )nhi(?! đồng)|nãi|liễu|chúng nhân|khai khẩu|nhất cá)\b", re.I)


def _translit_ratio(vi: str) -> float:
    words = len(vi.split())
    return len(_TRANSLIT_MARKERS.findall(vi)) / max(words, 1)


# Check này giờ nằm TRONG fuse production (chặn + retry) nên phía gốc phải loại
# từ ghép trùng mặt chữ (在下面 "ở dưới", 老夫老妻 "vợ chồng già"...) và phía dịch
# phải nhận đủ biến thể hợp lệ — dính oan là đốt retry/fallback cả chunk.
SELF_REFERENCE_CONSTRAINTS: list[tuple[re.Pattern, tuple[str, ...]]] = [
    (re.compile(r"老夫(?!老妻)"), ("lão phu", "lão già này", "lão đây")),
    (re.compile(r"老子"), ("lão tử", "ông đây", "bố đây", "ta đây", "bố mày", "ông mày", "lão đây")),
    (re.compile(r"本座"), ("bổn tọa", "bản tọa")),
    # 本尊 còn nghĩa "chân thân/bản thể" (phân thân–chân thân) — không phải tự xưng
    (re.compile(r"本尊"), ("bản tôn", "bổn tôn", "chân thân", "bản thể")),
    (re.compile(r"在下(?![面方风头边来去])"), ("tại hạ",)),
    (re.compile(r"晚辈"), ("vãn bối", "hậu bối")),
    (re.compile(r"贫道"), ("bần đạo",)),
    (re.compile(r"贫僧"), ("bần tăng",)),
    (re.compile(r"哀家"), ("ai gia",)),
    (re.compile(r"朕"), ("trẫm",)),
    (re.compile(r"微臣"), ("vi thần", "thần")),
    (re.compile(r"臣妾"), ("thần thiếp",)),
]


def self_reference_omissions(zh: str, vi: str) -> list[str]:
    """Tự xưng giàu sắc thái có trong gốc nhưng biến mất khỏi bản dịch."""
    low = vi.lower()
    out = []
    for pat, accepted in SELF_REFERENCE_CONSTRAINTS:
        hits = pat.findall(zh)
        if hits and not any(term in low for term in accepted):
            out.append(f"{hits[0]}×{len(hits)} thiếu dấu vết ({'/'.join(accepted)})")
    return out


def check_translation(content_zh: str, content_vi: str) -> str | None:
    """Trả LÝ DO nếu bản dịch hỏng, None nếu đạt. Dùng chung cho: fuse lúc dịch (chunk vs
    output) VÀ lệnh `audit` quét chương đã lưu (content_zh vs content_vi).

    - còn >5% ký tự Hán → trả nguyên văn tiếng Trung.
    - ngắn <120% gốc (zh→vi bình thường 2.5-3.5x) → dịch sót đoạn; chương ngắn ngưỡng 30%.
    - gốc ≥10 đoạn mà bản dịch mất >40% số đoạn → model nuốt đoạn.
    - gốc nhiều đoạn nhưng bản dịch mất hết xuống dòng → gộp thành 1 khối chữ liền.
    (content_zh rỗng thì bỏ qua 2 kiểm tra cần đối chiếu gốc — chỉ soi tỷ lệ Hán.)
    """
    if not (content_vi or "").strip():
        return "nội dung dịch rỗng"
    han = HAN_CHARS.search(content_vi)
    if han:
        return f"còn ký tự Hán '{han.group(0)}'"
    # ponytail: ngưỡng 2% ~ gấp 6 lần văn Việt thật (mục đích/giai đoạn/chi phí...);
    # bản phiên âm thật sự đo được ~6%
    if len(content_vi.split()) > 100:
        t = _translit_ratio(content_vi)
        if t > 0.02:
            return f"phiên âm Hán-Việt thay vì dịch nghĩa (mật độ hư từ {t:.1%})"
    # zh→vi bình thường phình 2.5-3.5x (tính KÝ TỰ) → dưới 1.2x là dịch sót đoạn.
    # Ngưỡng 0.3 cũ chỉ bắt được cụt thảm họa; chương ngắn (lời tác giả) giữ ngưỡng lỏng.
    # LƯU Ý: omission tự xưng KHÔNG nằm ở gate này — retry mù không chữa được model lì
    # (n1007 kẹt vĩnh viễn 3/3 lượt), phải sửa có mục tiêu bằng _fix_omissions sau dịch.
    if content_zh:
        ratio_min = 1.2 if len(content_zh) > 300 else 0.3
        if len(content_vi) < ratio_min * len(content_zh):
            return f"quá ngắn ({len(content_vi)}/{len(content_zh)} ký tự)"
    # prompt yêu cầu mỗi dòng gốc ↔ một dòng dịch → mất >40% số đoạn = model nuốt đoạn
    zh_lines = sum(1 for line in content_zh.split("\n") if line.strip())
    vi_lines = sum(1 for line in content_vi.split("\n") if line.strip())
    if zh_lines >= 10 and vi_lines < 0.6 * zh_lines:
        return f"mất đoạn (dịch {vi_lines}/{zh_lines} đoạn gốc)"
    # phình bất thường (bình thường ~2.5-3.5x vì zh→vi tính KÝ TỰ) → nghi chèn rác/bịa thêm;
    # chỉ soi khi gốc đủ dài, chương ngắn (lời nhắn tác giả…) tỉ lệ nhiễu
    if content_zh and len(content_zh) > 400 and len(content_vi) > 4.5 * len(content_zh):
        return f"phình bất thường ({len(content_vi) / len(content_zh):.1f}x gốc)"
    if content_zh.count("\n") >= 5 and content_vi.count("\n") == 0:
        return "mất hết xuống dòng (gộp đoạn thành khối chữ liền)"
    return None


# Thoại nằm trong "..." hoặc “...” (prompt bắt thoại dùng ngoặc kép kiểu Việt).
# Giới hạn độ dài + không ăn qua xuống dòng để câu kể thiếu ngoặc đóng không bị nuốt oan.
_DIALOGUE_RE = re.compile(
    r'"[^"\n]{1,500}"|“[^”\n]{1,500}”|^[ \t]*[—–-]\s+[^\n]{1,500}', re.M)


# Đại từ kể sai có thể vá MÁY MÓC an toàn (ngôi ba rõ ràng, giới tính rõ ràng).
# "tôi"/"cô" trần không vá được (không rõ thay bằng gì) → vẫn để fuse chặn + retry.
_REG_FIX = [
    (re.compile(r"\b[Cc]ô (?:ta|ấy)\b"), "nàng"),
    (re.compile(r"\b[Aa]nh (?!trai\b)(?:ta|ấy)\b"), "hắn"),
    (re.compile(r"\b[Cc]ậu ta\b"), "hắn"),
    (re.compile(r"\b[Ôô]ng (?:ta|ấy)\b"), "lão"),
    # Đại từ "anh" trần trong lời kể; chừa các từ ghép/danh xưng thông dụng.
    (re.compile(r"(?<!tinh )\b[Aa]nh\b(?!\s+(?:trai|em\b|chị\b|hùng|tài|kiệt|linh|hào|dũng|quốc))"), "hắn"),
]
# "Cô/Anh" TRẦN chỉ vá khi mở đầu câu kể + chữ thường theo sau (chắc chắn là đại từ);
# giữa câu để yên — "cô" còn là danh từ (cô nương/cô gái), "anh" còn là anh hùng/tinh anh.
_REG_FIX_HEAD = [
    (re.compile(r"(^|[.!?…]\s+)Cô\s+(?=[a-zà-ỹ])(?!ta\b|ấy\b|nương|gái|em\b|đơn|độc|bé\b)", re.M), r"\1Nàng "),
    (re.compile(r"(^|[.!?…]\s+)Anh\s+(?=[a-zà-ỹ])(?!ta\b|ấy\b|trai|em\b|hùng|tài|kiệt|linh|hào|dũng)", re.M), r"\1Hắn "),
]


def _fix_register(vi: str) -> str:
    """Vá đại từ kể sai phổ biến NGOÀI ngoặc kép (model quen 'cô ấy/anh ta' với truyện
    nữ chính/hiện đại — vá máy móc đỡ đốt lượt retry; thoại giữ nguyên)."""
    def fix_seg(seg: str) -> str:
        for pat, rep in _REG_FIX:
            seg = pat.sub(lambda m, r=rep: r.capitalize() if m.group(0)[0].isupper() else r, seg)
        for pat, rep in _REG_FIX_HEAD:
            seg = pat.sub(rep, seg)
        return seg
    out, last = [], 0
    for m in _DIALOGUE_RE.finditer(vi):
        out.append(fix_seg(vi[last:m.start()]))
        out.append(m.group(0))
        last = m.end()
    out.append(fix_seg(vi[last:]))
    return "".join(out)


_ZH_DIALOGUE_RE = re.compile(r'“[^”]*”|「[^」]*」|"[^"\n]*"')


def _is_first_person(zh: str) -> bool:
    """Truyện ngôi nhất khi 我 ÁP ĐẢO 他/她 trong lời kể. Đếm 1 chữ là dính oan:
    n1043 có đúng 1 我 (trong từ ghép 自我安慰) vs 36 他 → cả chương bị lật sang
    'ta' ngôi nhất. Truyện ngôi nhất thật thì 我 nhiều hơn hẳn."""
    narr = _ZH_DIALOGUE_RE.sub("", zh)
    return narr.count("我") > narr.count("他") + narr.count("她")


def _register_violation(content_vi: str, allow_toi: bool = False) -> str | None:
    """Chặn đại từ sai trong LỜI KỂ (user chốt 2026-07-10: chỉ lời kể mới cấm —
    thoại được linh hoạt anh/em/ca theo bối cảnh, nên bỏ qua khi soi).
    CHỈ bắt cụm không thể nhầm ("anh ta", "cô ấy", "tôi"...) — "anh"/"cô" trần
    KHÔNG bắt vì dính oan từ ghép: anh hùng/tinh anh/Nguyên Anh/nước Anh/cô nương.
    `allow_toi`: truyện kể ngôi thứ nhất → "tôi" là đúng, không bắt."""
    narration = _DIALOGUE_RE.sub(" ", content_vi)
    bad = re.search(r"\b(?:anh\s+(?:ta|ấy)|cậu ta|ông ta|cô\s+(?:ta|ấy))\b", narration, re.I)
    if bad:
        return f"lệch xưng hô '{bad.group(0)}' trong lời kể"
    if not allow_toi:
        # 'ta/tôi' lẻ tẻ ngoài ngoặc có thể là nghĩ thầm không ngoặc kép — prompt CHO PHÉP
        # xưng 'ta' ở đó, chặn từ 1 lần làm chương nhiều độc thoại kẹt vĩnh viễn (n1007
        # fail 6/6 lượt). Chỉ coi là TRÔI POV khi dày.
        # ponytail: ngưỡng 3 là số thô, chỉnh khi đo thêm chương
        hits = re.findall(r"\b(?:tôi(?!\s+luyện)|(?<!chúng\s)(?<!người\s)ta)\b", narration, re.I)
        if len(hits) >= 3:
            return f"lệch xưng hô '{hits[0]}' ×{len(hits)} trong lời kể"
    return None


def _audit_reason(content_zh: str, content_vi: str) -> str | None:
    """Lỗi cứng đáng xếp lại dịch; không kéo lỗi văn phong mềm vào audit hàng loạt."""
    return (check_translation(content_zh, content_vi)
            or _register_violation(content_vi, allow_toi=_is_first_person(content_zh))
            or next(iter(self_reference_omissions(content_zh, content_vi)), None))


def _quality_fuse(chunk: str, first_person: bool | None = None):
    """Validator chạy TRONG FallbackChain — raise khi output kém để tự đổi provider.
    Đo trên phần THÂN bản dịch (đã bỏ GLOSSARY_JSON/SUMMARY) — đo text thô sẽ lệch:
    tên Trung trong GLOSSARY_JSON tính nhầm vào tỷ lệ Hán, JSON dài tính nhầm vào độ phình."""
    def check(res) -> None:
        # vá đại từ kể sai vá được TRƯỚC khi soi — res.text sửa tại chỗ để pipeline
        # nhận bản đã vá (validator là chỗ duy nhất thấy text trước khi chain trả về)
        res.text = _fix_register(res.text)
        content_vi = _strip_meta(res.text)
        # Vài chữ Hán sót được sửa đúng dòng ngay sau complete; loại cả bản ở đây gây
        # mất chương chỉ vì nhãn như 囚/死. Đếm chữ KHÁC NHAU chứ không đếm lượt:
        # một biệt danh sót lặp 12 lần (二娃子, n1043 kẹt 6/6 lượt) vẫn chỉ là 3 chữ,
        # _fix_han_residue sửa được hết. Bản trả nguyên văn Hán vẫn bị fuse chặn.
        checked_vi = (HAN_CHARS.sub("x", content_vi)
                      if len(set(HAN_CHARS.findall(content_vi))) <= 8 else content_vi)
        problem = check_translation(chunk, checked_vi) or _register_violation(
            content_vi, allow_toi=_is_first_person(chunk) if first_person is None else first_person)
        if problem:
            raise RuntimeError(f"Bản dịch {problem} (model {res.model})")
    return check


def scan_bad_chapters(since: str | None = None) -> list[tuple[dict, str]]:
    """Quét chương 'done', trả [(chapter, lý_do)] cho các chương hỏng (dùng
    check_translation). `since` (ISO) → chỉ quét chương dịch SAU mốc đó: audit định kỳ
    khỏi kéo full text toàn kho mỗi chu kỳ (egress đắt); lệnh `audit`/nút Quét lỗi
    vẫn gọi không tham số để quét full."""
    rows: list[dict] = []
    frm = 0
    while True:
        q = (
            db.sb().table("chapters")
            .select("id, novel_id, chapter_index, content_zh, content_vi, model_used, "
                    "novels(title_vi, title_zh)")
            .eq("translation_status", "done")
        )
        if since:
            q = q.gte("translated_at", since)
        b = (q.range(frm, frm + 499).execute()).data or []
        rows += b
        if len(b) < 500:
            break
        frm += 500
    bad: list[tuple[dict, str]] = []
    for c in rows:
        reason = _audit_reason(c.get("content_zh") or "", c.get("content_vi") or "")
        if reason:
            bad.append((c, reason))
    return bad


def requeue_bad(bad: list[tuple[dict, str]]) -> None:
    """Xếp lại hàng đợi các chương hỏng để dịch lại bằng model hiện tại (dọn job cũ trước)."""
    for c, _ in bad:
        db.sb().table("translation_jobs").delete().eq("chapter_id", c["id"]).in_(
            "status", ["failed", "done"]).execute()
        db.sb().table("chapters").update({"translation_status": "queued"}).eq("id", c["id"]).execute()
        db.enqueue("chapter", c["novel_id"], chapter_id=c["id"], priority=40)


def _tail(text: str | None, limit: int = 350) -> str | None:
    """Đuôi bản dịch liền trước (cắt tại ranh giới đoạn gần nhất) — ngữ cảnh nối
    giọng văn/xưng hô qua ranh giới chương/chunk, rẻ hơn nhiều so với gửi cả chương."""
    if not text:
        return None
    t = text.strip()
    if len(t) > limit:
        t = t[-limit:]
        nl = t.find("\n")
        if 0 <= nl < limit - 50:  # bỏ đoạn đầu cụt, giữ từ ranh giới đoạn
            t = t[nl + 1:]
    return t.strip() or None


# khớp dòng tiêu đề theo khuôn «TIÊU ĐỀ: ...» prompt yêu cầu; nhận cả nhãn cũ model hay tự chế,
# kể cả khi model bọc trong «»/quotes (đã gặp thật: «TIÊU ĐỀ: Thế giới game bỗng hiện»)
TITLE_LINE = re.compile(
    r"""^\s*[#>*«"'\[(]*\s*(?:tiêu đề(?: chương)?|tieu de|nhan đề|title)\s*[:：]\s*(.+)$""",
    re.I)

_TITLE_TRIM = "«»\"'“”‘’[]() \t#*"


def _clean_title(t: str) -> str:
    """Dọn tiêu đề model trả: bỏ ngoặc/quote bọc quanh, nhãn lặp, "Chương N:" tự chế."""
    t = t.strip(_TITLE_TRIM)
    t = re.sub(r"^(?:chương|chapter)\s*\d+\s*[:：.．\-–—]?\s*", "", t, flags=re.I)
    t = re.sub(r"^(?:tiêu đề(?: chương)?|tieu de|nhan đề|title)\s*[:：]\s*", "", t, flags=re.I)
    return t.strip(_TITLE_TRIM)


def _pop_title(text: str) -> tuple[str | None, str]:
    """Bóc tiêu đề đã dịch khỏi đầu bản dịch. Ưu tiên dòng «TIÊU ĐỀ: ...» (định dạng
    prompt yêu cầu); fallback: dòng đầu ngắn <100 ký tự (model quên nhãn — heuristic cũ)."""
    first, _, rest = text.partition("\n")
    if not rest.strip():
        return None, text
    m = TITLE_LINE.match(first)
    if m:
        return _clean_title(m.group(1)) or None, rest.strip()
    if len(first) < 100:
        return _clean_title(first) or None, rest.strip()
    return None, text


def _pop_summary(text: str) -> tuple[str, str | None]:
    """Bóc dòng 'SUMMARY: ...' ở cuối bản dịch (sau khi đã bóc GLOSSARY_JSON)."""
    idx = text.rfind("\nSUMMARY:")
    # chỉ nhận khi nằm gần cuối — tránh ăn nhầm chữ "SUMMARY:" giữa nội dung
    if idx == -1 or len(text) - idx > 1500:
        return text, None
    summary = text[idx + len("\nSUMMARY:"):].strip()
    return text[:idx].rstrip(), summary or None


# Trần chunk theo TRẦN OUTPUT chứ không phải context: bản Việt ~3.4x số ký tự Hán.
# 6k từng sát max_tokens 8192 (đã gặp "Output bị cắt" trên model fallback) → 5k cho có biên.
CHUNK_LIMIT = 5_000

# 2-pass thích ứng: chốt tên riêng trước khi dịch ở arc mở đầu, tự tắt khi hết tên mới.
NEW_NAME_LOW = 2        # chương ra ≤ ngần này tên mới coi là "ít"
LOW_STREAK_LIMIT = 3    # đủ ngần này chương "ít" liên tiếp → tắt 2-pass cho truyện


def _merge_names(terms: list[dict], existing_zh: set[str], names: list[dict]) -> list[dict]:
    """Thêm tên mới (chưa có term_zh) vào `terms` để chunk/chương sau dùng ngay.
    Trả về danh sách tên THẬT SỰ mới (đếm cho logic tắt 2-pass + lưu DB làm gợi ý)."""
    added: list[dict] = []
    for nm in names or []:
        if not isinstance(nm, dict):
            continue
        zh, vi = nm.get("zh"), nm.get("vi")
        if not zh or not vi or zh in existing_zh:
            continue
        # LLM nhỏ hay phiên âm bừa kiểu pinyin (罗森→"Lao Sen") → đối chiếu bảng tra
        # Hán-Việt, sai thì thay ("La Sâm") TRƯỚC khi vào prompt/DB
        vi = nm["vi"] = hanviet.reconcile(zh, vi, nm.get("type")) or vi
        existing_zh.add(zh)
        terms.append({
            "term_zh": zh, "correct_vi": vi,
            "term_type": nm.get("type"), "note": nm.get("note"),
        })
        added.append(nm)
    return added


def _analyze_names(llm, chunk: str) -> list[dict]:
    """Pass 1: trích tên riêng / thuật ngữ để chốt phiên âm vào glossary TRƯỚC khi dịch.
    Lỗi thì [] — dịch vẫn chạy, chỉ thiếu gợi ý tên."""
    try:
        res = llm.complete(prompts.SYSTEM_ANALYZE, chunk, max_tokens=1536)
        data = _extract_json(res.text)
    except Exception:
        return []
    if isinstance(data, list):        # model trả shape mảng cũ → vẫn nhận tên
        return data
    if isinstance(data, dict):
        terms = data.get("terms")
        return terms if isinstance(terms, list) else []
    return []


def _split_chunks(text: str, limit: int = CHUNK_LIMIT) -> list[str]:
    """Cắt chương dài theo ranh giới đoạn văn, mỗi chunk <= limit ký tự."""
    if len(text) <= limit:
        return [text]
    chunks: list[str] = []
    cur = ""
    for para in text.split("\n"):
        if cur and len(cur) + 1 + len(para) > limit:
            chunks.append(cur)
            cur = para
        else:
            cur = f"{cur}\n{para}" if cur else para
    if cur:
        chunks.append(cur)
    return chunks


def _extract_json(text: str) -> dict | list:
    """LLM đôi khi bọc JSON trong ```json ...``` — bóc ra."""
    m = re.search(r"```(?:json)?\s*(.+?)\s*```", text, re.S)
    if m:
        return json.loads(m.group(1).strip())
    text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        starts = [i for i in (text.find("{"), text.find("[")) if i >= 0]
        if not starts:
            raise
        start = min(starts)
        opener = text[start]
        closer = "}" if opener == "{" else "]"
        depth = 0
        in_string = False
        escaped = False
        for i in range(start, len(text)):
            ch = text[i]
            if escaped:
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == '"':
                in_string = not in_string
                continue
            if in_string:
                continue
            if ch == opener:
                depth += 1
            elif ch == closer:
                depth -= 1
                if depth == 0:
                    return json.loads(text[start:i + 1])
        raise


# --- Sửa có mục tiêu (Q3-lite, 2026-07-12) -----------------------------------
# Prompt cấm nhưng model vẫn lì các lỗi văn phong mềm (Q0: "chẳng" tràn lan, chữ đệm
# "chăng/chứ" cuối câu, convertese, lặp từ). Retry cả chunk vừa đắt vừa không chắc
# hơn → soi câu lỗi rồi gọi MỘT lượt LLM sửa đúng các câu đó, thay lại bằng máy.
# "chẳng" → "không" là phép thay an toàn (giữ "chẳng lẽ/chẳng qua") → vá MÁY MÓC,
# không phó mặc LLM (đo thật: lượt revise LLM lúc sửa lúc không).
_CHANG_RE = re.compile(r"\b[Cc]hẳng\b(?!\s+lẽ|\s+qua)")
# 不禁/不由得 dịch phẳng "không khỏi" — lược thẳng khi đứng trước động từ cảm xúc
# (đo v4: LLM revise được nhắc vẫn bỏ sót). Giữ nghĩa thật "chữa/trị... không khỏi"
# bằng lookbehind + không đụng khi theo sau là "được/bệnh/hẳn" hoặc dấu câu.
_KHONG_KHOI_RE = re.compile(
    r"(?<!chữa )(?<!trị )(?<!mãi )\b([Kk])hông khỏi\s+(?!được\b|bệnh\b|hẳn\b)([a-zà-ỹ])")
# 总感觉 dịch phẳng "tổng cảm thấy/giác" → "cứ cảm thấy/giác"
_TONG_CAM_RE = re.compile(r"\b([Tt])ổng cảm (thấy|giác)\b")


def _fix_soft_style(vi: str) -> str:
    vi = _CHANG_RE.sub(lambda m: "Không" if m.group(0).startswith("C") else "không", vi)
    vi = _KHONG_KHOI_RE.sub(
        lambda m: m.group(2).upper() if m.group(1) == "K" else m.group(2), vi)
    return _TONG_CAM_RE.sub(
        lambda m: ("Cứ" if m.group(1) == "T" else "cứ") + " cảm " + m.group(2), vi)


_REVISE_RULES: list[tuple[str, re.Pattern]] = [
    ("chữ đệm thừa cuối câu", re.compile(r"\b(?:chăng|chứ|nha)\s*[?!.…”\"]", re.I)),
    # độc thoại/thoại xưng "mình" — kỳ ảo phải là "ta" hoặc lược (Q0 n962)
    ("tự xưng 'mình' → 'ta' hoặc lược", re.compile(
        r"(?:^|[\"“…,.!?:]\s*)[Mm]ình\s+(?:đã|chắc|sẽ|không|phải|cũng|còn|vừa|mới|chết|bị|đang)")),
    ("lỗi convert", re.compile(
        r"\b(?:không khỏi|căn bản là|rốt cuộc là|trên thực tế|tổng cảm thấy)\b", re.I)),
    ("'X một cái' convert", re.compile(
        r"(?:cười|nhìn|liếc|gật đầu|thở dài|vỗ|lắc đầu)\s+một cái", re.I)),
    # đồng bộ với evaluator: ≥3 'hắn' trong CÙNG câu là dày, bất kể cách nhau bao xa
    # (v4: câu dài 3 'hắn' cách >60 ký tự lọt lưới worker nhưng evaluator vẫn bắt)
    ("lặp 'hắn' dày trong câu", re.compile(r"(?:\bhắn\b.*?){2}\bhắn\b", re.I)),
]
_SENT_SPLIT = re.compile(r'(?<=[.!?…”"])\s+')
MAX_REVISE_SENTENCES = 12  # ponytail: quá ngần này = bản dịch hỏng diện rộng, retry rẻ hơn revise


def _style_flags(vi: str) -> list[tuple[str, str]]:
    """(câu, lỗi) cho từng câu vi phạm luật văn phong mềm."""
    flags = []
    for para in vi.split("\n"):
        for sent in _SENT_SPLIT.split(para):
            issues = [name for name, pat in _REVISE_RULES if pat.search(sent)]
            if issues:
                flags.append((sent.strip(), "; ".join(issues)))
    return flags


def _apply_fixes(vi: str, fixes) -> tuple[str, int]:
    """Thay câu sửa vào bản dịch — chỉ nhận bản sửa khớp nguyên văn và lành mạnh."""
    applied = 0
    for fx in fixes if isinstance(fixes, list) else []:
        old, new = (fx or {}).get("old"), (fx or {}).get("new")
        if (old and new and old != new and old in vi
                and 0.4 * len(old) <= len(new) <= 2.0 * len(old)
                and not HAN_CHARS.search(new)):
            vi = vi.replace(old, new, 1)
            applied += 1
    return vi, applied


def _apply_line_fixes(vi: str, fixes) -> tuple[str, int]:
    """Áp bản sửa theo số dòng, tránh LLM chép lệch dấu câu làm `old` không khớp."""
    lines, applied = vi.splitlines(), 0
    if isinstance(fixes, dict):  # model hay gói mảng trong object ({"fixes": [...]})
        fixes = next((v for v in fixes.values() if isinstance(v, list)), [])
    for fx in fixes if isinstance(fixes, list) else []:
        line, new = (fx or {}).get("line"), (fx or {}).get("new")
        if line is None and (fx or {}).get("old"):  # model trả format cũ old/new → vẫn áp
            fixed, n = _apply_fixes("\n".join(lines), [fx])
            if n:
                lines, applied = fixed.split("\n"), applied + n
            continue
        if isinstance(line, str) and line.isdigit():
            line = int(line)
        if (isinstance(line, int) and 1 <= line <= len(lines) and isinstance(new, str)
                and new.strip()
                and 0.4 * len(lines[line - 1]) <= len(new) <= 2.0 * len(lines[line - 1])
                and not HAN_CHARS.search(new)):
            lines[line - 1] = new
            applied += 1
    return "\n".join(lines), applied


def _fix_han_residue(chapter_llm, vi: str) -> str:
    """Sửa tối thiểu các dòng còn Hán tự; không dịch lại cả chunk."""
    bad = [(i, line) for i, line in enumerate(vi.splitlines(), 1) if HAN_CHARS.search(line)]
    if not bad:
        return vi
    user = ("Các dòng sau còn ký tự Hán. Chỉ dịch phần chữ Hán sang tiếng Việt tự nhiên, "
            "giữ nguyên mọi nội dung khác. Trả JSON "
            "[{\"line\": N, \"new\": \"toàn bộ dòng đã sửa\"}].\n\n"
            + "\n".join(f"{i}: {line}" for i, line in bad))
    try:
        fixes = _extract_json(chapter_llm.complete(
            prompts.SYSTEM_REVISE, user, max_tokens=2048).text)
        vi, applied = _apply_line_fixes(vi, fixes)
        log.info("Fix Hán tự sót: %d dòng lỗi, %d dòng thay", len(bad), applied)
    except Exception as e:
        log.warning("Fix Hán tự sót lỗi: %s", e)
    if HAN_CHARS.search(vi):
        raise RuntimeError("không sửa hết ký tự Hán sót")
    return vi


_ZH_SENT_SPLIT = re.compile(r"(?<=[。！？!?\n])")


def _fix_omissions(chapter_llm, zh_chunk: str, vi: str) -> str:
    """Q3 cho omission tự xưng: đưa CÂU GỐC chứa tự xưng bị mất cho LLM, sửa đúng câu
    dịch tương ứng. Retry mù trong fuse không chữa được model lì (n1007 fail 3/3 lượt)."""
    low = vi.lower()
    lines = []
    for pat, accepted in SELF_REFERENCE_CONSTRAINTS:
        m = pat.search(zh_chunk)
        if m and not any(term in low for term in accepted):
            sent = next((s for s in _ZH_SENT_SPLIT.split(zh_chunk) if pat.search(s)), m.group(0))
            lines.append(f"- Câu gốc: {sent.strip()[:200]} — tự xưng {m.group(0)} phải để lại "
                         f"dấu vết trong bản dịch ({'/'.join(accepted)})")
    if not lines:
        return vi
    numbered = "\n".join(f"{i}: {line}" for i, line in enumerate(vi.splitlines(), 1))
    user = ("Bản dịch dưới đây làm MẤT sắc thái tự xưng của các câu gốc sau:\n"
            + "\n".join(lines)
            + "\n\nBẢN DỊCH ĐÁNH SỐ DÒNG:\n" + numbered
            + "\n\nTìm dòng dịch tương ứng với từng câu gốc, sửa TỐI THIỂU để giữ đúng "
              "sắc thái tự xưng. Trả JSON "
              "[{\"line\": N, \"new\": \"toàn bộ dòng đã sửa\"}].")
    try:
        fixes = _extract_json(chapter_llm.complete(prompts.SYSTEM_REVISE, user, max_tokens=2048).text)
        vi, applied = _apply_line_fixes(vi, fixes)
        log.info("Fix omission tự xưng: %d marker, %d câu thay", len(lines), applied)
    except Exception as e:
        log.warning("Fix omission lỗi (giữ bản gốc): %s", e)
    return vi


_STYLE_KEYS = ("pov", "setting", "han_viet", "tone", "rules")


def _clean_style(style) -> dict | None:
    """Chỉ giữ key/độ dài hợp lệ — JSON rác của model không được sống xuyên truyện."""
    if not isinstance(style, dict):
        return None
    out = {}
    for k in _STYLE_KEYS:
        v = style.get(k)
        if k == "rules":
            rules = [r.strip()[:120] for r in v if isinstance(r, str) and r.strip()] \
                if isinstance(v, list) else []
            if rules:
                out[k] = rules[:5]
        elif isinstance(v, str) and v.strip():
            out[k] = v.strip()[:80]
    return out or None


def _init_style_bible(chapter_llm, nv: dict, novel_id: int, content_zh: str,
                      chapter_index: int | None = None) -> dict | None:
    """Sinh style bible MỘT lần từ metadata + đầu chương rồi lưu vào novels.
    Lỗi thì trả None — chương này dịch không style line, chương sau thử lại."""
    meta = json.dumps({
        "title": nv.get("title_zh") or nv.get("title_vi"),
        "genres": nv.get("genres") or [],
    }, ensure_ascii=False)
    try:
        res = chapter_llm.complete(
            prompts.SYSTEM_STYLE, f"{meta}\n\nĐoạn mở đầu:\n{content_zh[:2000]}",
            max_tokens=512)
        style = _clean_style(_extract_json(res.text))
        if not style:
            return None
        if chapter_index is not None:
            # style sinh từ chương giữa truyện kém đại diện hơn chương 1 — ghi lại
            # nguồn để biết bản nào đáng tái tạo
            style["src_chapter"] = chapter_index
        db.sb().table("novels").update({"translation_style": style}).eq("id", novel_id).execute()
        log.info("Novel %s: đã sinh style bible %s", novel_id, style)
        return style
    except Exception as e:
        log.warning("Novel %s: sinh style bible lỗi (bỏ qua): %s", novel_id, e)
        return None


def _style_revise(chapter_llm, vi: str, zh: str = "") -> str:
    """Lượt biên tập có mục tiêu; mọi lỗi ở đây đều không được phá bản dịch gốc."""
    flags = _style_flags(vi)
    if not flags or len(flags) > MAX_REVISE_SENTENCES:
        return vi
    bad_lines = []
    for line_no, line in enumerate(vi.splitlines(), 1):
        issues = sorted({issue for _, issue in _style_flags(line)})
        if issues:
            bad_lines.append((line_no, line, "; ".join(issues)))
    listing = "\n\n".join(
        f"DÒNG {line_no}: {line}\nLỖI: {issues}" for line_no, line, issues in bad_lines)
    listing += ("\n\nTrả JSON [{\"line\": N, \"new\": \"toàn bộ dòng đã sửa\"}]. "
                "Giữ nguyên ý và chỉ sửa lỗi được đánh dấu.")
    try:
        res = chapter_llm.complete(prompts.SYSTEM_REVISE, listing, max_tokens=4096)
        original = vi
        vi, applied = _apply_line_fixes(vi, _extract_json(res.text))
        vi = _fix_register(vi)
        problem = check_translation(zh, vi) or _register_violation(
            vi, allow_toi=_is_first_person(zh))
        if problem:
            log.warning("Revise văn phong làm giảm chất lượng (%s), giữ bản trước revise", problem)
            return original
        log.info("Revise văn phong: %d câu đánh dấu, %d câu thay", len(flags), applied)
    except Exception as e:
        log.warning("Revise văn phong lỗi (giữ bản gốc): %s", e)
    return vi


# Xưng hô: MỘT luật cho mọi truyện (2026-07-10, đã bỏ nhánh đô thị tôi–anh):
# lời KỂ cứng hắn/nàng; THOẠI linh hoạt theo bối cảnh (fuse cũng chỉ soi lời kể).
REGISTER_LINE = (
    "[Xưng hô — LỜI KỂ ngôi ba: nam 'hắn', nữ 'nàng'; TUYỆT ĐỐI KHÔNG "
    "'anh/anh ta/ông ta/cậu ta/tôi/cô/cô ấy' làm đại từ trong lời kể. Ngôi nhất/độc thoại "
    "bối cảnh kỳ ảo: xưng 'ta', KHÔNG 'tôi/mình'. THOẠI: tu tiên/cổ trang ta–ngươi, "
    "ca/huynh/tỷ/muội, KHÔNG anh/chị/em/mày; nhân vật hiện đại với nhau được anh/em hoặc "
    "'ca'; nhắc người thứ ba trong thoại: hắn ta/anh ta đều được.]")


def _register_line(zh: str) -> str:
    if _is_first_person(zh):
        return ("[POV LUẬT CỨNG: nguyên văn kể NGÔI NHẤT; lời kể/độc thoại dùng 'ta' "
                "hoặc lược chủ ngữ, không tự đổi sang hắn/anh/tôi.]")
    return ("[POV LUẬT CỨNG: nguyên văn kể NGÔI BA; nam dùng 'hắn', nữ dùng 'nàng'. "
            "CẤM ta/tôi/mình/anh/cậu làm đại từ trong LỜI KỂ; các từ ấy chỉ được giữ "
            "trong lời thoại trực tiếp.]")


# ---------- xử lý từng loại job ----------

def handle_metadata(job: dict, llm) -> None:
    novel = db.sb().table("novels").select("*").eq("id", job["novel_id"]).single().execute().data
    terms, _ = db.get_glossary(novel["id"])  # dịch lại metadata → tên khớp glossary đã tích lũy
    res = llm.complete(prompts.SYSTEM_METADATA, prompts.build_metadata_user(novel, terms), max_tokens=2048)
    data = _extract_json(res.text)
    db.sb().table("novels").update({
        "title_vi": data.get("title_vi"),
        "author_vi": data.get("author_vi"),
        "description_vi": data.get("description_vi"),
        "genres": data.get("genres_vi") or novel.get("genres"),
        "meta_translated": True,
        "updated_at": db.utc_now(),
    }).eq("id", novel["id"]).execute()
    log.info("Đã dịch metadata truyện %s: %s", novel["id"], data.get("title_vi"))


def handle_chapter(job: dict, llm) -> None:
    ch = db.sb().table("chapters").select("*").eq("id", job["chapter_id"]).single().execute().data
    if not ch.get("content_zh"):
        raise MissingContentError(f"Chương {ch['id']} chưa có content_zh — crawler chưa tải xong")

    db.sb().table("chapters").update({"translation_status": "translating"}).eq("id", ch["id"]).execute()

    providers.reset_call_stats()  # đếm LLM call/token cả chương (analyze + dịch + repair)
    t_start = time.time()
    terms, glossary_version = db.get_glossary(ch["novel_id"])

    # ngữ cảnh chương trước (nếu đã dịch): tóm tắt + ĐUÔI bản dịch (nối giọng văn/xưng hô)
    prev_summary = None
    prev_tail = None
    if ch["chapter_index"] > 1:
        prev = (
            db.sb().table("chapters").select("summary_vi, content_vi")
            .eq("novel_id", ch["novel_id"])
            .eq("chapter_index", ch["chapter_index"] - 1)
            .maybe_single().execute()
        )
        pd = getattr(prev, "data", None) or {}
        prev_summary = pd.get("summary_vi")
        prev_tail = _tail(pd.get("content_vi"))

    # 2-pass thích ứng + bối cảnh truyện (thể loại → register xưng hô).
    nv = (
        db.sb().table("novels")
        .select("twopass_active,twopass_low_streak,title_vi,title_zh,genres,translation_provider,translation_model,translation_style")
        .eq("id", ch["novel_id"]).single().execute()
    ).data or {}
    novel_line = None
    title = nv.get("title_vi") or nv.get("title_zh")
    if title:
        genres = ", ".join(nv.get("genres") or [])
        novel_line = f"{title}" + (f" — thể loại: {genres}" if genres else "")
    first_person = _is_first_person(ch["content_zh"])
    register_line = _register_line(ch["content_zh"])
    # Một truyện chỉ dùng đúng provider + model chốt ở chương đầu. Khi model lỗi,
    # job sẽ retry cùng cặp thay vì fallback âm thầm sang giọng khác.
    chapter_llm = llm
    if nv.get("translation_provider") and nv.get("translation_model"):
        chapter_llm = llm.pin(nv["translation_provider"], nv["translation_model"])
    twopass = nv.get("twopass_active", True)
    # style bible (Q1): có sẵn thì dùng, chưa có thì sinh 1 lần từ chương đang dịch
    style = nv.get("translation_style") or _init_style_bible(
        chapter_llm, nv, ch["novel_id"], ch["content_zh"], ch["chapter_index"])
    style_line = prompts.build_style_line(style)
    existing_zh = {t["term_zh"] for t in terms if t.get("term_zh")}
    # snapshot TRƯỚC khi merge tên mới: chỉ insert gợi ý chưa có trong DB, tránh nhân bản
    # (bảng không có unique constraint — try/except dưới chỉ là phòng hờ)
    preexisting_zh = set(existing_zh)
    new_names_this_chapter = 0

    chunks = _split_chunks(ch["content_zh"])
    parts: list[str] = []
    detected: list[dict] = []
    summary_vi = None
    prompt_tokens = completion_tokens = 0
    model = ""
    for i, chunk in enumerate(chunks):
        # Pass 1 (chỉ khi 2-pass còn bật): chốt phiên âm tên riêng vào glossary TRƯỚC khi dịch,
        # để mọi lần tên xuất hiện trong chunk này đều dùng đúng một cách phiên âm.
        if twopass:
            names = _analyze_names(chapter_llm, chunk)
            added = _merge_names(terms, existing_zh, names)
            new_names_this_chapter += len(added)
            detected += added  # tên pass-1 cũng phải vào DB — trước đây chỉ nằm RAM, chương sau mất

        res = chapter_llm.complete(
            # chỉ chèn term xuất hiện trong chunk này → prompt gọn, model bám sát hơn
            prompts.build_chapter_system(terms, chunk),
            # chunk sau nhận tóm tắt + đuôi bản dịch chunk trước làm ngữ cảnh nối mạch
            prompts.build_chapter_user(
                ch.get("title_zh") if i == 0 else None, chunk, prev_summary,
                prev_tail=prev_tail, novel_line=novel_line, register_line=register_line,
                style_line=style_line),
            # fuse chất lượng NẰM TRONG chain: output kém → tự đổi provider kế, không fail oan
            validate=_quality_fuse(chunk, first_person),
        )
        if not nv.get("translation_model"):
            db.sb().table("novels").update({
                "translation_provider": res.provider,
                "translation_model": res.model,
            }).eq("id", ch["novel_id"]).execute()
            nv["translation_provider"], nv["translation_model"] = res.provider, res.model
            chapter_llm = llm.pin(res.provider, res.model)
        text = res.text
        # bóc bảng tên riêng LLM phát hiện (phục vụ glossary suggest trong app)
        m = GLOSSARY_LINE.search(text)
        if m:
            text = text[: m.start()].rstrip()
            try:
                chunk_detected = json.loads(m.group(1))
                detected += chunk_detected
                # gộp luôn vào glossary cho chunk sau (miễn phí, giữ tên nhất quán cross-chunk)
                _merge_names(terms, existing_zh, chunk_detected)
            except json.JSONDecodeError:
                pass

        text, summary_vi = _pop_summary(text)
        prev_summary = summary_vi or prev_summary
        # Cầu chì chất lượng đã chạy TRONG llm.complete (validate=_quality_fuse) → tới đây
        # output chắc chắn đạt: đủ tiếng Việt, đủ độ dài, còn xuống dòng.
        text = _fix_omissions(chapter_llm, chunk, _clean_output(text))
        text = _fix_han_residue(chapter_llm, text)
        parts.append(text)
        prev_tail = _tail(parts[-1])  # chunk sau nối giọng văn từ đuôi chunk này
        prompt_tokens += res.prompt_tokens or 0
        completion_tokens += res.completion_tokens or 0
        model = res.model
        if len(chunks) > 1:
            log.info("Chương %s: chunk %d/%d xong", ch["id"], i + 1, len(chunks))

    text = "\n\n".join(parts)
    # vá văn phong máy móc (chẳng→không) rồi mới sửa có mục tiêu bằng LLM
    text = _fix_soft_style(text)
    text = _style_revise(chapter_llm, text, ch["content_zh"])
    # Revise có thể làm mất sắc thái tự xưng; lượt này chỉ gọi LLM khi thật sự còn thiếu.
    text = _fix_omissions(chapter_llm, ch["content_zh"], text)

    # Lưới an toàn: tên/thuật ngữ trong glossary còn SÓT dạng chữ Hán trong bản dịch
    # (lọt fuse vì dưới ngưỡng 5%) → thay thẳng bằng bản dịch chuẩn. Dài trước để
    # không đè cụm con (幻妖王 phải thay trước 幻妖).
    for t in sorted(terms, key=lambda t: -len(t.get("term_zh") or "")):
        zh = t.get("term_zh")
        if zh and t.get("correct_vi") and zh in text:
            text = text.replace(zh, t["correct_vi"])

    title_vi = None
    if ch.get("title_zh"):
        title_vi, text = _pop_title(text)
        # model đôi khi bỏ dịch tiêu đề → còn trơ chữ Hán. Phiên âm Hán-Việt cho khỏi
        # trơ chữ Trung (bỏ "第x章" trước). han_viet trả None nếu có chữ ngoài bảng → giữ nguyên.
        if title_vi and HAN_CHARS.search(title_vi):
            zh_clean = re.sub(
                r"^第?\s*[\d一二三四五六七八九十百千零〇兩两]+\s*[章回節节卷]\s*[:：.．\-–—]?\s*",
                "", ch["title_zh"]).strip()
            title_vi = hanviet.han_viet(zh_clean) or title_vi

    db.save_chapter_translation(
        ch["id"], title_vi, text, model, prompt_tokens, completion_tokens,
        glossary_version, summary_vi,
    )
    db.bump_translated_count(ch["novel_id"])

    # lưu tên riêng phát hiện được làm term "gợi ý" (approved=false, scope=novel)
    # — get_glossary lấy cả gợi ý nên chương sau dùng lại ngay, giữ phiên âm nhất quán
    inserted_zh: set[str] = set()
    for t in detected:
        zh = t.get("zh")
        if zh and t.get("vi") and zh not in preexisting_zh and zh not in inserted_zh:
            inserted_zh.add(zh)
            try:
                db.sb().table("glossary_terms").insert({
                    "novel_id": ch["novel_id"], "term_zh": t["zh"], "correct_vi": t["vi"],
                    "term_type": t.get("type", "other") if t.get("type") in
                        ("person", "place", "sect", "item", "skill") else "other",
                    "note": t.get("note") or None,  # giới tính/vai vế → xưng hô đúng ở chương sau
                    "scope": "novel", "approved": False,
                }).execute()
            except Exception as exc:
                if _is_unique_violation(exc):
                    log.debug("Glossary term trùng, bỏ qua: %s", zh)
                else:
                    # Bản dịch đã lưu ở trên: ghi rõ lỗi nhưng không dịch lại cả chương.
                    log.exception("Không lưu được glossary term %s (chương %s)", zh, ch["id"])

    # Cập nhật 2-pass thích ứng: đủ số chương "ít tên mới" liên tiếp thì tắt cho truyện này.
    # ponytail: nhiều luồng có thể đua state — chỉ là heuristic, đua lệch chút không sao.
    if twopass:
        if new_names_this_chapter <= NEW_NAME_LOW:
            streak = (nv.get("twopass_low_streak") or 0) + 1
        else:
            streak = 0
        still_active = streak < LOW_STREAK_LIMIT
        db.sb().table("novels").update(
            {"twopass_active": still_active, "twopass_low_streak": streak}
        ).eq("id", ch["novel_id"]).execute()
        if not still_active:
            log.info("Novel %s: tắt 2-pass (arc mở đầu xong, hết tên mới)", ch["novel_id"])

    st = providers.get_call_stats()
    log.info("Đã dịch chương %s/%s (novel %s) — %d chunk, %d LLM call, %d+%d tok, %.1fs",
             ch["chapter_index"], ch["novel_id"], model, len(chunks), st["calls"],
             st["prompt_tokens"], st["completion_tokens"], time.time() - t_start)


def handle_patch(job: dict, llm=None) -> None:
    """Vá chương đã dịch bằng string-replace các term có wrong_vi (không tốn LLM)."""
    terms, _ = db.get_glossary(job["novel_id"])
    repls = [(t["wrong_vi"], t["correct_vi"]) for t in terms
             if t.get("wrong_vi") and t.get("correct_vi")]
    # + tên còn SÓT dạng chữ Hán trong bản dịch cũ → thay bằng bản chuẩn luôn thể
    repls += [(t["term_zh"], t["correct_vi"]) for t in terms
              if t.get("term_zh") and t.get("correct_vi")]
    repls.sort(key=lambda p: -len(p[0]))  # cụm dài thay trước, không đè cụm con
    if not repls:
        return
    # page qua trần 1000 dòng PostgREST — truyện 4000 chương phải vá ĐỦ, không chỉ 1000 đầu
    chapters: list[dict] = []
    frm = 0
    while True:
        b = (
            db.sb().table("chapters").select("id, title_vi, content_vi")
            .eq("novel_id", job["novel_id"]).eq("translation_status", "done")
            .range(frm, frm + 499).execute()
        ).data or []
        chapters += b
        if len(b) < 500:
            break
        frm += 500
    patched = 0
    for ch in chapters:
        title, content = ch.get("title_vi") or "", ch.get("content_vi") or ""
        new_title, new_content = title, content
        for wrong, correct in repls:
            new_title = new_title.replace(wrong, correct)
            new_content = new_content.replace(wrong, correct)
        if (new_title, new_content) != (title, content):
            db.sb().table("chapters").update({
                "title_vi": new_title or None, "content_vi": new_content,
            }).eq("id", ch["id"]).execute()
            patched += 1
    log.info("Patch novel %s: vá %d/%d chương, %d term", job["novel_id"], patched, len(chapters), len(repls))


def handle_audit(job: dict, llm=None) -> None:
    """Job 'audit' (nút Quét lỗi trong Quản trị): quét toàn bộ chương done, xếp lại
    hàng đợi các chương hỏng để dịch lại. Không tốn LLM (chỉ heuristic)."""
    bad = scan_bad_chapters()
    if bad:
        # ponytail: batch cố định để nút Quét lỗi không đẩy cả kho cũ vào hàng dịch;
        # bấm lại sau khi batch xong sẽ lấy các chapter done còn lại.
        batch = bad[:25]
        for c, reason in batch:
            log.info("Audit: chương %s (novel %s) hỏng — %s", c["chapter_index"], c["novel_id"], reason)
        requeue_bad(batch)
        log.info("Audit: xếp lại %d/%d chương hỏng (bấm Quét lỗi lần nữa cho batch kế)",
                 len(batch), len(bad))
    else:
        log.info("Audit xong: không có chương hỏng")


HANDLERS = {
    "metadata": handle_metadata,
    "chapter": handle_chapter,
    "patch": handle_patch,
    "audit": handle_audit,
}


def _consume_loop(worker_id: str, slot: int, paused: threading.Event, poll_seconds: float) -> None:
    """Vòng lặp 1 luồng dịch. `slot` chọn key nvidia (2 key → 2 lane song song).
    `paused` set = đã chạm trần chi phí ngày → nghỉ."""
    llm = build_chain(slot)  # ghim 1 key nvidia cho luồng này, tái dùng suốt vòng đời
    idle_sleep = poll_seconds
    while True:
        if paused.is_set():
            time.sleep(30)
            continue
        # TOÀN BỘ thân vòng lặp trong try — lỗi mạng tạm thời (Supabase "Server
        # disconnected") ở claim/finish_job từng giết chết thread âm thầm, worker
        # nhìn như chạy mà không dịch gì. Job dở dang thì reaper trả lại sau.
        try:
            job = db.claim_next_job(worker_id)
            if not job:
                # hàng đợi trống → giãn dần poll tới 15s (đỡ ~50k RPC/ngày lúc rảnh);
                # có job lại về poll_seconds ngay — người đọc không phải chờ thêm
                time.sleep(idle_sleep)
                idle_sleep = min(idle_sleep + poll_seconds, 15.0)
                continue
            idle_sleep = poll_seconds
            log.info("[%s] Nhận job #%s type=%s novel=%s", worker_id, job["id"], job["type"], job["novel_id"])
            lease_stop = threading.Event()
            lease_thread = threading.Thread(
                target=_keep_job_lock,
                args=(job["id"], worker_id, lease_stop,
                      max(30.0, settings.stale_job_minutes * 20.0)),
                daemon=True,
            )
            lease_thread.start()
            try:
                HANDLERS[job["type"]](job, llm)
                db.finish_job(job["id"], ok=True)
            except MissingContentError as e:
                log.info("Job #%s chờ crawler: %s", job["id"], e)
                db.defer_job(job["id"], str(e))
                time.sleep(poll_seconds)
            except Exception as e:
                log.exception("Job #%s lỗi", job["id"])
                db.finish_job(job["id"], ok=False, error=str(e))
            finally:
                lease_stop.set()
                lease_thread.join(timeout=1)
        except Exception:
            log.exception("[%s] Lỗi tạm thời (mạng/DB) — nghỉ rồi thử lại", worker_id)
            time.sleep(max(poll_seconds, 5.0))


def run_forever(poll_seconds: float = 3.0) -> None:
    """Khởi động N luồng dịch (TRANSLATOR_CONCURRENCY) + luồng housekeeping.

    Housekeeping (mỗi 60s, chạy ở main thread):
    - Reaper: trả job kẹt 'running' quá STALE_JOB_MINUTES về hàng đợi
      (máy chạy worker sập/ngủ giữa chừng — hay gặp khi chạy trên máy cá nhân).
    - Cầu chì chi phí: dịch đủ MAX_CHAPTERS_PER_DAY chương trong ngày → tạm dừng
      mọi luồng tới 00:00 UTC hôm sau. Chống bug app spam request_translation.
    """
    log.info(
        "Translator '%s' bắt đầu: %d luồng, provider=%s, trần %d chương/ngày",
        settings.worker_id, settings.translator_concurrency,
        settings.llm_provider, settings.max_chapters_per_day,
    )
    paused = threading.Event()
    for i in range(settings.translator_concurrency):
        threading.Thread(
            target=_consume_loop,
            args=(f"{settings.worker_id}:{i}", i, paused, poll_seconds),
            daemon=True,
        ).start()

    last_audit = time.time()  # chờ đủ 1 chu kỳ mới quét lần đầu (khỏi trùng lúc mới khởi động)
    # Audit định kỳ chỉ quét chương dịch SAU watermark — restart process thì quét lại từ
    # lúc boot; nợ cũ trước đó đã dọn bởi các lần audit full (lệnh `audit`/nút Quét lỗi).
    audit_since = db.utc_now()
    while True:
        try:
            db.heartbeat("translator")  # điểm danh mỗi 60s
            db.requeue_stale_jobs(settings.stale_job_minutes)
            db.reset_orphan_chapters()  # dọn chương queued/translating không còn job (ghost Hàng đợi)
            # Audit định kỳ: tự quét chương done hỏng (Trung/cụt/mất đoạn lọt qua) → xếp lại dịch,
            # không phải đợi vào đọc mới biết. Fuse đã chặn chương mới nên đây chủ yếu dọn nợ cũ.
            if time.time() - last_audit > settings.audit_interval_min * 60:
                next_since = db.utc_now()
                bad = scan_bad_chapters(since=audit_since)
                audit_since = next_since
                if bad:
                    log.warning("Audit định kỳ: %d chương hỏng → xếp lại dịch", len(bad))
                    requeue_bad(bad)
                last_audit = time.time()
            # bám người đang đọc: nâng chương truyện đang đọc, hạ truyện không ai đọc
            db.reprioritize_chapters_by_reading(
                settings.active_read_hours, settings.prio_read, settings.prio_idle)
            done_today = db.count_chapters_translated_today()
            if done_today >= settings.max_chapters_per_day:
                if not paused.is_set():
                    log.warning(
                        "Chạm trần %d chương/ngày — tạm dừng dịch tới 00:00 UTC. "
                        "Nâng MAX_CHAPTERS_PER_DAY trong .env nếu chủ đích đọc nhiều.",
                        settings.max_chapters_per_day,
                    )
                    paused.set()
            elif paused.is_set():
                log.info("Sang ngày mới — tiếp tục dịch (đã dịch %d chương)", done_today)
                paused.clear()
        except Exception:
            log.exception("Lỗi housekeeping")
        time.sleep(60)
