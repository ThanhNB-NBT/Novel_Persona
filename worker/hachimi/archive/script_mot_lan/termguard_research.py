r"""Đo độ bền termguard và thử hậu sửa bằng attention trên Hachimi CT2.

Chỉ đọc Supabase, không ghi DB và không thay đổi pipeline production.
Chạy từ ``worker/``:

    PYTHONIOENCODING=utf-8 PYTHONPATH=. ..\.venv\Scripts\python.exe \
      experiments/termguard_research.py
"""
from __future__ import annotations

import argparse
import json
import math
import re
import time
from collections import Counter
from pathlib import Path
from typing import Callable

from novelworker import db
from novelworker.translator import hachimi_engine, termguard
from novelworker.translator.text_clean import clean_source

_EOS = "</s>"


def _fetch_sample(chapter_count: int, novel_count: int) -> tuple[list[dict], dict[int, list[dict]]]:
    """Lấy mẫu phân tầng, trải đều theo số chương, chỉ dùng truyện có glossary riêng."""
    top_terms = (
        db.sb().table("glossary_terms")
        .select("novel_id,term_zh,correct_vi,hit_count")
        .eq("approved", True)
        .not_.is_("novel_id", "null")
        .not_.is_("term_zh", "null")
        .not_.is_("correct_vi", "null")
        .order("hit_count", desc=True)
        .limit(1000)
        .execute()
        .data
        or []
    )
    ranked_novels: list[int] = []
    for row in top_terms:
        novel_id = row["novel_id"]
        if novel_id not in ranked_novels:
            ranked_novels.append(novel_id)

    per_novel = math.ceil(chapter_count / novel_count)
    chosen: list[dict] = []
    terms_by_novel: dict[int, list[dict]] = {}
    for novel_id in ranked_novels:
        local_terms = (
            db.sb().table("glossary_terms")
            .select("term_zh,wrong_vi,correct_vi,note,term_type,approved,novel_id")
            .eq("approved", True)
            .eq("novel_id", novel_id)
            .not_.is_("term_zh", "null")
            .not_.is_("correct_vi", "null")
            .limit(1000)
            .execute()
            .data
            or []
        )
        eligible_zh = [
            row["term_zh"].strip()
            for row in local_terms
            if len((row.get("term_zh") or "").strip()) >= 2
            and "nghi sai" not in (row.get("note") or "")
        ]
        if not eligible_zh:
            continue

        chapters = (
            db.sb().table("chapters")
            .select("id,novel_id,chapter_index,title_zh,content_zh,content_vi")
            .eq("novel_id", novel_id)
            .not_.is_("content_zh", "null")
            .not_.is_("content_vi", "null")
            .order("chapter_index")
            .limit(1000)
            .execute()
            .data
            or []
        )
        bearing = [
            chapter for chapter in chapters
            if chapter.get("content_zh") and any(term in chapter["content_zh"] for term in eligible_zh)
        ]
        if len(bearing) < per_novel:
            continue

        # Lấy đều từ đầu đến cuối dải chương, tránh chỉ chọn các chương dày term nhất.
        indexes = [
            round(i * (len(bearing) - 1) / (per_novel - 1))
            if per_novel > 1 else 0
            for i in range(per_novel)
        ]
        selected = [bearing[i] for i in indexes]
        global_terms = (
            db.sb().table("glossary_terms")
            .select("term_zh,wrong_vi,correct_vi,note,term_type,approved,novel_id")
            .eq("approved", True)
            .is_("novel_id", "null")
            .not_.is_("term_zh", "null")
            .not_.is_("correct_vi", "null")
            .limit(1000)
            .execute()
            .data
            or []
        )
        chosen.extend(selected)
        terms_by_novel[novel_id] = local_terms + global_terms
        if len(terms_by_novel) >= novel_count:
            break

    if len(chosen) < chapter_count:
        raise RuntimeError(
            f"Chỉ chọn được {len(chosen)}/{chapter_count} chương từ "
            f"{len(terms_by_novel)}/{novel_count} truyện"
        )
    return chosen[:chapter_count], terms_by_novel


