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
import html
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
logging.getLogger("httpx").setLevel(logging.WARNING)  # log request Supabase chỉ là nhiễu

from novelworker import db
from novelworker.translator import lint as translation_lint

# ---------- lint: mỗi luật = (tên, regex | hàm) — ăn khớp với điều prompt CẤM ----------

_FIDELITY_CASES: list[tuple[str, re.Pattern, str]] = [
    ("棒梗", re.compile(r"\bXoạ\s+Trụ\b", re.I), "nhầm 棒梗 thành 傻柱/Xoạ Trụ"),
    ("傻柱", re.compile(r"\bXoạ\s+Trụ\b", re.I), "phiên âm 傻柱 thành pinyin lai 'Xoạ Trụ'"),
    ("一大爷|二大爷|三大爷", re.compile(r"\bdượng\b", re.I),
     "đổi 一/二/三大爷 thành quan hệ 'dượng'"),
]

_han_repeat_density = translation_lint._han_repeat_density
_dialogue_self_minh = translation_lint._dialogue_self_minh
_self_reference_omissions = translation_lint._self_reference_omissions
narrator_terms = translation_lint.narrator_terms


def fidelity_issues(zh: str, vi: str) -> list[str]:
    """Các lỗi nghĩa/tên đã được xác nhận từ corpus đọc tay."""
    return [label for source, bad, label in _FIDELITY_CASES
            if re.search(source, zh) and bad.search(vi)]


def lint(zh: str, vi: str) -> list[str]:
    problems: list[str] = []
    # Chỉ giữ cảnh báo mềm để đọc mẫu; không dùng các lỗi cứng làm điểm loại.
    problems.extend(translation_lint._self_reference_warnings(zh, vi))
    for issue in fidelity_issues(zh, vi):
        problems.append(f"[fidelity] {issue}")
    problems.extend(translation_lint._style_warnings(vi))
    return problems


def quality_score(zh: str, vi: str) -> tuple[int, list[str]]:
    """Điểm xếp hạng mềm 0–100, không phải validator.

    Chỉ dùng để ưu tiên chương cần đọc: độ dài tương đối, độ phủ đoạn, lặp cụm
    và lặp đại từ. Không tự loại bản dịch; chữ Hán chỉ được sửa ở _fix_han_residue.
    """
    if not (vi or "").strip():
        return 0, ["bản dịch rỗng"]
    score = 100
    signals: list[str] = []
    zh_len, vi_len = max(len(zh or ""), 1), len(vi)
    ratio = vi_len / zh_len
    if ratio < 0.55:
        score -= 18
        signals.append(f"bản dịch ngắn ({ratio:.1f}x gốc)")
    elif ratio < 0.75:
        score -= 8
        signals.append(f"bản dịch hơi ngắn ({ratio:.1f}x gốc)")
    elif ratio > 4.5:
        score -= 15
        signals.append(f"bản dịch phình ({ratio:.1f}x gốc)")
    elif ratio > 3.8:
        score -= 7
        signals.append(f"bản dịch hơi dài ({ratio:.1f}x gốc)")

    zh_lines = sum(1 for line in (zh or "").splitlines() if line.strip())
    vi_lines = sum(1 for line in vi.splitlines() if line.strip())
    if zh_lines >= 8 and vi_lines < 0.55 * zh_lines:
        score -= 12
        signals.append(f"độ phủ đoạn thấp ({vi_lines}/{zh_lines})")

    repeated = re.findall(r"(?i)\b([\wÀ-ỹ]+(?:\s+[\wÀ-ỹ]+){1,4})\s+\1\b", vi)
    if repeated:
        penalty = min(15, len(repeated) * 4)
        score -= penalty
        signals.append(f"lặp cụm ({len(repeated)})")

    narrator_repeat = translation_lint._han_repeat_density(vi)
    if narrator_repeat:
        penalty = min(12, len(narrator_repeat) * 3)
        score -= penalty
        signals.append(f"lặp đại từ trong câu ({len(narrator_repeat)})")
    return max(0, min(100, score)), signals


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
    clean_score, _ = quality_score("他走进大厅。", "Hắn bước vào đại sảnh.")
    short_score, _ = quality_score("他走进大厅。" * 20, "Hắn bước vào.")
    assert clean_score > short_score and 0 <= clean_score <= 100


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
    files = []
    for file in Path(path).glob("n*_c*.txt"):
        m = re.fullmatch(r"n(\d+)_c(\d+)\.txt", file.name)
        if not m:
            continue
        novel_id, chapter_index = map(int, m.groups())
        files.append((novel_id, chapter_index, file))
    for novel_id, chapter_index, file in sorted(files)[:n]:
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


