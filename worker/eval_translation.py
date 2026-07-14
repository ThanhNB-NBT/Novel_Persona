"""Bộ eval chất lượng dịch: lấy ngẫu nhiên chương, chấm tự động + xuất file để người/LLM thẩm định.

Hai chế độ:
  --existing N   lấy N chương ĐÃ dịch (done) ngẫu nhiên trong DB → lint + xuất cặp zh/vi
  --fresh N      lấy N chương có content_zh → dịch MỚI bằng model hiện tại → lint + xuất
                 (tốn call NIM; dùng khi muốn đo prompt/model sau chỉnh sửa)

    PYTHONIOENCODING=utf-8 PYTHONPATH=. ../.venv/Scripts/python.exe eval_translation.py --existing 12
    ... eval_translation.py --fresh 3 --out /tmp/eval

Lint bắt các lỗi convert đo được bằng máy (danh sách lỗi lấy từ prompt production —
prompt cấm gì thì lint bắt cái đó). Điểm 0 = sạch. Lỗi văn phong tinh tế hơn
(thành ngữ dịch word-by-word, giọng kể lệch...) máy không bắt được → đọc file xuất ra.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
import random
import re
import sys
from pathlib import Path

# console Windows mặc định cp1252 — in tiếng Việt ("BỎ QUA...") là chết cả run
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# lộ log các lượt sửa (revise/omission/residue) — không có thì lỗi lì không chẩn đoán được
import logging
logging.basicConfig(level=logging.INFO, format="%(levelname).1s %(name)s: %(message)s")

from novelworker import db
from novelworker.translator.worker import check_translation, han_ratio

# ---------- lint: mỗi luật = (tên, regex | hàm) — ăn khớp với điều prompt CẤM ----------

_RULES: list[tuple[str, re.Pattern]] = [
    # đếm "một cái" vô nghĩa sau động từ (cười/nhìn/gật đầu... một cái)
    ("'X một cái' kiểu convert", re.compile(r"(?:cười|nhìn|liếc|gật đầu|thở dài|vỗ|đá|đấm|lắc đầu|hôn|ôm|cắn|nhảy|hét|quét)\s+một cái", re.I)),
    ("'tiến hành/thực hiện + động từ'", re.compile(r"\b(?:tiến hành|thực hiện)\s+(?:tấn công|phòng ngự|tu luyện|điều tra|chữa trị|luyện chế|thăm dò|so sánh)", re.I)),
    ("'đối với X tới nói'", re.compile(r"đối với\s+[^,.;!?]{1,30}\s+(?:tới|mà)\s+nói", re.I)),
    ("'trên thực tế'", re.compile(r"\btrên thực tế\b", re.I)),
    ("markdown lọt (** # ```)", re.compile(r"\*\*|^#{1,3}\s|```", re.M)),
    ("phiên âm gạch nối (An-đê-ri-an)", re.compile(r"\b[A-ZĐ][a-zà-ỹ]+(?:-[a-zà-ỹ]+){2,}\b")),
    ("'Lão Chủ' (老板 dịch sai)", re.compile(r"\bLão Chủ\b")),
    ("gọi nhân vật 'cậu/bạn' trong lời kể", re.compile(r"(?:^|\. )[^\"“\n]{0,80}\bkỳ vọng (?:cậu|bạn)\b")),
    # 'Anh/Cô' trần mở đầu câu kể — fuse không chặn (sợ oan anh hùng/Nguyên Anh),
    # nhưng đầu câu + động từ thường là đại từ kể sai → người đọc thẩm định
    ("'Anh/Cô' trần đầu câu kể (nghi vấn)", re.compile(r"(?:^|[.!?…]\s+)(?:Anh|Cô)\s+(?!ta\b|ấy\b|trai\b|hùng\b|nương\b|gái\b|em\b)[a-zà-ỹ]+")),
    ("convert 'không khỏi'", re.compile(r"\bkhông khỏi\b", re.I)),
    ("convert 'căn bản là'", re.compile(r"\bcăn bản là\b", re.I)),
    ("convert 'rốt cuộc là'", re.compile(r"\brốt cuộc là\b", re.I)),
    ("convert 'trực tiếp + động từ'", re.compile(r"\btrực tiếp\s+(?:đi|đến|nói|hỏi|ra tay|đánh|giết|ném|đẩy|mở|đóng)\b", re.I)),
    # feedback user 2026-07-11: lượng từ 一头 bê nguyên ("một đầu tam đầu ma long")
    ("lượng từ 'một đầu' (一头)", re.compile(r"\bmột đầu\b(?!\s+tiên)", re.I)),
    # pinyin lọt vào bản dịch — chỉ bắt được dấu macron/caron (ā ǎ) vì sắc/huyền
    # trùng tiếng Việt; pinyin dạng "láng yá" phải nhờ người đọc thẩm định
    ("pinyin lọt (ā ǎ ē...)", re.compile(r"[āēīōūǖǎěǐǒǔǘǚǜ]")),
    ("'gia tộc X' (nên 'X Gia/X thị')", re.compile(r"\b[Gg]ia tộc\s+[A-ZĐ][a-zà-ỹ]*\b")),
    # n1007: 咳咳 dịch thành "Cough cough" — tượng thanh phải là âm Việt
    ("tượng thanh tiếng Anh", re.compile(r"\b(?:cough|sigh|ahem|gasp|hmph|tsk)\b", re.I)),
    ("convert 'tổng cảm thấy' (总感觉)", re.compile(r"\btổng cảm thấy\b", re.I)),
    # Báo chi tiết chuỗi Hán còn sót; production fuse/repair cũng chặn ở lớp cuối.
    ("chữ Hán sót lẻ", re.compile(r"[一-鿿㐀-䶿]+")),
]

# Corpus fidelity: chỉ ghi các nhầm lẫn đã được đọc tay xác nhận. Đây là cảnh báo
# evaluator, không phải fuse — retry mù không thể tự suy ra tên/chức danh đúng.
_FIDELITY_CASES: list[tuple[str, re.Pattern, str]] = [
    ("棒梗", re.compile(r"\bXoạ\s+Trụ\b", re.I), "nhầm 棒梗 thành 傻柱/Xoạ Trụ"),
    ("傻柱", re.compile(r"\bXoạ\s+Trụ\b", re.I), "phiên âm 傻柱 thành pinyin lai 'Xoạ Trụ'"),
    ("一大爷|二大爷|三大爷", re.compile(r"\bdượng\b", re.I),
     "đổi 一/二/三大爷 thành quan hệ 'dượng'"),
]

# feedback user 2026-07-11: "chẳng" rải khắp nơi đọc gượng — mặc định phải là "không"
_CHANG_THRESHOLD = 4

_DIALOGUE = re.compile(
    r'"[^"\n]*"|“[^”]*”|「[^」]*」|^[ \t]*[—–-]\s+[^\n]*', re.M)
_NARRATOR_TERMS = re.compile(
    r"\b(?:hắn|nàng|y|gã|lão|tôi|(?<!chúng\s)(?<!người\s)ta|"
    r"anh(?:\s+ta)?|cậu\s+ta|cô(?:\s+ấy|\s+ta)?|ông\s+ta)\b",
    re.I,
)


def _han_repeat_density(vi: str) -> list[str]:
    """Câu có ≥3 lần 'hắn' → prompt bắt lược chủ ngữ, model lười thì lộ ngay."""
    out = []
    for sent in re.split(r"[.!?…][\"”’]*\s+|\n+", vi):
        if len(re.findall(r"\bhắn\b", sent, re.I)) >= 3:
            out.append(sent.strip()[:90])
    return out


def _exclaim_density(vi: str) -> int:
    """Đoạn có >2 dấu '!' (prompt: mỗi đoạn tối đa 1-2)."""
    return sum(1 for p in vi.split("\n") if p.count("!") > 2)


def narrator_terms(vi: str) -> dict[str, int]:
    """Đếm cách người kể gọi nhân vật, bỏ phần thoại để không trộn hai hệ xưng hô."""
    narration = _DIALOGUE.sub(" ", vi)
    out: dict[str, int] = defaultdict(int)
    for term in _NARRATOR_TERMS.findall(narration):
        out[term.lower()] += 1
    return dict(out)


def fidelity_issues(zh: str, vi: str) -> list[str]:
    """Các lỗi nghĩa/tên đã được xác nhận từ corpus đọc tay."""
    return [label for source, bad, label in _FIDELITY_CASES
            if re.search(source, zh) and bad.search(vi)]


def _self_reference_omissions(zh: str, vi: str) -> list[str]:
    """Metric evaluator; production chỉ nhắc trong prompt và không sửa hậu kỳ."""
    rules = [
        (r"老夫(?!老妻)", ("lão phu", "lão già này", "lão đây")),
        (r"老子", ("lão tử", "ông đây", "bố đây", "ta đây", "bố mày", "ông mày")),
        (r"本座", ("bổn tọa", "bản tọa")),
        (r"在下(?![面方风头边来去])", ("tại hạ",)),
        (r"晚辈", ("vãn bối", "hậu bối")),
    ]
    low = vi.lower()
    return [f"{m.group(0)} thiếu dấu vết ({'/'.join(accepted)})"
            for pat, accepted in rules if (m := re.search(pat, zh))
            and not any(term in low for term in accepted)]


def _dialogue_self_minh(vi: str) -> list[str]:
    """'mình' làm chủ ngữ tự xưng trong thoại/độc thoại — bối cảnh kỳ ảo phải là 'ta'
    hoặc lược. Chỉ bắt dạng chủ ngữ; bỏ qua 'chúng mình/của mình/tự mình/một mình'."""
    hits = []
    for m in _DIALOGUE.finditer(vi):
        seg = m.group(0)
        for hit in re.finditer(r"(?:^|[\"“,.!?…:]\s*)[Mm]ình\s+(?:đã|chắc|sẽ|không|chẳng|phải|cũng|còn|vừa|mới|chết|bị|đang)", seg):
            hits.append(seg[:60])
            break
    return hits


def lint(zh: str, vi: str) -> list[str]:
    problems: list[str] = []
    mech = check_translation(zh, vi)          # fuse cơ học: sót Hán/cụt/mất đoạn
    if mech:
        problems.append(f"[fuse] {mech}")
    # Xưng hô/tự xưng là metric đánh giá prompt, không phải fuse production.
    for missing in _self_reference_omissions(zh, vi):
        problems.append(f"[xưng hô] {missing}")
    for issue in fidelity_issues(zh, vi):
        problems.append(f"[fidelity] {issue}")
    for name, pat in _RULES:
        hits = pat.findall(vi)
        if hits:
            problems.append(f"[lint] {name}: {len(hits)} lần (vd '{str(hits[0])[:40]}')")
    for s in _han_repeat_density(vi)[:3]:
        problems.append(f"[lint] lặp 'hắn' ≥3/câu: {s}")
    n = _exclaim_density(vi)
    if n:
        problems.append(f"[lint] {n} đoạn quá 2 dấu '!'")
    chang = len(re.findall(r"\bchẳng\b", vi, re.I))
    if chang >= _CHANG_THRESHOLD:
        problems.append(f"[văn phong] 'chẳng' ×{chang} — mặc định dùng 'không'")
    for seg in _dialogue_self_minh(vi)[:3]:
        problems.append(f"[xưng hô] 'mình' tự xưng trong thoại (nghi vấn): {seg}")
    return problems


def _self_check() -> None:
    assert _self_reference_omissions("老夫不答应。", "Ta không đồng ý.")
    assert not _self_reference_omissions("老夫不答应。", "Lão phu không đồng ý.")
    terms = narrator_terms('Hắn quay đi. “Lão tử không sợ!” Nàng im lặng.')
    assert terms == {"hắn": 1, "nàng": 1}, terms
    assert any("không khỏi" in p for p in lint("他笑了。", "Hắn không khỏi bật cười."))
    assert any("một đầu" in p for p in lint("一头魔龙。", "Một đầu ma long kinh khủng."))
    assert not any("một đầu" in p for p in lint("首先。", "Một đầu tiên là vậy."))
    assert any("pinyin" in p for p in lint("狼牙棒。", "Cây lāng yá bàng."))
    assert any("'chẳng'" in p for p in lint("。", "Chẳng ai. Chẳng thể. Chẳng còn. Chẳng biết."))
    assert _dialogue_self_minh('“Mình chắc chắn đã bỏ lỡ điều gì đó.”')
    assert not _dialogue_self_minh('“Chúng mình đi thôi, của mình đây.”')
    assert any("gia tộc" in p for p in lint("洛家。", "Gia tộc Lạc không đồng ý."))


# ---------- lấy mẫu ----------

def sample_existing(n: int) -> list[dict]:
    """N chương done ngẫu nhiên, rải đều nhiều truyện (mỗi truyện tối đa 2 chương)."""
    rows = (
        db.sb().table("chapters")
        .select("id, novel_id, chapter_index, title_zh, content_zh, content_vi, model_used, novels(title_vi, genres)")
        .eq("translation_status", "done").not_.is_("content_vi", "null")
        .not_.is_("content_zh", "null")
        .order("translated_at", desc=True).limit(400).execute()
    ).data or []
    random.shuffle(rows)
    picked, per_novel = [], {}
    for r in rows:
        if per_novel.get(r["novel_id"], 0) >= 2:
            continue
        picked.append(r)
        per_novel[r["novel_id"]] = per_novel.get(r["novel_id"], 0) + 1
        if len(picked) >= n:
            break
    return picked


def sample_files(path: str, n: int) -> list[dict]:
    """Đọc bộ eval cố định n<novel>_c<chapter>.txt thay vì chọn DB ngẫu nhiên."""
    rows = []
    for file in sorted(Path(path).glob("n*_c*.txt"))[:n]:
        m = re.fullmatch(r"n(\d+)_c(\d+)\.txt", file.name)
        if not m:
            continue
        novel_id, chapter_index = map(int, m.groups())
        text = file.read_text(encoding="utf-8")
        try:
            payload = text.split("--- GỐC (zh) ---\n", 1)[1]
            zh, vi = payload.split("\n\n--- DỊCH (vi) ---\n", 1)
        except IndexError:
            continue
        title_m = re.search(r"^=== novel .*? \((.*?)\) \[", text, re.M)
        genres_m = re.search(r"^=== thể loại:\s*(.*)$", text, re.M)
        genres = [x.strip() for x in (genres_m.group(1) if genres_m else "").split(",") if x.strip()]
        rows.append({"id": 0, "novel_id": novel_id, "chapter_index": chapter_index,
                     "title_zh": None, "content_zh": zh, "content_vi": vi,
                     "model_used": "(file)", "_from_file": True,
                     "novels": {"title_vi": title_m.group(1) if title_m else "?",
                                "genres": genres}})
    return rows


def translate_fresh(rows: list[dict]) -> list[dict]:
    """Dry-run pipeline production đầy đủ, không ghi chapter/glossary/style vào DB.
    Một chương lì (fuse chặn hết chuỗi provider) chỉ bị BỎ QUA, không giết cả run."""
    from novelworker.translator.providers import build_chain
    llm = build_chain(0)
    out = []
    for r in rows:
        # model lì theo lượt (đo v4/v5: chạy lại là qua) → thử lại 1 lần như queue production
        for attempt in (1, 2):
            try:
                out.append(_translate_one(r, llm))
                break
            except Exception as e:
                verdict = "thử lại" if attempt == 1 else "BỎ QUA"
                print(f"  {verdict} n{r['novel_id']} c{r['chapter_index']}: {str(e)[:120]}")
    return out


def _translate_one(r: dict, llm) -> dict:
    """Dry-run 1 chương qua pipeline production (không ghi DB)."""
    from novelworker.translator import prompts
    from novelworker.translator.worker import (
        GLOSSARY_LINE, _analyze_names, _clean_output, _drop_context_echo,
        _extract_json, _fix_han_residue,
        _merge_names, _pop_summary,
        _quality_fuse, _register_line, _split_chunks, _tail,
    )
    if r.get("_from_file"):
        terms = []
        nv = {**(r.get("novels") or {}), "twopass_active": True}
    else:
        terms, _ = db.get_glossary(r["novel_id"])
        nv = (db.sb().table("novels").select(
            "title_vi,title_zh,genres,translation_provider,translation_model,"
            "translation_style,twopass_active")
            .eq("id", r["novel_id"]).single().execute().data or {})
    chapter_llm = llm
    if nv.get("translation_provider") and nv.get("translation_model"):
        chapter_llm = llm.pin(nv["translation_provider"], nv["translation_model"])

    style = nv.get("translation_style")
    if not style:
        meta = json.dumps({"title": nv.get("title_zh") or nv.get("title_vi"),
                           "genres": nv.get("genres") or []}, ensure_ascii=False)
        try:
            style = _extract_json(chapter_llm.complete(
                prompts.SYSTEM_STYLE,
                f"{meta}\n\nĐoạn mở đầu:\n{r['content_zh'][:2000]}",
                max_tokens=512).text)
        except Exception:
            style = None
    style_line = prompts.build_style_line(style)
    title = nv.get("title_vi") or nv.get("title_zh")
    novel_line = title + (f" — thể loại: {', '.join(nv.get('genres') or [])}"
                          if title and nv.get("genres") else "") if title else None

    prev_summary = prev_tail = None
    if r["chapter_index"] > 1 and not r.get("_from_file"):
        prev = (db.sb().table("chapters").select("summary_vi,content_vi")
                .eq("novel_id", r["novel_id"])
                .eq("chapter_index", r["chapter_index"] - 1)
                .maybe_single().execute())
        pd = getattr(prev, "data", None) or {}
        prev_summary, prev_tail = pd.get("summary_vi"), _tail(pd.get("content_vi"))

    existing_zh = {t["term_zh"] for t in terms if t.get("term_zh")}
    twopass = nv.get("twopass_active", True)
    register_line = _register_line(r["content_zh"])
    parts = []
    for i, chunk in enumerate(_split_chunks(r["content_zh"])):
        if twopass:
            _merge_names(terms, existing_zh, _analyze_names(chapter_llm, chunk))
        res = chapter_llm.complete(
            prompts.build_main_chapter_system(terms, chunk),
            prompts.build_chapter_user(
                r.get("title_zh") if i == 0 else None, chunk, prev_summary,
                prev_tail=prev_tail, novel_line=novel_line, register_line=register_line,
                style_line=style_line),
            validate=_quality_fuse(chunk),
        )
        text = res.text
        m = GLOSSARY_LINE.search(text)
        if m:
            text = text[:m.start()].rstrip()
        text, summary = _pop_summary(text)
        prev_summary = summary or prev_summary
        text = _drop_context_echo(_clean_output(text), prev_tail)
        parts.append(_fix_han_residue(chapter_llm, text, terms))
        prev_tail = _tail(parts[-1])
    text = "\n\n".join(parts)
    return {**r, "content_vi": text, "model_used": "(fresh-full)"}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--existing", type=int, default=0)
    ap.add_argument("--fresh", type=int, default=0)
    ap.add_argument("--out", default="eval_out", help="thư mục xuất cặp zh/vi")
    ap.add_argument("--from-dir", help="dùng bộ n*_c*.txt cố định thay vì lấy mẫu DB")
    ap.add_argument("--self-check", action="store_true", help="chạy kiểm tra evaluator, không gọi DB/API")
    args = ap.parse_args()
    if args.self_check:
        _self_check()
        print("Self-check evaluator: OK")
        return
    if not (args.existing or args.fresh):
        ap.error("cần --existing N hoặc --fresh N")

    count = max(args.existing, args.fresh)
    rows = sample_files(args.from_dir, count) if args.from_dir else sample_existing(count)
    if args.fresh:
        rows = translate_fresh(rows[:args.fresh])
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    total_problems = 0
    report = []
    narrator_by_novel: dict[int, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for r in rows:
        problems = lint(r["content_zh"], r["content_vi"])
        total_problems += len(problems)
        nv = r.get("novels") or {}
        narrator = narrator_terms(r["content_vi"])
        for term, count in narrator.items():
            narrator_by_novel[r["novel_id"]][term] += count
        tag = f"novel {r['novel_id']} ch.{r['chapter_index']} ({nv.get('title_vi', '?')}) [{r.get('model_used')}]"
        report.append({"chapter": tag, "problems": problems, "narrator_terms": narrator})
        fname = outdir / f"n{r['novel_id']}_c{r['chapter_index']}.txt"
        fname.write_text(
            f"=== {tag}\n=== thể loại: {', '.join(nv.get('genres') or [])}\n\n"
            f"--- GỐC (zh) ---\n{r['content_zh']}\n\n--- DỊCH (vi) ---\n{r['content_vi']}\n",
            encoding="utf-8")
        status = "SẠCH" if not problems else f"{len(problems)} vấn đề"
        print(f"{status:>10} | {tag}")
        for p in problems:
            print(f"           - {p}")
    print(f"\nTổng: {len(rows)} chương, {total_problems} vấn đề máy bắt được.")
    print("\nĐại từ người kể theo truyện (chỉ là tín hiệu; nhiều nhân vật có thể cần nhiều cách gọi):")
    for novel_id, terms in narrator_by_novel.items():
        print(f"  novel {novel_id}: " + ", ".join(
            f"{term}={count}" for term, count in sorted(terms.items(), key=lambda x: -x[1])))
    print(f"Cặp zh/vi đã xuất ra {outdir}/ — đọc để thẩm định lỗi văn phong máy không thấy.")
    (outdir / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