def _rare_vocab_codes(limit: int = 80) -> list[str]:
    """Lấy các từ Latin hiếm nhưng là đúng một SentencePiece ở cả nguồn và đích."""
    sp = hachimi_engine._get().src
    codes: list[tuple[int, str]] = []
    for piece_id in range(5000, sp.vocab_size()):
        piece = sp.id_to_piece(piece_id)
        raw = piece.removeprefix("▁")
        if (
            4 <= len(raw) <= 14
            and raw.isascii()
            and raw.isalpha()
            and raw[:1].isupper()
            and sp.encode(raw, out_type=str) == [piece]
        ):
            codes.append((piece_id, raw))
    return [raw for _, raw in reversed(codes[-limit:])]


def _protect_custom(
    zh: str,
    terms: list[dict],
    codes: list[str],
) -> tuple[str, dict[str, str], dict[str, str]]:
    """Bản thử nghiệm tối thiểu của protect, giữ đúng thứ tự ưu tiên production."""
    mapping: dict[str, str] = {}
    source_terms: dict[str, str] = {}
    available = [code for code in codes if code not in zh]
    for term, code in zip(termguard._eligible(terms, zh), available):
        zh = zh.replace(term["term_zh"], f" {code} ")
        mapping[code] = term["correct_vi"]
        source_terms[code] = term["term_zh"]
    return zh, mapping, source_terms


def _pattern(code: str, alphabet: str | None = None) -> re.Pattern[str]:
    body = r"[ \t]*".join(re.escape(char) for char in code)
    if alphabet:
        return re.compile(rf"(?<![{re.escape(alphabet)}]){body}(?![{re.escape(alphabet)}])")
    if code[0].isalnum() and code[-1].isalnum():
        return re.compile(rf"(?<![A-Za-z0-9]){body}(?![A-Za-z0-9])")
    return re.compile(body)


def _restore_custom(vi: str, mapping: dict[str, str]) -> str:
    for code, correct_vi in sorted(mapping.items(), key=lambda item: -len(item[0])):
        vi = _pattern(code).sub(correct_vi, vi)
    return re.sub(r"[ \t]{2,}", " ", vi).strip()


