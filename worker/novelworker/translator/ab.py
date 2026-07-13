"""Chạy A/B hai bộ dịch trên cùng chương, không ghi kết quả vào bảng production."""
from __future__ import annotations

import json
from html import escape
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass

from . import prompts


V2_DIRECTIVE = """
[BỘ DỊCH V2 — ưu tiên đọc dễ]
Trước khi viết, hãy xác định người nói, đối tượng, giới tính, quan hệ và nghĩa của
thành ngữ/từ ngữ trong đoạn. Sau đó chỉ xuất bản bản dịch tiếng Việt cuối cùng.
Ưu tiên theo thứ tự: đúng nghĩa > không bỏ sót > nhất quán tên/xưng hô > tự nhiên.
Không phóng tác, không thêm cảm xúc, không rút gọn, không giải thích.
Mỗi đoạn, mỗi tin tức và mỗi câu trong bản gốc đều phải xuất hiện trong bản dịch;
không gộp hai đoạn tin thành một, không bỏ tin thứ hai/thứ ba, không tóm tắt danh sách.
Giữ thứ tự đoạn và thứ tự ý; nếu câu Trung dài thì tách câu Việt nhưng không được bỏ
mệnh đề cuối. Tên và thuật ngữ đã có trong bảng bắt buộc dùng đúng một cách viết.
Nếu input có tiêu đề, giữ tiêu đề ở dòng đầu; nếu không có, không được tự đặt tiêu đề.
Không xuất SUMMARY/GLOSSARY hay markdown; output chỉ là bản dịch.
"""

REFERENCE_DIRECTIVE = """
[BỘ DỊCH C — đối chiếu bám nguyên văn]
Dịch trực tiếp từ bản gốc tiếng Trung sang tiếng Việt để làm bản đối chiếu.
Bắt buộc giữ số đoạn và thứ tự đoạn: mỗi đoạn Trung phải có một đoạn Việt tương ứng,
không gộp hai đoạn, không bỏ đoạn, không thêm đoạn. Ưu tiên đúng nghĩa và đầy đủ
hơn văn chương. Dịch 追查 là điều tra/truy tìm, không dịch thành truy sát nếu không
có ý giết hoặc tiêu diệt. Nếu input có tiêu đề thì dịch tiêu đề; nếu không có thì
không tự đặt tiêu đề. Chỉ xuất bản dịch, không SUMMARY, GLOSSARY hay giải thích.
"""

def _system_v2(terms: list[dict], chunk: str, variant: str) -> str:
    # Tái sử dụng khối glossary/luật an toàn hiện có; V2 chỉ thay chiến lược đầu ra.
    if variant == "reference":
        return prompts.build_reference_chapter_system(terms, chunk)
    return prompts.build_chapter_system(terms, chunk) + "\n" + V2_DIRECTIVE


def _drop_invented_title(text: str, title_zh: str | None) -> str:
    """A/B không cho model biến câu mở đầu thành tiêu đề nếu input không có title."""
    if title_zh:
        return text
    lines = text.splitlines()
    if lines and lines[0].strip().lower().startswith(("tiêu đề:", "tieu de:")):
        return "\n".join(lines[1:]).lstrip()
    return text


@dataclass
class VariantResult:
    variant: str
    text: str
    model: str
    prompt_tokens: int = 0
    completion_tokens: int = 0
    error: str | None = None


def translate_variant(
    content_zh: str,
    terms: list[dict],
    llm,
    variant: str,
    *,
    title_zh: str | None = None,
    prev_summary: str | None = None,
    prev_tail: str | None = None,
    novel_line: str | None = None,
    register_line: str | None = None,
    style_line: str | None = None,
) -> VariantResult:
    """Dịch một bản thử nghiệm; không ghi chương/glossary và không sửa dữ liệu dịch."""
    # Lazy import để self-check prompt chạy được trong môi trường không cài DB client.
    from .worker import (
        GLOSSARY_LINE, _clean_output, _fix_han_residue,
        _pop_summary, _quality_fuse, _split_chunks, _tail,
    )
    if variant not in {"current", "v2", "reference"}:
        raise ValueError(f"variant khong hop le: {variant}")

    parts: list[str] = []
    errors: list[str] = []
    model = ""
    prompt_tokens = completion_tokens = 0
    for index, chunk in enumerate(_split_chunks(content_zh)):
        system = (prompts.build_chapter_system(terms, chunk)
                  if variant == "current" else _system_v2(terms, chunk, variant))
        result = llm.complete(
            system,
            prompts.build_chapter_user(
                title_zh if index == 0 else None,
                chunk,
                prev_summary,
                prev_tail=prev_tail,
                novel_line=novel_line,
                register_line=register_line,
                style_line=style_line,
            ),
            validate=_quality_fuse(chunk),
        )
        text = result.text
        match = GLOSSARY_LINE.search(text)
        if match:
            text = text[:match.start()].rstrip()
        text, summary = _pop_summary(text)
        prev_summary = summary or prev_summary
        text = _clean_output(text)
        try:
            text = _fix_han_residue(llm, text, terms)
        except RuntimeError as exc:
            # A/B phải giữ được các bản còn lại khi một model không sửa được Hán tự sót.
            errors.append(str(exc))
        parts.append(text)
        prev_tail = _tail(text)
        model = result.model
        prompt_tokens += result.prompt_tokens or 0
        completion_tokens += result.completion_tokens or 0

    text = "\n\n".join(parts).strip()
    return VariantResult(variant, _drop_invented_title(text, title_zh), model,
                         prompt_tokens, completion_tokens,
                         "; ".join(errors) if errors else None)