_PROBLEM_TAG = re.compile(r"^\[([^\]]+)\]")
_PROBLEM_EXCERPTS = re.compile(r"'([^']{4,90})'|: ([^(\n]{12,90})$")


def _problem_excerpts(problems: list[str]) -> list[str]:
    """Trích đoạn văn dính lỗi từ message cảnh báo (vd '...' hoặc câu sau dấu ':')
    để highlight trong bản dịch — người rà nhảy thẳng tới chỗ lỗi thay vì đọc dò."""
    out: list[str] = []
    for p in problems:
        for a, b in _PROBLEM_EXCERPTS.findall(p):
            s = (a or b).strip()
            if s and s not in out:
                out.append(s)
    return out


_SAMPLES_FILE = Path(__file__).parent / "test" / "fixtures" / "translation_style_samples.txt"


def _load_style_samples() -> dict[tuple[int, int], str]:
    """Bản mẫu chuẩn đã duyệt → {(novel_id, chapter_index): text} để report đặt cạnh
    bản dịch đang chấm. Novel id lấy từ header file ("n1380 c50–59")."""
    try:
        text = _SAMPLES_FILE.read_text(encoding="utf-8")
    except OSError:
        return {}
    m = re.search(r"n(\d+)\s+c\d+", text)
    if not m:
        return {}
    novel_id = int(m.group(1))
    out: dict[tuple[int, int], str] = {}
    parts = re.split(r"^## Chương (\d+)\s*$", text, flags=re.M)
    for num, body in zip(parts[1::2], parts[2::2]):
        # bỏ dòng kẻ --- và ghi chú cuối file
        body = body.split("\n---", 1)[0].strip()
        if body:
            out[(novel_id, int(num))] = body
    return out