def _measure_scheme(
    chapters: list[dict],
    terms_by_novel: dict[int, list[dict]],
    name: str,
    code_factory: Callable[[int], list[str]],
    full_chapters: bool,
) -> dict:
    totals = Counter()
    failures: list[dict] = []
    started = time.perf_counter()

    for chapter in chapters:
        source = clean_source(chapter["content_zh"])
        terms = terms_by_novel[chapter["novel_id"]]
        if name == "jwzf":
            protected, mapping = termguard.protect(source, terms)
            eligible = termguard._eligible(terms, source)
            source_terms = {
                code: term["term_zh"]
                for code, term in zip(mapping, eligible)
            }
            restore = termguard.restore
            alphabet = termguard._L
        elif name == "direct_vi":
            protected = source
            mapping = {}
            source_terms = {}
            for term in termguard._eligible(terms, source):
                code = term["correct_vi"]
                protected = protected.replace(term["term_zh"], f" {code} ")
                mapping[code] = code
                source_terms[code] = term["term_zh"]
            restore = _restore_custom
            alphabet = None
        else:
            protected, mapping, source_terms = _protect_custom(
                source, terms, code_factory(len(terms))
            )
            restore = _restore_custom
            alphabet = None

        protected_lines = protected.splitlines()
        selected_indexes = (
            list(range(len(protected_lines)))
            if full_chapters
            else [
                i for i, line in enumerate(protected_lines)
                if any(code in line for code in mapping)
            ]
        )
        selected_text = "\n".join(protected_lines[i] for i in selected_indexes)
        translated = hachimi_engine.translate_text(selected_text)
        raw_lines = translated.splitlines()
        restored = restore(translated, mapping)
        restored_lines = restored.splitlines()
        totals["translated_lines"] += len(selected_indexes)

        for code, correct_vi in mapping.items():
            pattern = _pattern(code, alphabet)
            exact_pattern = re.compile(
                pattern.pattern.replace(r"[ \t]*", "")
            )
            expected = sum(
                len(pattern.findall(protected_lines[i])) for i in selected_indexes
            )
            if not expected:
                continue
            exact = len(exact_pattern.findall(translated))
            restorable = len(pattern.findall(translated))
            totals["expected"] += expected
            totals["exact"] += min(exact, expected)
            totals["restorable"] += min(restorable, expected)
            totals["lost"] += max(expected - restorable, 0)
            totals["overgenerated"] += max(restorable - expected, 0)

            if restorable < expected and len(failures) < 24:
                for local_i, source_i in enumerate(selected_indexes):
                    if code not in protected_lines[source_i]:
                        continue
                    raw_line = raw_lines[local_i] if local_i < len(raw_lines) else ""
                    if len(pattern.findall(raw_line)) >= protected_lines[source_i].count(code):
                        continue
                    failures.append({
                        "chapter_id": chapter["id"],
                        "chapter_index": chapter["chapter_index"],
                        "novel_id": chapter["novel_id"],
                        "term_zh": source_terms.get(code),
                        "correct_vi": correct_vi,
                        "code": code,
                        "source": protected_lines[source_i][:300],
                        "raw": raw_line[:300],
                        "restored": (
                            restored_lines[local_i][:300]
                            if local_i < len(restored_lines) else ""
                        ),
                    })
                    break

        if name == "jwzf":
            unmatched_raw = translated
            for code in sorted(mapping, key=len, reverse=True):
                unmatched_raw = _pattern(code, alphabet).sub("", unmatched_raw)
            totals["raw_fragments"] += len(
                re.findall(
                    rf"(?<![{termguard._L}])[{termguard._L}]{{1,6}}(?![{termguard._L}])",
                    unmatched_raw,
                )
            )
            totals["restored_fragments"] += len(
                re.findall(rf"(?<![{termguard._L}])[{termguard._L}]{{1,6}}(?![{termguard._L}])", restored)
            )

    elapsed = time.perf_counter() - started
    expected = totals["expected"]
    return {
        "name": name,
        "scope": "full_chapters" if full_chapters else "term_bearing_lines",
        **totals,
        "exact_rate": totals["exact"] / expected if expected else 0,
        "restorable_rate": totals["restorable"] / expected if expected else 0,
        "seconds": elapsed,
        "failures": failures,
    }


def _source_spans(sp, line: str) -> tuple[str, list[str], list[tuple[int, int]]]:
    tokens = sp.encode(line, out_type=str)
    prefixes = [sp.decode(tokens[:i]) for i in range(len(tokens) + 1)]
    return prefixes[-1], tokens, [
        (len(prefixes[i]), len(prefixes[i + 1])) for i in range(len(tokens))
    ]


def _non_overlapping_occurrences(line: str, terms: list[dict]) -> list[dict]:
    occupied: set[int] = set()
    found: list[dict] = []
    for picked in termguard._eligible(terms, line):
        term = next(
            (
                row for row in terms
                if (row.get("term_zh") or "").strip() == picked["term_zh"]
                and (row.get("correct_vi") or "").strip() == picked["correct_vi"]
            ),
            picked,
        )
        zh = term["term_zh"]
        for match in re.finditer(re.escape(zh), line):
            positions = set(range(match.start(), match.end()))
            if positions & occupied:
                continue
            occupied |= positions
            found.append({
                "start": match.start(),
                "end": match.end(),
                "term_zh": zh,
                "wrong_vi": term.get("wrong_vi"),
                "correct_vi": term["correct_vi"],
                "term_type": term.get("term_type"),
            })
    return sorted(found, key=lambda item: item["start"])


def _clusters(indexes: list[int]) -> list[list[int]]:
    groups: list[list[int]] = []
    for index in sorted(indexes):
        if not groups or index > groups[-1][-1] + 1:
            groups.append([index])
        else:
            groups[-1].append(index)
    return groups


