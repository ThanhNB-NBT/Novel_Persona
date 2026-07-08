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


HAN_CHARS = re.compile(r"[一-鿿㐀-䶿]")


def han_ratio(text: str) -> float:
    """Tỷ lệ ký tự Hán trong bản dịch — dùng làm cầu chì chất lượng."""
    return len(HAN_CHARS.findall(text)) / max(len(text), 1)


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
    r = han_ratio(content_vi)
    if r > 0.05:
        return f"còn {r:.0%} ký tự Hán (trả nguyên văn tiếng Trung)"
    # zh→vi bình thường phình 2.5-3.5x (tính KÝ TỰ) → dưới 1.2x là dịch sót đoạn.
    # Ngưỡng 0.3 cũ chỉ bắt được cụt thảm họa; chương ngắn (lời tác giả) giữ ngưỡng lỏng.
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


def _quality_fuse(chunk: str):
    """Validator chạy TRONG FallbackChain — raise khi output kém để tự đổi provider.
    Đo trên phần THÂN bản dịch (đã bỏ GLOSSARY_JSON/SUMMARY) — đo text thô sẽ lệch:
    tên Trung trong GLOSSARY_JSON tính nhầm vào tỷ lệ Hán, JSON dài tính nhầm vào độ phình."""
    def check(res) -> None:
        problem = check_translation(chunk, _strip_meta(res.text))
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
        reason = check_translation(c.get("content_zh") or "", c.get("content_vi") or "")
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
    """Pass 1: chỉ trích tên riêng + phiên âm (không dịch → rẻ). Lỗi thì bỏ qua."""
    try:
        res = llm.complete(prompts.SYSTEM_ANALYZE, chunk, max_tokens=1024)
        data = _extract_json(res.text)
        return data if isinstance(data, list) else []
    except Exception:
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


# ---------- xử lý từng loại job ----------

def handle_metadata(job: dict, llm) -> None:
    novel = db.sb().table("novels").select("*").eq("id", job["novel_id"]).single().execute().data
    res = llm.complete(prompts.SYSTEM_METADATA, prompts.build_metadata_user(novel), max_tokens=2048)
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
        .select("twopass_active,twopass_low_streak,title_vi,title_zh,genres")
        .eq("id", ch["novel_id"]).single().execute()
    ).data or {}
    novel_line = None
    title = nv.get("title_vi") or nv.get("title_zh")
    if title:
        genres = ", ".join(nv.get("genres") or [])
        novel_line = f"{title}" + (f" — thể loại: {genres}" if genres else "")
    twopass = nv.get("twopass_active", True)
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
            names = _analyze_names(llm, chunk)
            added = _merge_names(terms, existing_zh, names)
            new_names_this_chapter += len(added)
            detected += added  # tên pass-1 cũng phải vào DB — trước đây chỉ nằm RAM, chương sau mất

        res = llm.complete(
            # chỉ chèn term xuất hiện trong chunk này → prompt gọn, model bám sát hơn
            prompts.build_chapter_system(terms, chunk),
            # chunk sau nhận tóm tắt + đuôi bản dịch chunk trước làm ngữ cảnh nối mạch
            prompts.build_chapter_user(
                ch.get("title_zh") if i == 0 else None, chunk, prev_summary,
                prev_tail=prev_tail, novel_line=novel_line),
            # fuse chất lượng NẰM TRONG chain: output kém → tự đổi provider kế, không fail oan
            validate=_quality_fuse(chunk),
        )
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
        parts.append(_clean_output(text))
        prev_tail = _tail(parts[-1])  # chunk sau nối giọng văn từ đuôi chunk này
        prompt_tokens += res.prompt_tokens or 0
        completion_tokens += res.completion_tokens or 0
        model = res.model
        if len(chunks) > 1:
            log.info("Chương %s: chunk %d/%d xong", ch["id"], i + 1, len(chunks))

    text = "\n\n".join(parts)

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
            except Exception:
                pass  # trùng thì thôi

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

    log.info("Đã dịch chương %s/%s (novel %s)", ch["chapter_index"], ch["novel_id"], model)


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
        for c, reason in bad:
            log.info("Audit: chương %s (novel %s) hỏng — %s", c["chapter_index"], c["novel_id"], reason)
        requeue_bad(bad)
    log.info("Audit xong: %d chương hỏng đã xếp lại dịch", len(bad))


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
