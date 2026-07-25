r"""Khai thác biến thể term từ chương đã dịch trong DB và đo exact post-edit.

Script chỉ đọc Supabase và chạy Hachimi local, không ghi production.
"""
from __future__ import annotations

import argparse
import json
import re
import time
from collections import Counter, defaultdict
from pathlib import Path

from novelworker import db
from novelworker.translator import hachimi_engine
from novelworker.translator.text_clean import clean_source

from termguard_research import _source_spans

_EOS = "</s>"


def _term_spans(
    normalized: str,
    source_spans: list[tuple[int, int]],
    term_zh: str,
) -> list[list[int]]:
    spans: list[list[int]] = []
    for match in re.finditer(re.escape(term_zh), normalized):
        spans.append([
            i for i, (start, end) in enumerate(source_spans)
            if end > match.start() and start < match.end()
        ])
    return spans


def _candidate_span(
    attention: list[list[float]],
    target_count: int,
    source_indexes: list[int],
) -> list[int]:
    indexes = [
        target_i
        for target_i, weights in enumerate(attention[:target_count])
        if max(range(len(weights)), key=weights.__getitem__) in source_indexes
    ]
    if not indexes:
        return []
    groups: list[list[int]] = []
    for index in indexes:
        if not groups or index > groups[-1][-1] + 1:
            groups.append([index])
        else:
            groups[-1].append(index)
    return max(
        groups,
        key=lambda group: sum(
            sum(attention[target_i][source_i] for source_i in source_indexes)
            for target_i in group
        ),
    )


def _replace_variants(text: str, variants: list[str], correct_vi: str) -> tuple[str, int]:
    replaced = 0
    for variant in sorted(set(variants), key=len, reverse=True):
        pattern = re.compile(rf"(?<!\w){re.escape(variant)}(?!\w)", re.IGNORECASE)
        text, count = pattern.subn(correct_vi, text)
        replaced += count
    return text, replaced


def _marker_pattern(marker: str, alphabet: str) -> re.Pattern[str]:
    body = r"[ \t]*".join(re.escape(char) for char in marker)
    return re.compile(rf"(?<![{re.escape(alphabet)}]){body}(?![{re.escape(alphabet)}])")


def _measure_placeholder_cascade(
    rows: list[dict],
    engine,
    term_zh: str,
    correct_vi: str,
    normal_repaired: list[str],
) -> dict:
    remaining = list(range(len(rows)))
    stages: list[dict] = []
    resolved_occurrences = 0
    started = time.perf_counter()
    for name, marker, alphabet in (
        ("alnum", "ZX001Q", "ZX0123456789Q"),
        ("jwzf", "JW", "JWZF"),
        ("bracket", "⟦001⟧", "⟦0123456789⟧"),
    ):
        sources = [
            engine.src.encode(
                rows[index]["source"].replace(term_zh, f" {marker} "),
                out_type=str,
            ) + [_EOS]
            for index in remaining
        ]
        results = engine.translator.translate_batch(
            sources,
            max_batch_size=32,
            beam_size=4,
            max_decoding_length=180,
        )
        pattern = _marker_pattern(marker, alphabet)
        next_remaining: list[int] = []
        success_lines = success_occurrences = 0
        failures: list[dict] = []
        for index, result in zip(remaining, results):
            raw = engine.tgt.decode(
                [token for token in result.hypotheses[0] if token != _EOS]
            )
            found = len(pattern.findall(raw))
            expected = rows[index]["expected"]
            if found == expected:
                success_lines += 1
                success_occurrences += expected
            else:
                next_remaining.append(index)
                if len(failures) < 10:
                    failures.append({
                        "chapter_index": rows[index]["chapter_index"],
                        "expected": expected,
                        "found": found,
                        "source": rows[index]["source"],
                        "raw": raw,
                    })
        stages.append({
            "name": name,
            "attempted_lines": len(remaining),
            "success_lines": success_lines,
            "success_occurrences": success_occurrences,
            "failed_lines": len(next_remaining),
            "failures": failures,
        })
        resolved_occurrences += success_occurrences
        remaining = next_remaining
        if not remaining:
            break

    fallback_resolved = 0
    final_remaining: list[int] = []
    for index in remaining:
        repaired_count = normal_repaired[index].casefold().count(correct_vi.casefold())
        if repaired_count >= rows[index]["expected"]:
            fallback_resolved += rows[index]["expected"]
        else:
            final_remaining.append(index)
    return {
        "seconds": time.perf_counter() - started,
        "stages": stages,
        "placeholder_resolved_occurrences": resolved_occurrences,
        "variant_fallback_resolved_occurrences": fallback_resolved,
        "unresolved_lines": len(final_remaining),
        "unresolved_occurrences": sum(rows[index]["expected"] for index in final_remaining),
    }