def _measure_attention(
    chapters: list[dict],
    terms_by_novel: dict[int, list[dict]],
) -> dict:
    engine = hachimi_engine._get()
    line_rows: list[dict] = []
    for chapter in chapters:
        terms = terms_by_novel[chapter["novel_id"]]
        for line_index, raw_line in enumerate(chapter["content_zh"].splitlines()):
            line = clean_source(raw_line)
            if not line:
                continue
            occurrences = _non_overlapping_occurrences(line, terms)
            if occurrences:
                line_rows.append({
                    "chapter_id": chapter["id"],
                    "chapter_index": chapter["chapter_index"],
                    "novel_id": chapter["novel_id"],
                    "line_index": line_index,
                    "line": line,
                    "occurrences": occurrences,
                })

    sources: list[list[str]] = []
    spans_by_line: list[list[tuple[int, int]]] = []
    normalized_lines: list[str] = []
    for row in line_rows:
        normalized, tokens, spans = _source_spans(engine.src, row["line"])
        normalized_lines.append(normalized)
        spans_by_line.append(spans)
        sources.append(tokens + [_EOS])

    started = time.perf_counter()
    results = engine.translator.translate_batch(
        sources,
        max_batch_size=32,
        beam_size=4,
        max_decoding_length=180,
        return_attention=True,
    )
    elapsed = time.perf_counter() - started
    totals = Counter()
    examples: list[dict] = []
    variant_candidates: dict[tuple[str, str], Counter[str]] = {}

    for row, normalized, source_spans, result in zip(
        line_rows, normalized_lines, spans_by_line, results
    ):
        target_tokens = [token for token in result.hypotheses[0] if token != _EOS]
        plain_vi = engine.tgt.decode(target_tokens)
        attention = result.attention[0]
        replacements: list[tuple[int, int, str]] = []
        used_target: set[int] = set()
        folded_vi = " ".join(plain_vi.casefold().split())
        correct_budgets: Counter[str] = Counter()
        for occurrence in _non_overlapping_occurrences(
            normalized, terms_by_novel[row["novel_id"]]
        ):
            folded = " ".join(occurrence["correct_vi"].casefold().split())
            correct_budgets[folded] = folded_vi.count(folded)

        for occurrence in _non_overlapping_occurrences(
            normalized, terms_by_novel[row["novel_id"]]
        ):
            totals["occurrences"] += 1
            is_proper = occurrence.get("term_type") in {"person", "place", "sect"}
            if is_proper:
                totals["proper_occurrences"] += 1
            folded_correct = " ".join(occurrence["correct_vi"].casefold().split())
            if correct_budgets[folded_correct] > 0:
                correct_budgets[folded_correct] -= 1
                totals["already_correct"] += 1
                if is_proper:
                    totals["proper_already_correct"] += 1
                continue
            totals["needs_patch"] += 1
            if is_proper:
                totals["proper_needs_patch"] += 1
            wrong_vi = (occurrence.get("wrong_vi") or "").strip()
            if wrong_vi and wrong_vi.casefold() in plain_vi.casefold():
                totals["known_variant_patchable"] += 1
                if is_proper:
                    totals["proper_known_variant_patchable"] += 1
            source_indexes = [
                i for i, (start, end) in enumerate(source_spans)
                if end > occurrence["start"] and start < occurrence["end"]
            ]
            forward_indexes = [
                target_i
                for target_i, weights in enumerate(attention[:len(target_tokens)])
                if source_indexes
                and max(range(len(weights)), key=weights.__getitem__) in source_indexes
            ]
            reverse_indexes = [
                max(
                    range(len(target_tokens)),
                    key=lambda target_i, source_i=source_i: attention[target_i][source_i],
                )
                for source_i in source_indexes
            ] if target_tokens else []
            aligned_indexes = sorted(set(forward_indexes + reverse_indexes))
            if not aligned_indexes:
                totals["unaligned"] += 1
                continue
            best = list(range(aligned_indexes[0], aligned_indexes[-1] + 1))
            while best and target_tokens[best[0]].lstrip("▁") in ",.;:!?…“”‘’\"'()[]{}":
                best.pop(0)
            while best and target_tokens[best[-1]].lstrip("▁") in ",.;:!?…“”‘’\"'()[]{}":
                best.pop()
            if not best:
                totals["unaligned"] += 1
                continue
            totals["aligned"] += 1
            if is_proper:
                key = (occurrence["term_zh"], occurrence["correct_vi"])
                variants = variant_candidates.setdefault(key, Counter())
                variants[engine.tgt.decode(
                    target_tokens[min(forward_indexes):max(forward_indexes) + 1]
                ) if forward_indexes else ""] += 1
            confidence = sum(
                sum(attention[target_i][source_i] for source_i in source_indexes)
                for target_i in best
            ) / len(best)
            if confidence < 0.35:
                totals["low_confidence"] += 1
                continue
            correct_tokens = engine.tgt.encode(occurrence["correct_vi"], out_type=str)
            if len(best) > max(4, len(correct_tokens) * 2 + 2):
                totals["span_too_wide"] += 1
                continue
            if set(best) & used_target:
                totals["collisions"] += 1
                continue
            used_target.update(best)
            totals["patchable"] += 1
            replacements.append((best[0], best[-1] + 1, occurrence["correct_vi"]))

            if len(examples) < 40:
                examples.append({
                    "novel_id": row["novel_id"],
                    "chapter_id": row["chapter_id"],
                    "chapter_index": row["chapter_index"],
                    "term_zh": occurrence["term_zh"],
                    "correct_vi": occurrence["correct_vi"],
                    "source": normalized[:300],
                    "plain_vi": plain_vi[:300],
                    "forward_text": engine.tgt.decode(
                        target_tokens[min(forward_indexes):max(forward_indexes) + 1]
                    ) if forward_indexes else "",
                    "aligned_text": engine.tgt.decode(target_tokens[best[0]:best[-1] + 1]),
                    "confidence": round(confidence, 4),
                })

        patched_tokens = list(target_tokens)
        for start, end, correct_vi in sorted(replacements, reverse=True):
            patched_tokens[start:end] = engine.tgt.encode(correct_vi, out_type=str)
        patched_vi = engine.tgt.decode(patched_tokens)
        for example in examples:
            if (
                example["chapter_id"] == row["chapter_id"]
                and example["source"] == normalized[:300]
                and "patched_vi" not in example
            ):
                example["patched_vi"] = patched_vi[:300]

    occurrences = totals["occurrences"]
    needs_patch = totals["needs_patch"]
    return {
        **totals,
        "lines": len(line_rows),
        "already_correct_rate": totals["already_correct"] / occurrences if occurrences else 0,
        "alignment_rate_on_needed": totals["aligned"] / needs_patch if needs_patch else 0,
        "safe_patch_rate_on_needed": totals["patchable"] / needs_patch if needs_patch else 0,
        "seconds": elapsed,
        "examples": examples,
        "proper_variant_candidates": [
            {
                "term_zh": term_zh,
                "correct_vi": correct_vi,
                "variants": variants.most_common(),
            }
            for (term_zh, correct_vi), variants in sorted(
                variant_candidates.items(),
                key=lambda item: -sum(item[1].values()),
            )
        ],
    }


