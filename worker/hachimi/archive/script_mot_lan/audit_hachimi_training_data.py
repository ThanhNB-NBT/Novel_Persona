"""Kiểm toán dữ liệu fine-tune Hachimi mà không sửa dữ liệu nguồn.

Chạy từ worker/:
PYTHONIOENCODING=utf-8 PYTHONPATH=. ..\\.venv\\Scripts\\python.exe
experiments/audit_hachimi_training_data.py
"""

from __future__ import annotations

import json
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "hachimi_finetune"
OUT = Path(__file__).with_name("hachimi_training_data_audit_agent.md")
HARD_QUARANTINE = Path(__file__).with_name("hachimi_training_hard_quarantine_candidates.jsonl")
REVIEW_QUEUE = Path(__file__).with_name("hachimi_training_review_candidates.jsonl")
FILES = {
    "approved_gold": ROOT / "approved_gold.jsonl",
    "train_gold_vnext": ROOT / "dataset" / "train_gold_vnext.jsonl",
    "register_gold": ROOT / "dataset" / "register_gold.jsonl",
    "labeled_gold": ROOT / "dataset" / "labeled_gold.jsonl",
    "booster": ROOT / "dataset" / "booster.jsonl",
    "train_v2": ROOT / "dataset" / "train_v2.jsonl",
}
HAN = re.compile(r"[\u3400-\u9fff]")
AUTHOR = re.compile(r"(?:PS[：: ]|本章说|求(?:票|收藏|订阅)|(?:作者|笔者).{0,12}(?:说|写|感谢)|感谢.{0,18}(?:读者|编辑|书友)|完本)", re.I)
QUOTE = re.compile(r'"[^"\n]*"|“[^”\n]*”|「[^」\n]*」')
LATIN_WORD = re.compile(r"\b[A-Z][A-Za-z]{2,}\b")
BAD_PUNCT = re.compile(r"(?:\*\*|/\s*$|[（(]\s*[）)]|[【]\s*[】])")
_VB = r"(?:đã|sẽ|đang|vẫn|cũng|bị|được|phải|không|chẳng|liền|lại|có|là|cảm|thấy|nghĩ|biết|muốn|nhìn|nói|tưởng|hiểu|định|nhớ|quyết|thầm|vừa|mới|chỉ|hơi|quả|còn|rất)"
TOI = re.compile(rf"(?<!của )(?<!cho )\btôi\s+{_VB}\b", re.I)
MINH = re.compile(rf"(?:^|[,;]\s*|\b(?:thì|nhưng|và|rồi|nên|mà|vì|khi|nếu|còn)\s+)mình\s+{_VB}\b", re.I)
MOD3 = re.compile(r"\b(?:anh ta|cô ta|cô ấy|cậu ta|ông ta)\b", re.I)


def pair(row: dict) -> tuple[str, str]:
    return (
        str(row.get("zh") or row.get("source") or row.get("source_zh") or "").strip(),
        str(row.get("vi") or row.get("target") or row.get("target_vi") or row.get("proposed_vi") or "").strip(),
    )


def load(path: Path) -> list[tuple[int, dict]]:
    rows = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip():
            rows.append((line_no, json.loads(line)))
    return rows


def examples(items: list[tuple[int, dict]], limit: int = 8) -> list[str]:
    return [f"{line}: {pair(row)[0][:90]} → {pair(row)[1][:110]}" for line, row in items[:limit]]


def register_leak(vi: str) -> bool:
    """Khớp đúng gate replay hiện hành, không coi 'của mình' là lỗi."""
    narr = QUOTE.sub(" ", vi)
    return bool(TOI.search(narr) or MINH.search(narr) or MOD3.search(narr))


def audit_file(name: str, rows: list[tuple[int, dict]]) -> dict:
    pairs = Counter(pair(row) for _, row in rows)
    zh_counts = Counter(pair(row)[0] for _, row in rows)
    malformed = [(n, r) for n, r in rows if not all(pair(r))]
    status = Counter(str(r.get("status", "<thiếu>")) for _, r in rows)
    skipped = [(n, r) for n, r in rows if r.get("skip")]
    han_vi = [(n, r) for n, r in rows if HAN.search(pair(r)[1])]
    author = [(n, r) for n, r in rows if AUTHOR.search(pair(r)[0])]
    bad_punct = [(n, r) for n, r in rows if BAD_PUNCT.search(pair(r)[0])]
    modern_narr = [(n, r) for n, r in rows if register_leak(pair(r)[1])]
    unbalanced = [(n, r) for n, r in rows if pair(r)[1].count('"') % 2 or pair(r)[1].count("“") != pair(r)[1].count("”")]
    long_ratio = [(n, r) for n, r in rows if len(pair(r)[0]) > 20 and not 0.25 <= len(pair(r)[1]) / len(pair(r)[0]) <= 5.0]
    return {
        "rows": len(rows), "pairs": pairs, "zh_counts": zh_counts, "malformed": malformed,
        "status": status, "skipped": skipped, "han_vi": han_vi, "author": author,
        "bad_punct": bad_punct, "modern_narr": modern_narr, "unbalanced": unbalanced,
        "long_ratio": long_ratio,
    }