def _self_check() -> None:
    assert _replace_variants("Đồng Tí và Xương Tí.", ["Đồng Tí", "Xương Tí"], "Nhai Tý") == (
        "Nhai Tý và Nhai Tý.", 2,
    )
    assert _replace_variants("Đồng Tím", ["Đồng Tí"], "Nhai Tý")[1] == 0
    assert len(_marker_pattern("ZX001Q", "ZX0123456789Q").findall("a ZX 0 0 1 Q b")) == 1
    print("termguard_db_repair_probe self-check OK")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--novel-id", type=int, default=1380)
    parser.add_argument("--term-zh", default="睚眦")
    parser.add_argument("--correct-vi", default="Nhai Tý")
    parser.add_argument(
        "--variants",
        help="Các biến thể đã duyệt, phân cách bằng |; bỏ trống để chỉ khai thác ứng viên.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("experiments/termguard_db_repair_probe.json"),
    )
    parser.add_argument("--placeholder-cascade", action="store_true")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        _self_check()
        return

    chapters = (
        db.sb().table("chapters")
        .select("id,chapter_index,content_zh,content_vi")
        .eq("novel_id", args.novel_id)
        .not_.is_("content_zh", "null")
        .not_.is_("content_vi", "null")
        .order("chapter_index")
        .limit(1000)
        .execute()
        .data
        or []
    )
    source_occurrences = sum(
        chapter["content_zh"].count(args.term_zh) for chapter in chapters
    )
    current_correct = sum(
        chapter["content_vi"].count(args.correct_vi) for chapter in chapters
    )
    deficit_chapters = [
        {
            "chapter_id": chapter["id"],
            "chapter_index": chapter["chapter_index"],
            "source": chapter["content_zh"].count(args.term_zh),
            "correct": chapter["content_vi"].count(args.correct_vi),
        }
        for chapter in chapters
        if chapter["content_zh"].count(args.term_zh)
        > chapter["content_vi"].count(args.correct_vi)
    ]

    rows: list[dict] = []
    for chapter in chapters:
        for line_index, raw_line in enumerate(chapter["content_zh"].splitlines()):
            line = clean_source(raw_line)
            if args.term_zh in line:
                rows.append({
                    "chapter_id": chapter["id"],
                    "chapter_index": chapter["chapter_index"],
                    "line_index": line_index,
                    "source": line,
                    "expected": line.count(args.term_zh),
                })

    engine = hachimi_engine._get()
    sources: list[list[str]] = []
    normalized_lines: list[str] = []
    spans_by_line: list[list[tuple[int, int]]] = []
    for row in rows:
        normalized, tokens, spans = _source_spans(engine.src, row["source"])
        normalized_lines.append(normalized)
        spans_by_line.append(spans)
        sources.append(tokens + [_EOS])

    started = time.perf_counter()
    translations = engine.translator.translate_batch(
        sources,
        max_batch_size=32,
        beam_size=4,
        max_decoding_length=180,
        return_attention=True,
    )
    seconds = time.perf_counter() - started

    candidate_counts: Counter[str] = Counter()
    candidate_examples: dict[str, list[dict]] = defaultdict(list)
    approved_variants = [
        item.strip() for item in (args.variants or "").split("|") if item.strip()
    ]
    totals = Counter()
    line_results: list[dict] = []
    unresolved_results: list[dict] = []
    normal_repaired: list[str] = []

    for row, normalized, source_spans, result in zip(
        rows, normalized_lines, spans_by_line, translations
    ):
        target_tokens = [token for token in result.hypotheses[0] if token != _EOS]
        plain_vi = engine.tgt.decode(target_tokens)
        attention = result.attention[0]
        candidates: list[str] = []
        for source_indexes in _term_spans(
            normalized, source_spans, args.term_zh
        ):
            target_indexes = _candidate_span(
                attention, len(target_tokens), source_indexes
            )
            candidate = (
                engine.tgt.decode(
                    target_tokens[target_indexes[0]:target_indexes[-1] + 1]
                ).strip(" ,.;:!?…“”‘’\"'")
                if target_indexes else ""
            )
            candidates.append(candidate)
            candidate_counts[candidate] += 1
            if len(candidate_examples[candidate]) < 3:
                candidate_examples[candidate].append({
                    "chapter_index": row["chapter_index"],
                    "source": normalized,
                    "plain_vi": plain_vi,
                })

        repaired, replaced = _replace_variants(
            plain_vi, approved_variants, args.correct_vi
        )
        normal_repaired.append(repaired)
        totals["expected"] += row["expected"]
        totals["plain_correct"] += plain_vi.casefold().count(args.correct_vi.casefold())
        totals["replaced"] += replaced
        totals["repaired_correct"] += repaired.casefold().count(args.correct_vi.casefold())
        unresolved = max(
            row["expected"] - repaired.casefold().count(args.correct_vi.casefold()),
            0,
        )
        totals["unresolved"] += unresolved
        detail = {
            **row,
            "plain_vi": plain_vi,
            "candidates": candidates,
            "repaired_vi": repaired,
        }
        if unresolved:
            unresolved_results.append(detail)
        if len(line_results) < 100 and (
            replaced or unresolved
        ):
            line_results.append(detail)

    cascade = (
        _measure_placeholder_cascade(
            rows, engine, args.term_zh, args.correct_vi, normal_repaired
        )
        if args.placeholder_cascade else None
    )
    result = {
        "novel_id": args.novel_id,
        "term_zh": args.term_zh,
        "correct_vi": args.correct_vi,
        "db": {
            "chapters": len(chapters),
            "source_occurrences": source_occurrences,
            "current_correct_occurrences": current_correct,
            "net_difference": source_occurrences - current_correct,
            "deficit_chapters": len(deficit_chapters),
            "deficit_in_those_chapters": sum(
                row["source"] - row["correct"] for row in deficit_chapters
            ),
            "deficit_details": deficit_chapters,
        },
        "fresh_normal": {
            "lines": len(rows),
            "seconds": seconds,
            "approved_variants": approved_variants,
            **totals,
        },
        "candidates": [
            {
                "variant": variant,
                "count": count,
                "examples": candidate_examples[variant],
            }
            for variant, count in candidate_counts.most_common()
        ],
        "line_results": line_results,
        "unresolved_results": unresolved_results,
        "placeholder_cascade": cascade,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps({
        "db": result["db"] | {"deficit_details": "(xem JSON)"},
        "fresh_normal": result["fresh_normal"],
        "top_candidates": [
            [row["variant"], row["count"]] for row in result["candidates"][:20]
        ],
        "placeholder_cascade": cascade,
    }, ensure_ascii=False, indent=2))
    print(f"Đã ghi {args.output}")


if __name__ == "__main__":
    main()