def _measure_target_prefix(attention_examples: list[dict], limit: int = 20) -> dict:
    engine = hachimi_engine._get()
    rows = attention_examples[:limit]
    sources = [engine.src.encode(row["source"], out_type=str) + [_EOS] for row in rows]
    prefixes = [engine.tgt.encode(row["correct_vi"], out_type=str) for row in rows]
    started = time.perf_counter()
    results = engine.translator.translate_batch(
        sources,
        target_prefix=prefixes,
        beam_size=4,
        max_decoding_length=180,
    )
    elapsed = time.perf_counter() - started
    examples: list[dict] = []
    for row, result in zip(rows, results):
        output = engine.tgt.decode(
            [token for token in result.hypotheses[0] if token != _EOS]
        )
        examples.append({
            "term_zh": row["term_zh"],
            "correct_vi": row["correct_vi"],
            "source": row["source"],
            "plain_vi": row["plain_vi"],
            "forced_vi": output,
            "term_not_at_source_start": not row["source"].startswith(row["term_zh"]),
            "forced_at_target_start": output.startswith(row["correct_vi"]),
        })
    return {
        "examples_count": len(examples),
        "forced_at_target_start": sum(row["forced_at_target_start"] for row in examples),
        "mispositioned_cases": sum(
            row["forced_at_target_start"] and row["term_not_at_source_start"]
            for row in examples
        ),
        "seconds": elapsed,
        "examples": examples,
    }