def replay_sample_risks(rows: list[tuple[int, dict]], limit: int = 20_000) -> dict[str, list[int]]:
    """Mô phỏng đúng thứ tự `load_extra_replay(..., limit)` để không báo số toàn tập vô ích."""
    rows = rows.copy()
    random.Random(42).shuffle(rows)
    chosen = [(line, row) for line, row in rows if all(pair(row)) and not register_leak(pair(row)[1])][:limit]
    return {
        "selected": [line for line, _ in chosen],
        "source_corrupted_marker": [line for line, row in chosen if BAD_PUNCT.search(pair(row)[0])],
        "unbalanced_target_quote": [line for line, row in chosen if pair(row)[1].count('"') % 2 or pair(row)[1].count("“") != pair(row)[1].count("”")],
        "author_note_or_meta": [line for line, row in chosen if AUTHOR.search(pair(row)[0])],
        "length_ratio": [line for line, row in chosen if len(pair(row)[0]) > 20 and not 0.25 <= len(pair(row)[1]) / len(pair(row)[0]) <= 5.0],
    }


def main() -> None:
    loaded = {name: load(path) for name, path in FILES.items()}
    audits = {name: audit_file(name, rows) for name, rows in loaded.items()}
    lines = [
        "# Kiểm toán dữ liệu fine-tune Hachimi",
        "",
        "Script này chỉ đọc JSONL. Các cờ là danh sách cần duyệt, không tự kết luận bản dịch sai.",
        "",
        "## Tổng quan",
        "",
        "| Tập | Dòng | Cặp duy nhất | Cặp trùng nội bộ | ZH lặp (khác/giống VI) | status |",
        "|---|---:|---:|---:|---:|---|",
    ]
    for name, data in audits.items():
        internal = sum(n - 1 for n in data["pairs"].values() if n > 1)
        zh_dup = sum(n - 1 for n in data["zh_counts"].values() if n > 1)
        lines.append(f"| {name} | {data['rows']} | {len(data['pairs'])} | {internal} | {zh_dup} | {dict(data['status'])} |")

    train = audits["train_gold_vnext"]["pairs"]
    lines += ["", "## Provenance và trọng số thực", ""]
    for name in ("approved_gold", "register_gold", "booster", "labeled_gold"):
        source = audits[name]["pairs"]
        present = sum(1 for p in source if p in train)
        weighted = sum(train[p] for p in source if p in train)
        lines.append(f"- `{name}`: {len(source)} cặp duy nhất; có {present} trong `train_gold_vnext`, chiếm {weighted} lượt trước `gold_repeat`.")
    lines += [
        "- `kaggle_train.py` còn nhân toàn bộ `--gold` thêm `gold_repeat=5`. Vì vậy mỗi lần lặp sẵn trong `train_gold_vnext` bị nhân tiếp 5; đây là trọng số thực, không phải chỉ tài liệu mô tả.",
        "",
        "## Lỗi chắc chắn cần chặn trước train",
        "",
    ]
    replay_risks = replay_sample_risks(loaded["train_v2"])
    lines += [
        "## Replay thực sự sẽ được lấy",
        "",
        f"`load_extra_replay` xáo cố định seed 42 rồi lấy {len(replay_risks['selected'])} dòng hợp gate từ `train_v2`. Trong đúng mẫu này có:",
        f"- {len(replay_risks['source_corrupted_marker'])} nguồn mất chữ/marker: dòng {replay_risks['source_corrupted_marker'][:12]};",
        f"- {len(replay_risks['unbalanced_target_quote'])} đích lệch dấu thoại: dòng {replay_risks['unbalanced_target_quote'][:12]};",
        f"- {len(replay_risks['length_ratio'])} cặp lệch độ dài rõ: dòng {replay_risks['length_ratio'][:12]};",
        f"- {len(replay_risks['author_note_or_meta'])} lời tác giả/meta: dòng {replay_risks['author_note_or_meta'][:12]}.",
        "",
        "Kết luận: register gate không kiểm alignment hay nguồn hỏng; không nên truyền `--extra-replay dataset/train_v2.jsonl` cho vòng này.",
        "",
    ]
    for name, data in audits.items():
        if data["malformed"] or data["skipped"] or data["han_vi"]:
            lines.append(f"### {name}")
            if data["malformed"]:
                lines.append(f"- Thiếu ZH/VI: {len(data['malformed'])}. " + " | ".join(examples(data["malformed"])))
            if data["skipped"]:
                lines.append(f"- Có `skip=true`: {len(data['skipped'])}. " + " | ".join(examples(data["skipped"])))
            if data["han_vi"]:
                lines.append(f"- Còn chữ Hán trong VI: {len(data['han_vi'])}. " + " | ".join(examples(data["han_vi"])))
            lines.append("")

    lines += ["## Cờ duyệt ngữ cảnh (không tự sửa)", ""]
    for label, key in (
        ("Lời kể có đại từ hiện đại ngoài dấu thoại", "modern_narr"),
        ("Dấu thoại không cân", "unbalanced"),
        ("Dấu nguồn bẩn", "bad_punct"),
        ("Khả năng lời tác giả", "author"),
        ("Tỉ lệ dài bất thường", "long_ratio"),
    ):
        total = sum(len(data[key]) for data in audits.values())
        lines.append(f"### {label}: {total}")
        for name, data in audits.items():
            if data[key]:
                lines.append(f"- `{name}` ({len(data[key])}): " + " | ".join(examples(data[key])))
        lines.append("")

    hard_rows, review_rows = [], []
    # Candidate áp trực tiếp vào lệnh train hiện tại: chỉ emit dòng của manifest vnext,
    # không lặp lại cùng cặp qua các tập nguồn.
    for name in ("train_gold_vnext",):
        for line_no, row in loaded[name]:
            zh, vi = pair(row)
            if BAD_PUNCT.search(zh):
                hard_rows.append({"dataset": name, "line": line_no, "reason": "source_corrupted_marker", "zh": zh, "vi": vi})
            if vi.count('"') % 2 or vi.count("“") != vi.count("”"):
                review_rows.append({"dataset": name, "line": line_no, "reason": "unbalanced_target_quote", "zh": zh, "vi": vi})
            if AUTHOR.search(zh):
                review_rows.append({"dataset": name, "line": line_no, "reason": "author_note_or_meta", "zh": zh, "vi": vi})
            if register_leak(vi):
                review_rows.append({"dataset": name, "line": line_no, "reason": "narrative_register_gate", "zh": zh, "vi": vi})
    HARD_QUARANTINE.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in hard_rows), encoding="utf-8")
    REVIEW_QUEUE.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in review_rows), encoding="utf-8")

    # Các tên Latin là dấu hiệu nhất quán nhân vật cần đối chiếu; chỉ báo khi cùng họ tên
    # xuất hiện với từ hai biến thể trở lên trong mọi gold, không phán đoán biến thể đúng.
    variants: dict[str, set[str]] = defaultdict(set)
    for rows in loaded.values():
        for _, row in rows:
            for word in LATIN_WORD.findall(pair(row)[1]):
                variants[word.lower()].add(word)
    case_variants = {key: values for key, values in variants.items() if len(values) > 1}
    lines += ["## Khuyến nghị tối thiểu", "", "1. Không dùng `dataset/train_gold_vnext.jsonl` nguyên trạng làm `--gold`: nó đã trộn nguồn và bản sao booster, rồi lại bị `gold_repeat=5` nhân toàn bộ.", "2. Chỉ train từ một manifest đã duyệt: `approved_gold` + các dòng `register_gold` qua kiểm duyệt lại + booster không trùng. Không coi trường `status=approved` là provenance; `register_gold` được sao từ `labeled_gold` nhưng không có `label_src`, người duyệt, hay dấu thời gian.", f"3. Quarantine chắc chắn {len(hard_rows)} dòng có marker nguồn hỏng trong `{HARD_QUARANTINE.name}`. Hàng đợi duyệt `{REVIEW_QUEUE.name}` có {len(review_rows)} cờ thoại/xưng hô/lời tác giả; lời tác giả không tự loại vì yêu cầu hiện tại là dịch đủ.", "4. Sau khi lọc, hạ trọng số bằng một đòn: hoặc bỏ bản sao booster trong manifest, hoặc đặt `--gold-repeat=1` và chỉ lặp riêng nhóm đã duyệt. Không làm cả hai kiểu lặp.", "", "## Tự kiểm", "", "- Script chỉ đọc sáu JSONL và viết artifact vào `experiments/`; không ghi lên tập train.", "- Cờ xưng hô dùng đúng regex gate replay hiện hành, nên không đánh nhầm sở hữu cách như ‘của mình’. Không suy đoán Marya/Mailia vì cần map nhân vật từ nguồn/glossary.", ""]
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(OUT)


def _self_check() -> None:
    assert not register_leak("Hắn nắm lấy thanh kiếm của mình.")
    assert register_leak("Tôi đã nhìn thấy hắn.")
    assert register_leak("Nàng nói xong, cô ta rời đi.")
    assert BAD_PUNCT.search("他躺在**上。")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        _self_check()
        print("OK")
    else:
        main()