def compare_chapter(row: dict, terms: list[dict], chains: tuple, *, parallel: bool = True) -> dict:
    """So sánh hai bộ trên đúng một input và trả payload JSON-serializable."""
    common = {
        "content_zh": row["content_zh"],
        "terms": terms,
        "title_zh": row.get("title_zh"),
        "novel_line": row.get("novel_line"),
        "register_line": row.get("register_line"),
        "style_line": row.get("style_line"),
        "prev_summary": row.get("prev_summary"),
        "prev_tail": row.get("prev_tail"),
    }

    def run(args):
        variant, chain = args
        try:
            return translate_variant(**common, llm=chain, variant=variant)
        except Exception as exc:
            return VariantResult(variant, "", "", error=f"{type(exc).__name__}: {exc}")

    if parallel:
        with ThreadPoolExecutor(max_workers=3) as pool:
            results = list(pool.map(run, (("current", chains[0]), ("v2", chains[1]),
                                          ("reference", chains[2]))))
    else:
        results = [run(("current", chains[0])), run(("v2", chains[1])),
                   run(("reference", chains[2]))]
    return {
        "chapter_id": row.get("id"),
        "novel_id": row.get("novel_id"),
        "chapter_index": row.get("chapter_index"),
        "title_zh": row.get("title_zh"),
        "content_zh": row["content_zh"],
        "results": [asdict(item) for item in results],
    }


def dumps(payload: dict) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2)


def render_html(payloads: list[dict], title: str = "A/B translation") -> str:
    """Viewer tĩnh để đọc nguyên văn và hai bản dịch cạnh nhau."""
    nav = "".join(
        f'<a href="#c-{p.get("chapter_index")}">Chương {p.get("chapter_index")}</a>'
        for p in payloads
    )
    sections = []
    for payload in payloads:
        results = {item["variant"]: item for item in payload["results"]}
        current = results.get("current", {})
        v2 = results.get("v2", {})
        reference = results.get("reference", {})
        def status(item: dict) -> str:
            return f" · FAIL: {escape(item.get('error', ''))}" if item.get("error") else ""
        source = escape(payload.get("content_zh") or "")
        sections.append(f"""
        <section id="c-{payload.get('chapter_index')}">
          <h2>Chương {payload.get('chapter_index')}</h2>
          <details class="source"><summary>Bản gốc tiếng Trung</summary><pre>{source}</pre></details>
          <div class="grid">
            <details class="card v2" open><summary>V2 (chu dao){status(v2)} <small>{escape(v2.get('model', ''))}</small></summary>
              <pre>{escape(v2.get('text', ''))}</pre></details>
            <details class="card"><summary>Current{status(current)} <small>{escape(current.get('model', ''))}</small></summary>
              <pre>{escape(current.get('text', ''))}</pre></details>
            <details class="card reference"><summary>Reference{status(reference)} <small>{escape(reference.get('model', ''))}</small></summary>
              <pre>{escape(reference.get('text', ''))}</pre></details>
          </div>
        </section>""")
    return f"""<!doctype html>
<html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{escape(title)}</title>
<style>
body{{margin:0;background:#101318;color:#e8ecf1;font:16px/1.65 system-ui,sans-serif}}
header{{position:sticky;top:0;padding:14px 4vw;background:#181d25ee;backdrop-filter:blur(8px);z-index:2}}
nav{{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}}nav a{{color:#9cc8ff;text-decoration:none;padding:3px 8px;border:1px solid #344052;border-radius:5px}}
main{{max-width:1500px;margin:auto;padding:20px 4vw}}section{{scroll-margin-top:100px;margin:28px 0 55px}}h2{{border-bottom:1px solid #303846;padding-bottom:8px}}
details{{background:#171c23;border:1px solid #303846;border-radius:8px;padding:10px;margin-bottom:14px}}summary{{cursor:pointer;color:#b8c2d0}}
.grid{{display:grid;grid-template-columns:1fr 1fr 1fr;gap:14px}}.card{{min-width:0;border:1px solid #40516a;border-radius:8px;overflow:hidden;padding:0}}.card summary{{padding:9px 12px;background:#202a38;color:#b9d7ff}}.card.v2{{border-color:#3d8064}}.card.v2 summary{{background:#1d332b;color:#a9e4c2}}
button{{background:#263447;color:#dce8f7;border:1px solid #435571;border-radius:5px;padding:5px 9px;cursor:pointer}}small{{float:right;color:#8b98aa;font-weight:normal}}
pre{{white-space:pre-wrap;word-break:break-word;margin:0;padding:14px;min-height:120px;font:inherit;background:#12161c}}
article.reference{{border-color:#92753f}}.reference h3{{background:#3a3020;color:#f0d49a}}
@media(max-width:1100px){{.grid{{grid-template-columns:1fr}}}}
</style><header><strong>{escape(title)}</strong>
<button onclick="document.querySelectorAll('details.card').forEach(x=>x.open=true)">Mo tat ca</button>
<button onclick="document.querySelectorAll('details.card').forEach(x=>x.open=false)">Thu gon tat ca</button>
<nav>{nav}</nav></header><main>{''.join(sections)}</main></html>"""


def _self_check() -> None:
    assert "BỘ DỊCH V2" in V2_DIRECTIVE
    assert "chỉ là bản dịch" in V2_DIRECTIVE


if __name__ == "__main__":
    _self_check()
    print("AB translator self-check: OK")