def _self_check() -> None:
    assert _clusters([1, 2, 4, 7, 8]) == [[1, 2], [4], [7, 8]]
    assert len(_pattern("ZX01Q").findall("a ZX01Q b")) == 1
    assert not _pattern("ZX01Q").search("aZX01Qb")
    assert _restore_custom("a ZX01Q b", {"ZX01Q": "Nhai Tý"}) == "a Nhai Tý b"
    print("termguard_research self-check OK")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--chapters", type=int, default=30)
    parser.add_argument("--novels", type=int, default=3)
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--attention-only", action="store_true")
    parser.add_argument("--only-scheme", choices=[
        "jwzf", "alnum", "bracket_digits", "private_use",
        "rare_vocab_piece", "direct_vi",
    ])
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("experiments/termguard_results.json"),
    )
    args = parser.parse_args()
    if args.self_check:
        _self_check()
        return

    chapters, terms_by_novel = _fetch_sample(args.chapters, args.novels)
    dataset = {
        "chapters": len(chapters),
        "novels": sorted(terms_by_novel),
        "chapter_ids": [chapter["id"] for chapter in chapters],
        "chapter_indexes": [chapter["chapter_index"] for chapter in chapters],
        "source_chars": sum(len(chapter["content_zh"]) for chapter in chapters),
        "source_lines": sum(len(chapter["content_zh"].splitlines()) for chapter in chapters),
        "terms": sum(len(terms) for terms in terms_by_novel.values()),
    }
    print("Mẫu:", dataset, flush=True)

    schemes = {
        "jwzf": lambda count: termguard._CODES[:count],
        "alnum": lambda count: [f"ZX{i:03d}Q" for i in range(1, count + 1)],
        "bracket_digits": lambda count: [f"⟦{i:03d}⟧" for i in range(1, count + 1)],
        "private_use": lambda count: [chr(0xE000 + i) for i in range(count)],
        "rare_vocab_piece": lambda count: _rare_vocab_codes(max(count, 80))[:count],
        "direct_vi": lambda count: [],
    }
    placeholder_results: list[dict] = []
    if not args.attention_only:
        for name, factory in schemes.items():
            if args.only_scheme and name != args.only_scheme:
                continue
            print(f"Đang đo {name}...", flush=True)
            placeholder_results.append(
                _measure_scheme(
                    chapters,
                    terms_by_novel,
                    name,
                    factory,
                    full_chapters=name == "jwzf",
                )
            )

    print("Đang đo attention alignment...", flush=True)
    attention = _measure_attention(chapters, terms_by_novel)
    print("Đang thử target_prefix...", flush=True)
    target_prefix = _measure_target_prefix(attention["examples"])
    result = {
        "dataset": dataset,
        "model": {
            "path": str(Path("models/hachimi-ct2").resolve()),
            "ctranslate2": __import__("ctranslate2").__version__,
            "beam_size": 4,
            "cpu_threads": hachimi_engine.settings.hachimi_cpu_threads,
        },
        "placeholders": placeholder_results,
        "attention_post_edit": attention,
        "target_prefix": target_prefix,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"Đã ghi {args.output}", flush=True)


if __name__ == "__main__":
    main()
