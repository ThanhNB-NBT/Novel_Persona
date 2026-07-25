"""Khóa eval, chọn ứng viên và xuất gold đã được biên tập thủ công."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).parent
SOURCE = ROOT.parent / "experiments" / "hachimi_base_longform.jsonl"
DATASET = ROOT / "dataset"
EVAL_OUT = DATASET / "eval_vnext_300.jsonl"
EVAL_CALIBRATION_OUT = DATASET / "eval_calibration_60.jsonl"
EVAL_EDITS = DATASET / "eval_review_60_edits.jsonl"
EVAL_REFERENCE_OUT = DATASET / "eval_reference_60.jsonl"
CANDIDATES_OUT = DATASET / "gold_candidates_pack_01.jsonl"
PACK_02_OUT = DATASET / "gold_candidates_pack_02.jsonl"
PACK_03_OUT = DATASET / "gold_candidates_pack_03.jsonl"
FULL_CANDIDATES_OUT = DATASET / "gold_candidates_vnext_1200.jsonl"
EDITS = DATASET / "gold_review_pack_01_edits.jsonl"
EDITS_02 = DATASET / "gold_review_pack_02_edits.jsonl"
EDITS_03 = DATASET / "gold_review_pack_03_edits.jsonl"
EDITS_04 = DATASET / "gold_review_pack_04_edits.jsonl"
EDITS_05 = DATASET / "gold_review_pack_05_edits.jsonl"
APPROVED_OUT = DATASET / "gold_approved_vnext.jsonl"
REVIEW_OUT = ROOT.parent / "experiments" / "hachimi_gold_review_pack_01.md"
REVIEW_02_OUT = ROOT.parent / "experiments" / "hachimi_gold_review_pack_02.md"
REVIEW_03_OUT = ROOT.parent / "experiments" / "hachimi_gold_review_pack_03.md"
EVAL_REVIEW_OUT = ROOT.parent / "experiments" / "hachimi_eval_review_60.md"
QUOTAS = {
    "semantic_context": 17,
    "dialogue_register": 8,
    "domain_terms": 10,
    "number_negation": 7,
    "quote_author": 4,
    "natural_vi": 4,
}
REMAINING_QUOTAS = {
    "semantic_context": 383,
    "dialogue_register": 192,
    "domain_terms": 230,
    "number_negation": 153,
    "quote_author": 96,
    "natural_vi": 96,
}
EVAL_QUOTAS = {
    "semantic_context": 10,
    "dialogue_register": 10,
    "domain_terms": 10,
    "number_negation": 10,
    "quote_author": 10,
    "natural_vi": 10,
}
PACK_03_QUOTAS = {
    "dialogue_register": 24,
    "domain_terms": 30,
    "number_negation": 20,
    "quote_author": 13,
    "natural_vi": 13,
}
REJECTED_SOURCE_IDS = {
    # Câu thứ hai bị lỗi nguồn, không thể lập bản dịch gold mà không đoán nội dung.
    "6060c0dd55cc40ab",
}
DOMAIN = re.compile(
    r"系统|游戏|玩家|技能|装备|爆率|掉落|兵种|领主|战舰|护卫舰|机甲|魔法|妖兽|灵根"
)
NUMBER_NEGATION = re.compile(r"\d|不|没|无|未|难|仅|只|除非|否则")
AUTHOR = re.compile(r"(?<!制)作者|更新|推荐票|收藏|读者|章节|点击榜|月票|投票")
QUOTE_PAIRS = (("“", "”"), ("「", "」"), ("『", "』"))
HAN_VI = re.compile(r"[\u3400-\u9fff]")
MODERN_VI = re.compile(
    r"\b(?:tôi(?!\s+luyện\b)|bạn|cậu|anh ta|cô ta|cô ấy|nhé)\b",
    re.I,
)
PARTICLE_NHA = re.compile(r"\bnha(?=[.!?,”’\"]|$)")
MODERN_MÌNH = re.compile(
    r"(?:^|[,;]\s*|\b(?:thì|nhưng|và|rồi|nên|mà|vì|khi|nếu|còn)\s+)"
    r"mình\s+(?:đã|sẽ|đang|vẫn|cũng|bị|được|phải|không|chẳng|liền|lại|"
    r"có|là|cảm|thấy|nghĩ|biết|muốn|nhìn|nói|tưởng|hiểu|định|nhớ|quyết)\b",
    re.I,
)


def source_key(text: str) -> str:
    return re.sub(r"[\s\"“”‘’'，。！？、：；,.!?…]", "", text)


def balanced_quotes(text: str) -> bool:
    return all(text.count(left) == text.count(right) for left, right in QUOTE_PAIRS)


def tags(text: str) -> list[str]:
    out: list[str] = []
    if len(text) >= 90:
        out.append("semantic_context")
    if any(char in text for char in "“「『") and balanced_quotes(text):
        out.append("dialogue_register")
    if DOMAIN.search(text):
        out.append("domain_terms")
    if NUMBER_NEGATION.search(text):
        out.append("number_negation")
    if AUTHOR.search(text):
        out.append("quote_author")
    if 20 <= len(text) <= 89:
        out.append("natural_vi")
    return out


def load_rows() -> list[dict]:
    rows: list[dict] = []
    seen: set[str] = set()
    for chapter in (
        json.loads(line)
        for line in SOURCE.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ):
        source_lines = chapter["source_zh"].split("\n")
        raw_lines = chapter["raw_vi"].split("\n")
        if len(source_lines) != len(raw_lines):
            raise RuntimeError(
                f"Raw đổi số dòng: novel {chapter['novel_id']} "
                f"chương {chapter['chapter_index']}"
            )
        for line_index, (zh, raw_vi) in enumerate(
            zip(source_lines, raw_lines), start=1
        ):
            zh = zh.strip()
            key = source_key(zh)
            if (
                not key
                or key in seen
                or len(zh) < 8
                or len(zh) > 500
                or "**" in zh
                or not balanced_quotes(zh)
            ):
                continue
            seen.add(key)
            row_tags = tags(zh)
            rows.append({
                "id": hashlib.sha256(key.encode("utf-8")).hexdigest()[:16],
                "novel_id": chapter["novel_id"],
                "novel_title": chapter["title_vi"],
                "genre": chapter["genre"],
                "chapter_index": chapter["chapter_index"],
                "line_index": line_index,
                "zh": zh,
                "raw_vi": raw_vi.strip(),
                "tags": row_tags,
            })
    return rows


def round_robin(rows: list[dict], count: int) -> list[dict]:
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        groups[row["genre"]].append(row)
    selected: list[dict] = []
    genres = list(groups)
    while len(selected) < count and genres:
        next_genres: list[str] = []
        for genre in genres:
            if groups[genre] and len(selected) < count:
                selected.append(groups[genre].pop(0))
            if groups[genre]:
                next_genres.append(genre)
        genres = next_genres
    return selected


def select_eval(rows: list[dict]) -> list[dict]:
    by_chapter: dict[tuple[int, int], list[dict]] = defaultdict(list)
    for row in rows:
        by_chapter[(row["novel_id"], row["chapter_index"])].append(row)
    selected: list[dict] = []
    for chapter_rows in by_chapter.values():
        selected.append(max(
            chapter_rows,
            key=lambda row: (
                "semantic_context" in row["tags"],
                "dialogue_register" in row["tags"],
                len(row["zh"]),
            ),
        ))
    if len(selected) != 225:
        raise RuntimeError(f"Cần 225 chương eval nền, chỉ chọn được {len(selected)}")
    selected_ids = {row["id"] for row in selected}
    extras = sorted(
        (row for row in rows if row["id"] not in selected_ids),
        key=lambda row: (
            -len(row["tags"]),
            -len(row["zh"]),
            row["novel_id"],
            row["chapter_index"],
            row["line_index"],
        ),
    )
    selected.extend(round_robin(extras, 75))
    return selected


def select_gold_candidates(
    rows: list[dict],
    blocked_ids: set[str],
    quotas: dict[str, int] = QUOTAS,
    quote_dialogue_fallback: bool = False,
) -> list[dict]:
    available = [row for row in rows if row["id"] not in blocked_ids]
    selected: list[dict] = []
    selected_ids: set[str] = set()
    for category, count in quotas.items():
        candidates = [
            row for row in available
            if (
                category in row["tags"]
                or (
                    quote_dialogue_fallback
                    and category == "quote_author"
                    and "dialogue_register" in row["tags"]
                )
            )
            and row["id"] not in selected_ids
        ]
        candidates.sort(key=lambda row: (
            -len(row["tags"]),
            abs(len(row["zh"]) - (140 if category == "semantic_context" else 60)),
            row["novel_id"],
            row["chapter_index"],
            row["line_index"],
        ))
        picked = round_robin(candidates, count)
        if len(picked) != count:
            raise RuntimeError(f"Thiếu ứng viên {category}: {len(picked)}/{count}")
        for row in picked:
            row["category"] = category
            row["status"] = "pending_review"
            row["proposed_vi"] = ""
        selected.extend(picked)
        selected_ids.update(row["id"] for row in picked)
    return selected


def select_eval_calibration(rows: list[dict]) -> list[dict]:
    selected: list[dict] = []
    selected_ids: set[str] = set()
    for category, count in EVAL_QUOTAS.items():
        candidates = [
            row for row in rows
            if row["id"] not in selected_ids
            and (
                category in row["tags"]
                or (
                    category == "quote_author"
                    and "dialogue_register" in row["tags"]
                )
            )
        ]
        candidates.sort(key=lambda row: (
            category != "quote_author" or "quote_author" not in row["tags"],
            -len(row["tags"]),
            -len(row["zh"]),
            row["novel_id"],
            row["chapter_index"],
        ))
        picked = round_robin(candidates, count)
        if len(picked) != count:
            raise RuntimeError(f"Thiếu eval {category}: {len(picked)}/{count}")
        selected.extend({
            **row,
            "eval_category": category,
            "status": "pending_eval_review",
            "reference_vi": "",
        } for row in picked)
        selected_ids.update(row["id"] for row in picked)
    return selected


def select_pack_03(rows: list[dict], blocked_ids: set[str]) -> list[dict]:
    selected: list[dict] = []
    for category, count in PACK_03_QUOTAS.items():
        candidates = [
            row for row in rows
            if (
                row["id"] not in blocked_ids
                and row["id"] not in REJECTED_SOURCE_IDS
                and row["category"] == category
            )
        ]
        picked = round_robin(candidates, count)
        if len(picked) != count:
            raise RuntimeError(f"Thiếu pack 03 {category}: {len(picked)}/{count}")
        selected.extend(picked)
        blocked_ids.update(row["id"] for row in picked)
    return selected


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
        encoding="utf-8",
    )


def write_review(rows: list[dict]) -> None:
    edits = {
        row["id"]: row
        for row in (
            json.loads(line)
            for line in EDITS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    } if EDITS.exists() else {}
    unknown = set(edits) - {row["id"] for row in rows}
    if unknown:
        raise RuntimeError(f"Review edit không còn ứng viên tương ứng: {sorted(unknown)}")
    missing = [
        row["id"] for row in rows
        if not (edits.get(row["id"], {}).get("issue") or "").strip()
        or not (edits.get(row["id"], {}).get("proposed_vi") or "").strip()
    ]
    if missing:
        raise RuntimeError(f"Ứng viên chưa được biên tập đủ: {missing}")
    out = [
        "# Gold Hachimi v-next — review pack 01",
        "",
        "> 50 cặp đã được Codex đối chiếu lần hai và duyệt theo ủy quyền của người dùng.",
        "",
    ]
    for index, row in enumerate(rows, start=1):
        edit = edits.get(row["id"], {})
        out.extend([
            f"## {index}. {row['category']} — {row['genre']}",
            "",
            f"- Vị trí: novel {row['novel_id']}, chương {row['chapter_index']}, "
            f"dòng {row['line_index']}",
            f"- ZH: {row['zh']}",
            f"- Hachimi gốc: {row['raw_vi']}",
            f"- Lỗi cụ thể: {edit.get('issue', '')}",
            f"- Bản đề xuất: {edit.get('proposed_vi', '')}",
            "",
        ])
    REVIEW_OUT.write_text("\n".join(out), encoding="utf-8")


def write_pending_review(rows: list[dict]) -> None:
    edits = {
        row["id"]: row
        for row in (
            json.loads(line)
            for line in EDITS_02.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }
    if {row["id"] for row in rows} != set(edits):
        raise RuntimeError("Pack 02 chưa được biên tập đủ hoặc chứa ID lạ")
    out = [
        "# Gold Hachimi v-next — review pack 02",
        "",
        "> 50 cặp đã được Codex đọc nghĩa, đối chiếu glossary và duyệt theo ủy quyền của người dùng.",
        "",
    ]
    for index, row in enumerate(rows, start=51):
        edit = edits[row["id"]]
        out.extend([
            f"## {index}. {row['category']} — {row['genre']}",
            "",
            f"- ID: `{row['id']}`",
            f"- Vị trí: novel {row['novel_id']}, chương {row['chapter_index']}, "
            f"dòng {row['line_index']}",
            f"- ZH: {row['zh']}",
            f"- Hachimi gốc: {row['raw_vi']}",
            f"- Lỗi cụ thể: {edit['issue']}",
            f"- Bản đề xuất: {edit['proposed_vi']}",
            "",
        ])
    REVIEW_02_OUT.write_text("\n".join(out), encoding="utf-8")


def write_eval_review(rows: list[dict]) -> None:
    edits = {
        row["id"]: row
        for row in (
            json.loads(line)
            for line in EVAL_EDITS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }
    unknown = set(edits) - {row["id"] for row in rows}
    if unknown:
        raise RuntimeError(f"Eval edit chứa ID lạ: {sorted(unknown)}")
    out = [
        "# Eval Hachimi v-next — 60 cảnh hiệu chuẩn",
        "",
        "> Tập này chỉ dùng để chấm model, tuyệt đối không đưa vào train.",
        f"> Đã biên tập: **{len(edits)}/60**.",
        "",
    ]
    for index, row in enumerate(rows, start=1):
        edit = edits.get(row["id"], {})
        out.extend([
            f"## {index}. {row['eval_category']} — {row['genre']}",
            "",
            f"- ID: `{row['id']}`",
            f"- Vị trí: novel {row['novel_id']}, chương {row['chapter_index']}, "
            f"dòng {row['line_index']}",
            f"- ZH: {row['zh']}",
            f"- Hachimi gốc: {row['raw_vi']}",
            f"- Lỗi cụ thể: {edit.get('issue', '')}",
            f"- Bản tham chiếu: {edit.get('reference_vi', '')}",
            "",
        ])
    EVAL_REVIEW_OUT.write_text("\n".join(out), encoding="utf-8")


def write_pack_03_review(rows: list[dict]) -> None:
    edits = {
        row["id"]: row
        for row in (
            json.loads(line)
            for line in EDITS_03.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    } if EDITS_03.exists() else {}
    unknown = set(edits) - {row["id"] for row in rows}
    if unknown:
        raise RuntimeError(f"Pack 03 edit chứa ID lạ: {sorted(unknown)}")
    out = [
        "# Gold Hachimi v-next — review pack 03",
        "",
        f"> Đã biên tập **{len(edits)}/100**; chỉ nhập gold khi đủ cả pack.",
        "",
    ]
    for index, row in enumerate(rows, start=101):
        edit = edits.get(row["id"], {})
        out.extend([
            f"## {index}. {row['category']} — {row['genre']}",
            "",
            f"- ID: `{row['id']}`",
            f"- Vị trí: novel {row['novel_id']}, chương {row['chapter_index']}, "
            f"dòng {row['line_index']}",
            f"- ZH: {row['zh']}",
            f"- Hachimi gốc: {row['raw_vi']}",
            f"- Lỗi cụ thể: {edit.get('issue', '')}",
            f"- Bản đề xuất: {edit.get('proposed_vi', '')}",
            "",
        ])
    REVIEW_03_OUT.write_text("\n".join(out), encoding="utf-8")


def write_eval_reference(rows: list[dict]) -> None:
    edits = {
        row["id"]: row
        for row in (
            json.loads(line)
            for line in EVAL_EDITS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }
    if len(edits) != len(rows):
        raise RuntimeError(f"Eval mới biên tập {len(edits)}/{len(rows)}")
    write_jsonl(EVAL_REFERENCE_OUT, [
        {
            **row,
            "status": "locked_eval_reference",
            "reference_vi": edits[row["id"]]["reference_vi"].strip(),
            "review_issue": edits[row["id"]]["issue"].strip(),
            "reviewer": "codex_manual_qc",
            "reviewed_at": "2026-07-24",
        }
        for row in rows
    ])


def write_approved(rows: list[dict]) -> None:
    edits = {}
    for path in (EDITS, EDITS_02, EDITS_03, EDITS_04, EDITS_05):
        if not path.exists():
            continue
        edits.update({
            row["id"]: row
            for row in (
                json.loads(line)
                for line in path.read_text(encoding="utf-8").splitlines()
                if line.strip()
            )
        })
    approved = []
    for row in rows:
        edit = edits[row["id"]]
        approved.append({
            "id": row["id"],
            "zh": row["zh"],
            "vi": edit["proposed_vi"].strip(),
            "status": "approved",
            "category": row["category"],
            "issue": edit["issue"].strip(),
            "source_model": "ngocdang83/HachimiMT-60-zh-vi",
            "novel_id": row["novel_id"],
            "chapter_index": row["chapter_index"],
            "line_index": row["line_index"],
            "genre": row["genre"],
            "reviewer": "codex_manual_qc",
            "reviewed_at": "2026-07-24",
        })
    write_jsonl(APPROVED_OUT, approved)


def self_check() -> None:
    assert balanced_quotes("“甲”")
    assert not balanced_quotes("“甲")
    assert "domain_terms" in tags("玩家获得技能和装备。")
    assert "number_negation" in tags("不到5%的人成功。")
    assert source_key("“甲，乙。”") == "甲乙"
    assert sum(QUOTAS.values()) == 50
    assert sum(REMAINING_QUOTAS.values()) == 1_150
    assert sum(EVAL_QUOTAS.values()) == 60
    assert sum(PACK_03_QUOTAS.values()) == 100
    assert "6060c0dd55cc40ab" in REJECTED_SOURCE_IDS
    print("prepare_vnext_review OK")


def validate_outputs() -> None:
    eval_rows = [
        json.loads(line) for line in EVAL_OUT.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    candidates = [
        json.loads(line)
        for line in CANDIDATES_OUT.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    edits = [
        json.loads(line) for line in EDITS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    edits_02 = [
        json.loads(line) for line in EDITS_02.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    approved = [
        json.loads(line) for line in APPROVED_OUT.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    full_candidates = [
        json.loads(line)
        for line in FULL_CANDIDATES_OUT.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    eval_calibration = [
        json.loads(line)
        for line in EVAL_CALIBRATION_OUT.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    eval_edits = [
        json.loads(line)
        for line in EVAL_EDITS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    eval_reference = [
        json.loads(line)
        for line in EVAL_REFERENCE_OUT.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    pack_02 = [
        json.loads(line)
        for line in PACK_02_OUT.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    pack_03 = [
        json.loads(line)
        for line in PACK_03_OUT.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    edits_03 = [
        json.loads(line)
        for line in EDITS_03.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ] if EDITS_03.exists() else []
    edits_04 = [
        json.loads(line)
        for line in EDITS_04.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ] if EDITS_04.exists() else []
    edits_05 = [
        json.loads(line)
        for line in EDITS_05.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ] if EDITS_05.exists() else []
    assert len(eval_rows) == 300
    assert len(candidates) == len(edits) == len(edits_02) == 50
    assert len(approved) == 100 + len(edits_03) + len(edits_04) + len(edits_05)
    assert len(full_candidates) == 1_200
    assert len(eval_calibration) == 60
    assert len(eval_edits) <= 60
    assert len(eval_reference) == 60
    assert len(pack_02) == 50
    assert len(pack_03) == 100
    assert len(edits_03) <= 100
    assert len(edits_04) <= 20
    assert len(edits_05) <= 20
    eval_ids = {row["id"] for row in eval_rows}
    candidate_ids = {row["id"] for row in candidates}
    assert len(eval_ids) == 300 and len(candidate_ids) == 50
    assert eval_ids.isdisjoint(candidate_ids), "gold candidate bị rò vào eval"
    assert eval_ids.isdisjoint({row["id"] for row in full_candidates})
    assert {row["id"] for row in eval_calibration} <= eval_ids
    assert len({row["id"] for row in eval_calibration}) == 60
    assert {row["id"] for row in eval_reference} == {
        row["id"] for row in eval_calibration
    }
    assert all(row["status"] == "locked_eval_reference" for row in eval_reference)
    assert all(row["reference_vi"].strip() for row in eval_reference)
    assert all(row["status"] == "pending_eval_review" for row in eval_calibration)
    assert all(not row["reference_vi"] for row in eval_calibration)
    assert {row["id"] for row in eval_edits} <= {
        row["id"] for row in eval_calibration
    }
    assert len({row["id"] for row in eval_edits}) == len(eval_edits)
    assert all(
        row["issue"].strip() and row["reference_vi"].strip()
        for row in eval_edits
    )
    assert {
        category: sum(
            row["eval_category"] == category for row in eval_calibration
        )
        for category in EVAL_QUOTAS
    } == EVAL_QUOTAS
    assert len({row["id"] for row in full_candidates}) == 1_200
    assert [row["id"] for row in full_candidates[:50]] == [
        row["id"] for row in candidates
    ]
    assert [row["id"] for row in full_candidates[50:100]] == [
        row["id"] for row in pack_02
    ]
    assert not ({row["id"] for row in pack_03} & {
        row["id"] for row in full_candidates[:100]
    })
    assert {
        category: sum(row["category"] == category for row in pack_03)
        for category in PACK_03_QUOTAS
    } == PACK_03_QUOTAS
    assert {
        category: sum(row["category"] == category for row in full_candidates)
        for category in QUOTAS
    } == {
        category: QUOTAS[category] + REMAINING_QUOTAS[category]
        for category in QUOTAS
    }
    assert {row["id"] for row in edits} == candidate_ids
    expected_approved_ids = {row["id"] for row in full_candidates[:100]}
    if len(edits_03) == 100:
        expected_approved_ids.update(row["id"] for row in pack_03)
    expected_approved_ids.update(row["id"] for row in edits_04)
    expected_approved_ids.update(row["id"] for row in edits_05)
    assert {row["id"] for row in approved} == expected_approved_ids
    assert all(row["status"] == "locked_eval" for row in eval_rows)
    assert all(row["status"] == "pending_review" for row in candidates)
    assert all(row["status"] == "approved" for row in approved)
    assert all(not row["reference_vi"] for row in eval_rows)
    assert all(not row["proposed_vi"] for row in candidates)
    assert all(row["issue"].strip() and row["proposed_vi"].strip() for row in edits)
    assert all(row["issue"].strip() and row["proposed_vi"].strip() for row in edits_02)
    reviewed = edits + edits_02 + edits_03 + edits_04 + edits_05
    source_by_id = {
        row["id"]: row["zh"]
        for row in full_candidates
    }
    assert len({row["id"] for row in reviewed}) == (
        100 + len(edits_03) + len(edits_04) + len(edits_05)
    )
    assert all(row.get("status") == "approved_by_user" for row in edits_04 + edits_05)
    assert all(not HAN_VI.search(row["proposed_vi"]) for row in reviewed)
    assert all(
        not MODERN_VI.search(row["proposed_vi"])
        and not MODERN_MÌNH.search(row["proposed_vi"])
        and not PARTICLE_NHA.search(row["proposed_vi"])
        for row in reviewed
    )
    assert all(balanced_quotes(row["proposed_vi"]) for row in reviewed)
    assert all(
        0.35 <= len(row["proposed_vi"]) / len(source_by_id[row["id"]]) <= 6
        for row in reviewed
    )
    assert all(not HAN_VI.search(row["reference_vi"]) for row in eval_edits)
    assert all(
        not MODERN_VI.search(row["reference_vi"])
        and not MODERN_MÌNH.search(row["reference_vi"])
        and not PARTICLE_NHA.search(row["reference_vi"])
        for row in eval_edits
    )
    assert all(balanced_quotes(row["reference_vi"]) for row in eval_edits)
    eval_source_by_id = {row["id"]: row["zh"] for row in eval_calibration}
    assert all(
        0.35 <= len(row["reference_vi"]) / len(eval_source_by_id[row["id"]]) <= 6
        for row in eval_edits
    )
    assert REVIEW_OUT.read_text(encoding="utf-8").count("\n## ") == 50
    assert REVIEW_02_OUT.read_text(encoding="utf-8").count("\n## ") == 50
    assert REVIEW_03_OUT.read_text(encoding="utf-8").count("\n## ") == 100
    assert EVAL_REVIEW_OUT.read_text(encoding="utf-8").count("\n## ") == 60


def main() -> None:
    rows = load_rows()
    eval_rows = select_eval(rows)
    eval_calibration = select_eval_calibration(eval_rows)
    eval_ids = {row["id"] for row in eval_rows}
    candidates = select_gold_candidates(rows, eval_ids)
    remaining = select_gold_candidates(
        rows,
        eval_ids | {row["id"] for row in candidates},
        REMAINING_QUOTAS,
        quote_dialogue_fallback=True,
    )
    full_candidates = candidates + remaining
    pack_03 = select_pack_03(
        full_candidates,
        {row["id"] for row in full_candidates[:100]},
    )
    DATASET.mkdir(exist_ok=True)
    write_jsonl(EVAL_OUT, [
        {**row, "status": "locked_eval", "reference_vi": ""}
        for row in eval_rows
    ])
    write_jsonl(EVAL_CALIBRATION_OUT, eval_calibration)
    write_jsonl(CANDIDATES_OUT, candidates)
    write_jsonl(FULL_CANDIDATES_OUT, full_candidates)
    write_jsonl(PACK_02_OUT, remaining[:50])
    write_jsonl(PACK_03_OUT, pack_03)
    write_review(candidates)
    write_pending_review(remaining[:50])
    write_pack_03_review(pack_03)
    write_eval_review(eval_calibration)
    write_eval_reference(eval_calibration)
    approved_rows = candidates + remaining[:50]
    if EDITS_03.exists() and sum(
        1 for line in EDITS_03.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ) == 100:
        approved_rows += pack_03
    if EDITS_04.exists():
        edit_04_ids = {
            json.loads(line)["id"]
            for line in EDITS_04.read_text(encoding="utf-8").splitlines()
            if line.strip()
        }
        if len(edit_04_ids) != 20:
            raise RuntimeError(f"Pack 04 cần đúng 20 ID đã duyệt, hiện có {len(edit_04_ids)}")
        approved_rows += [row for row in full_candidates if row["id"] in edit_04_ids]
    if EDITS_05.exists():
        edit_05_ids = {
            json.loads(line)["id"]
            for line in EDITS_05.read_text(encoding="utf-8").splitlines()
            if line.strip()
        }
        if len(edit_05_ids) != 20:
            raise RuntimeError(f"Pack 05 cần đúng 20 ID đã duyệt, hiện có {len(edit_05_ids)}")
        approved_rows += [row for row in full_candidates if row["id"] in edit_05_ids]
    write_approved(approved_rows)
    validate_outputs()
    print(
        f"pool={len(rows)} eval={len(eval_rows)} "
        f"gold_candidates={len(candidates) + len(remaining)}"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    self_check() if args.self_check else main()