def _write_html(outdir: Path, rows: list[dict], report: list[dict]) -> None:
    """Báo cáo tĩnh tự chứa: nguồn, bản dịch đang chấm, bản mẫu chuẩn (nếu có) và lỗi máy."""
    esc = lambda value: html.escape(str(value or ""))
    samples = _load_style_samples()

    def mark(text: str, excerpts: list[str]) -> str:
        """Escape rồi bọc <mark> quanh đoạn dính lỗi (so trên bản đã escape cho khớp)."""
        out = esc(text)
        for ex in excerpts:
            out = out.replace(esc(ex), f"<mark>{esc(ex)}</mark>")
        return out

    issue_count = sum(len(item["problems"]) for item in report)
    failed = sum(bool(row.get("_fresh_error")) for row in rows)
    all_tags: dict[str, int] = {}
    cards = []
    for i, (row, item) in enumerate(zip(rows, report)):
        problems = item["problems"]
        score = item.get("quality_score", 0)
        status = "error" if row.get("_fresh_error") else ("dirty" if problems else "clean")
        badge = row.get("_fresh_error") or f"Điểm {score}/100"
        tags = sorted({m.group(1) for p in problems if (m := _PROBLEM_TAG.match(p))})
        for t in tags:
            all_tags[t] = all_tags.get(t, 0) + 1
        chips = "".join(f'<i class="chip">{esc(t)}</i>' for t in tags)
        issues = "".join(f"<li>{esc(problem)}</li>" for problem in problems)
        excerpts = _problem_excerpts(problems)
        # bản mẫu chuẩn đặt cạnh bản đang chấm — so giọng trực tiếp, khỏi mở 2 file
        sample = samples.get((row.get("novel_id"), row.get("chapter_index")))
        sample_col = (f'<section><h3>Bản mẫu chuẩn</h3><pre>{esc(sample)}</pre></section>'
                      if sample else "")
        cards.append(f"""
<details class="chapter {status}" id="c{i}" data-status="{status}" data-tags="{esc(' '.join(tags))}" data-search="{esc(item['chapter']).lower()}">
  <summary><span class="title">{esc(item['chapter'])}</span>{chips}<b>{esc(badge)}</b></summary>
  <div class="issues"><b>Điểm chất lượng mềm: {score}/100</b>{f'<ul>{issues}</ul>' if issues else '<span> Không có cảnh báo mềm.</span>'}</div>
  <div class="columns">
    <section><h3>Nguyên văn Trung</h3><pre lang="zh">{esc(row.get('content_zh'))}</pre></section>
    <section><h3>Bản dịch hiện tại</h3><pre>{mark(row.get('content_vi') or '', excerpts)}</pre></section>
    {sample_col}
  </div>
</details>""")
    tag_chips = "".join(
        f'<button class="tag" data-tag="{esc(t)}">{esc(t)} · {n}</button>'
        for t, n in sorted(all_tags.items(), key=lambda kv: -kv[1]))
    page = f"""<!doctype html>
<html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Validation bản dịch</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;800&display=swap" rel="stylesheet">
<style>
:root{{--bg:#0b1020;--panel:#121a2d;--line:#263451;--text:#e8edf8;--muted:#91a0bd;--ok:#40c98b;--bad:#ffbd59;--err:#ff6b75;--accent:#9db8f5}}
*{{box-sizing:border-box}} body{{margin:0;background:var(--bg);color:var(--text);font:15px/1.6 Nunito,system-ui,sans-serif}}
main{{max-width:1700px;margin:auto;padding:24px}} h1{{margin:0 0 6px;font-weight:800}} .muted{{color:var(--muted)}}
.stats,.tools{{display:flex;gap:12px;flex-wrap:wrap;margin:14px 0;align-items:center}}
.stat,.tools input,.tools select,.tools button{{background:var(--panel);border:1px solid var(--line);border-radius:10px;color:var(--text);padding:9px 14px;font:inherit}}
.stat b{{font-size:22px;display:block;font-weight:800}} .tools input{{min-width:260px;flex:1}} button{{cursor:pointer}}
.tags{{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 14px}}
.tag{{background:var(--panel);border:1px solid var(--line);border-radius:999px;color:var(--muted);padding:5px 12px;font:600 13px Nunito,sans-serif;cursor:pointer}}
.tag.on{{border-color:var(--bad);color:var(--bad)}}
.chapter{{background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--ok);border-radius:12px;margin:10px 0;overflow:hidden}}
.chapter.dirty{{border-left-color:var(--bad)}} .chapter.error{{border-left-color:var(--err)}}
summary{{cursor:pointer;padding:12px 16px;display:flex;align-items:center;gap:10px}}
summary .title{{flex:1;font-weight:600}} summary b{{color:var(--ok);white-space:nowrap;font-weight:800}}
.dirty summary b{{color:var(--bad)}} .error summary b{{color:var(--err)}}
.chip{{font:600 12px Nunito,sans-serif;font-style:normal;color:var(--bad);border:1px solid var(--line);border-radius:999px;padding:2px 9px;white-space:nowrap}}
.issues{{padding:0 16px 12px;color:var(--muted)}} .issues ul{{margin:0;padding-left:20px;color:var(--bad)}}
.columns{{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));border-top:1px solid var(--line)}}
section{{min-width:0;padding:14px;border-right:1px solid var(--line)}}
h3{{margin:0 0 8px;color:var(--accent);font-size:12px;text-transform:uppercase;letter-spacing:.06em;position:sticky;top:0;background:var(--panel);padding:4px 0}}
pre{{white-space:pre-wrap;word-break:break-word;margin:0;max-height:72vh;overflow:auto;font:15px/1.75 Nunito,system-ui,sans-serif}}
pre[lang=zh]{{font-family:Nunito,'Noto Sans SC',system-ui,sans-serif}}
mark{{background:rgba(255,189,89,.28);color:var(--bad);border-radius:3px;padding:0 2px}}
.hidden{{display:none}}
.nav{{position:fixed;right:18px;bottom:18px;display:flex;flex-direction:column;gap:8px}}
.nav button{{width:44px;height:44px;border-radius:12px;font-size:18px;font-weight:800}}
</style></head><body><main>
<h1>Validation bản dịch Trung → Việt</h1><div class="muted">Corpus cố định · bấm chip loại lỗi để lọc · nút ▲▼ nhảy giữa các chương có lỗi · đoạn dính lỗi được tô trong bản dịch</div>
<div class="stats"><div class="stat"><b>{len(rows)}</b>chương</div><div class="stat"><b>{issue_count}</b>cảnh báo</div><div class="stat"><b>{failed}</b>request thất bại</div></div>
<div class="tools"><input id="q" placeholder="Tìm truyện hoặc chương…"><select id="status"><option value="">Tất cả</option><option value="clean">Sạch</option><option value="dirty">Có cảnh báo</option><option value="error">Request lỗi</option></select><button id="open">Mở tất cả</button><button id="close">Đóng tất cả</button></div>
<div class="tags">{tag_chips}</div>
{''.join(cards)}
</main>
<div class="nav"><button id="prev" title="Chương lỗi trước (k)">▲</button><button id="next" title="Chương lỗi kế (j)">▼</button></div>
<script>
const cards=[...document.querySelectorAll('.chapter')],q=document.querySelector('#q'),s=document.querySelector('#status');
let tagOn=null;
function filter(){{const text=q.value.toLowerCase();cards.forEach(c=>c.classList.toggle('hidden',
  (s.value&&c.dataset.status!==s.value)||(tagOn&&!c.dataset.tags.split(' ').includes(tagOn))||!c.dataset.search.includes(text)))}}
q.oninput=s.onchange=filter;
document.querySelectorAll('.tag').forEach(b=>b.onclick=()=>{{tagOn=tagOn===b.dataset.tag?null:b.dataset.tag;
  document.querySelectorAll('.tag').forEach(x=>x.classList.toggle('on',x.dataset.tag===tagOn));filter()}});
document.querySelector('#open').onclick=()=>cards.filter(c=>!c.classList.contains('hidden')).forEach(c=>c.open=true);
document.querySelector('#close').onclick=()=>cards.forEach(c=>c.open=false);
// nhảy giữa các chương CÓ LỖI đang hiện — rà nhanh không phải cuộn dò
function bads(){{return cards.filter(c=>!c.classList.contains('hidden')&&c.dataset.status!=='clean')}}
let at=-1;
function go(d){{const b=bads();if(!b.length)return;at=(at+d+b.length)%b.length;b[at].open=true;b[at].scrollIntoView({{behavior:'smooth',block:'start'}})}}
document.querySelector('#next').onclick=()=>go(1);document.querySelector('#prev').onclick=()=>go(-1);
document.onkeydown=e=>{{if(e.target.tagName!=='INPUT'){{if(e.key==='j')go(1);if(e.key==='k')go(-1)}}}};
</script></body></html>"""
    (outdir / "index.html").write_text(page, encoding="utf-8")


