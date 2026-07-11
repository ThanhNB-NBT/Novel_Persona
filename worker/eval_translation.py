"""Bộ eval chất lượng dịch: lấy ngẫu nhiên chương, chấm tự động + xuất file để người/LLM thẩm định.

Hai chế độ:
  --existing N   lấy N chương ĐÃ dịch (done) ngẫu nhiên trong DB → lint + xuất cặp zh/vi
  --fresh N      lấy N chương có content_zh → dịch MỚI bằng model hiện tại → lint + xuất
                 (tốn call NIM; dùng khi muốn đo prompt/model sau chỉnh sửa)

    PYTHONIOENCODING=utf-8 PYTHONPATH=. ../.venv/Scripts/python.exe eval_translation.py --existing 12
    ... eval_translation.py --fresh 3 --out /tmp/eval

Lint bắt các lỗi convert đo được bằng máy (danh sách lỗi lấy từ prompt SYSTEM_CHAPTER —
prompt cấm gì thì lint bắt cái đó). Điểm 0 = sạch. Lỗi văn phong tinh tế hơn
(thành ngữ dịch word-by-word, giọng kể lệch...) máy không bắt được → đọc file xuất ra.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
import random
import re
from pathlib import Path

from novelworker import db
from novelworker.translator.worker import (
    _is_first_person, _register_violation, check_translation, han_ratio,
)

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
]

# Tự xưng có sắc thái trong gốc không được rút hết thành "ta/tôi" hoặc biến mất.
# Đây là warning theo constraint từ vựng; reviewer vẫn quyết định cách Việt hóa đúng ngữ cảnh.
_SELF_REFERENCE_CONSTRAINTS: list[tuple[str, tuple[str, ...]]] = [
    ("老夫", ("lão phu", "lão già này", "lão đây")),
    ("老子", ("lão tử", "ông đây", "bố đây", "ta đây")),
    ("本座", ("bổn tọa",)),
    ("本尊", ("bản tôn", "bổn tôn")),
    ("在下", ("tại hạ",)),
    ("晚辈", ("vãn bối",)),
    ("贫道", ("bần đạo",)),
    ("贫僧", ("bần tăng",)),
    ("哀家", ("ai gia",)),
    ("朕", ("trẫm",)),
    # ponytail: 臣 trần nằm trong 大臣/臣子... và "thần" trần nằm trong tinh thần/thần thông...
    # nên hai chiều đều nhiễu — chỉ match cụm tự xưng rõ
    ("微臣", ("vi thần",)),
    ("臣妾", ("thần thiếp",)),
]

_DIALOGUE = re.compile(r'"[^"\n]*"|“[^”]*”|「[^」]*」')
_NARRATOR_TERMS = re.compile(
    r"\b(?:hắn|nàng|y|gã|lão|anh(?:\s+ta)?|cậu(?:\s+ta)?|cô(?:\s+ấy|\s+ta)?|ông\s+ta)\b",
    re.I,
)


def _han_repeat_density(vi: str) -> list[str]:
    """Câu có ≥3 lần 'hắn' → prompt bắt lược chủ ngữ, model lười thì lộ ngay."""
    out = []
    for sent in re.split(r"[.!?…]\s+", vi):
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


def _self_reference_omissions(zh: str, vi: str) -> list[str]:
    """Bắt tự xưng giàu sắc thái xuất hiện trong gốc nhưng mất khỏi bản dịch."""
    low = vi.lower()
    missing = []
    for source, accepted in _SELF_REFERENCE_CONSTRAINTS:
        count = zh.count(source)
        if count and not any(term in low for term in accepted):
            missing.append(f"{source}×{count} thiếu dấu vết ({'/'.join(accepted)})")
    return missing


def lint(zh: str, vi: str) -> list[str]:
    problems: list[str] = []
    mech = check_translation(zh, vi)          # fuse cơ học: sót Hán/cụt/mất đoạn
    if mech:
        problems.append(f"[fuse] {mech}")
    reg = _register_violation(vi, allow_toi=_is_first_person(zh))  # xưng hô lời kể
    if reg:
        problems.append(f"[fuse] {reg}")
    for missing in _self_reference_omissions(zh, vi):
        problems.append(f"[xưng hô] {missing}")
    for name, pat in _RULES:
        hits = pat.findall(vi)
        if hits:
            problems.append(f"[lint] {name}: {len(hits)} lần (vd '{str(hits[0])[:40]}')")
    for s in _han_repeat_density(vi)[:3]:
        problems.append(f"[lint] lặp 'hắn' ≥3/câu: {s}")
    n = _exclaim_density(vi)
    if n:
        problems.append(f"[lint] {n} đoạn quá 2 dấu '!'")
    return problems


def _self_check() -> None:
    assert _self_reference_omissions("老夫不答应。", "Ta không đồng ý.")
    assert not _self_reference_omissions("老夫不答应。", "Lão phu không đồng ý.")
    terms = narrator_terms('Hắn quay đi. “Lão tử không sợ!” Nàng im lặng.')
    assert terms == {"hắn": 1, "nàng": 1}, terms
    assert any("không khỏi" in p for p in lint("他笑了。", "Hắn không khỏi bật cười."))


# ---------- lấy mẫu ----------

def sample_existing(n: int) -> list[dict]:
    """N chương done ngẫu nhiên, rải đều nhiều truyện (mỗi truyện tối đa 2 chương)."""
    rows = (
        db.sb().table("chapters")
        .select("id, novel_id, chapter_index, content_zh, content_vi, model_used, novels(title_vi, genres)")
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


def translate_fresh(rows: list[dict]) -> list[dict]:
    """Dịch mới bằng pipeline thật (glossary + prompt + fuse trong chain)."""
    from novelworker.translator import prompts
    from novelworker.translator.providers import build_chain
    from novelworker.translator.worker import REGISTER_LINE, _quality_fuse, _split_chunks, _strip_meta
    llm = build_chain(0)
    out = []
    for r in rows:
        terms, _ = db.get_glossary(r["novel_id"])
        parts = []
        for i, chunk in enumerate(_split_chunks(r["content_zh"])):
            res = llm.complete(
                prompts.build_chapter_system(terms, chunk),
                prompts.build_chapter_user(None, chunk, None, register_line=REGISTER_LINE),
                validate=_quality_fuse(chunk),
            )
            parts.append(_strip_meta(res.text))
        out.append({**r, "content_vi": "\n\n".join(parts), "model_used": "(fresh)"})
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--existing", type=int, default=0)
    ap.add_argument("--fresh", type=int, default=0)
    ap.add_argument("--out", default="eval_out", help="thư mục xuất cặp zh/vi")
    ap.add_argument("--self-check", action="store_true", help="chạy kiểm tra evaluator, không gọi DB/API")
    args = ap.parse_args()
    if args.self_check:
        _self_check()
        print("Self-check evaluator: OK")
        return
    if not (args.existing or args.fresh):
        ap.error("cần --existing N hoặc --fresh N")

    rows = sample_existing(max(args.existing, args.fresh))
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