def translate_fresh(rows: list[dict]) -> list[dict]:
    """Dry-run pipeline production đầy đủ, không ghi chapter/glossary/style vào DB.
    Một chương lì (fuse chặn hết chuỗi provider) chỉ bị BỎ QUA, không giết cả run."""
    from novelworker.translator.providers import build_chain
    out = []
    carries: dict[int, dict] = {}
    for slot, r in enumerate(rows):
        # Một provider nhưng nhiều key/tài khoản: chia chương theo slot như worker production.
        llm = build_chain(slot)
        # model lì theo lượt (đo v4/v5: chạy lại là qua) → thử lại 1 lần như queue production
        for attempt in (1, 2):
            try:
                out.append(_translate_one(r, llm, carries.setdefault(r["novel_id"], {})))
                break
            except Exception as e:
                verdict = "thử lại" if attempt == 1 else "BỎ QUA"
                print(f"  {verdict} n{r['novel_id']} c{r['chapter_index']}: {str(e)[:120]}")
                if attempt == 2:
                    out.append({**r, "content_vi": "",
                                "model_used": "(fresh-failed)", "_fresh_error": str(e)})
    return out


def _translate_one(r: dict, llm, carry: dict | None = None) -> dict:
    """Dry-run 1 chương qua pipeline production (không ghi DB)."""
    from novelworker.translator import prompts
    from novelworker.translator.worker import (
        GLOSSARY_LINE, _analyze_names, _clean_output, _drop_context_echo,
        _extract_json, _fix_han_residue,
        _merge_names, _pop_summary,
        _register_line, _split_chunks, _tail,
    )
    if r.get("_from_file"):
        terms = [dict(term) for term in ((carry or {}).get("terms") or [])]
        if not terms:
            # Chương đầu của truyện trong lượt chạy: nạp glossary DB như production —
            # không có nó tên tự trôi mỗi lượt (Tử Thần/Thần Chết), đo không đại diện.
            try:
                terms, _ = db.get_glossary(r["novel_id"])
            except Exception as e:
                print(f"  (không nạp được glossary n{r['novel_id']}: {e} — chạy glossary rỗng)")
        nv = {**(r.get("novels") or {}),
              "translation_style": (carry or {}).get("style")}
    else:
        terms, _ = db.get_glossary(r["novel_id"])
        nv = (db.sb().table("novels").select(
            "title_vi,title_zh,genres,translation_provider,translation_model,"
            "translation_style")
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

    prev_summary = (carry or {}).get("prev_summary") if r.get("_from_file") else None
    prev_tail = (carry or {}).get("prev_tail") if r.get("_from_file") else None
    if r["chapter_index"] > 1 and not r.get("_from_file"):
        prev = (db.sb().table("chapters").select("summary_vi,content_vi")
                .eq("novel_id", r["novel_id"])
                .eq("chapter_index", r["chapter_index"] - 1)
                .maybe_single().execute())
        pd = getattr(prev, "data", None) or {}
        prev_summary, prev_tail = pd.get("summary_vi"), _tail(pd.get("content_vi"))

    existing_zh = {t["term_zh"] for t in terms if t.get("term_zh")}
    register_line = _register_line(r["content_zh"])
    parts = []
    for i, chunk in enumerate(_split_chunks(r["content_zh"])):
        _merge_names(terms, existing_zh, _analyze_names(chapter_llm, chunk))
        res = chapter_llm.complete(
            prompts.build_main_chapter_system(terms, chunk),
            prompts.build_chapter_user(
                r.get("title_zh") if i == 0 else None, chunk, prev_summary,
                prev_tail=prev_tail, novel_line=novel_line, register_line=register_line,
                style_line=style_line),
            temperature=prompts.CHAPTER_TEMPERATURE,
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
    from novelworker.translator.worker import _fix_register, _fix_soft_style
    text = _fix_register(_fix_soft_style("\n\n".join(parts)))  # cùng hậu xử lý với production
    if carry is not None:
        carry.update({"terms": terms, "style": style,
                      "prev_summary": prev_summary, "prev_tail": prev_tail})
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
        score, signals = quality_score(r["content_zh"], r["content_vi"])
        total_problems += len(problems)
        nv = r.get("novels") or {}
        narrator = narrator_terms(r["content_vi"])
        for term, count in narrator.items():
            narrator_by_novel[r["novel_id"]][term] += count
        tag = f"novel {r['novel_id']} ch.{r['chapter_index']} ({nv.get('title_vi', '?')}) [{r.get('model_used')}]"
        report.append({"chapter": tag, "problems": problems, "quality_score": score,
                       "quality_signals": signals, "narrator_terms": narrator})
        fname = outdir / f"n{r['novel_id']}_c{r['chapter_index']}.txt"
        fname.write_text(
            f"=== {tag}\n=== thể loại: {', '.join(nv.get('genres') or [])}\n\n"
            f"--- GỐC (zh) ---\n{r['content_zh']}\n\n--- DỊCH (vi) ---\n{r['content_vi']}\n",
            encoding="utf-8")
        status = f"{score}/100"
        print(f"{status:>10} | {tag}")
        for p in problems:
            print(f"           - {p}")
    avg_score = (sum(item["quality_score"] for item in report) / len(report)) if report else 0
    print(f"\nTổng: {len(rows)} chương, điểm chất lượng mềm trung bình {avg_score:.1f}/100.")
    print(f"Cảnh báo mềm máy bắt được: {total_problems} (không dùng để loại bản dịch).")
    print("\nĐại từ người kể theo truyện (chỉ là tín hiệu; nhiều nhân vật có thể cần nhiều cách gọi):")
    for novel_id, terms in narrator_by_novel.items():
        print(f"  novel {novel_id}: " + ", ".join(
            f"{term}={count}" for term, count in sorted(terms.items(), key=lambda x: -x[1])))
    print(f"Cặp zh/vi đã xuất ra {outdir}/ — đọc để thẩm định lỗi văn phong máy không thấy.")
    (outdir / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    _write_html(outdir, rows, report)


if __name__ == "__main__":
    main()
