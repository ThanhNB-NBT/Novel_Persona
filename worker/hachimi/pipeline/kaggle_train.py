"""Fine-tune HachimiMT-60 with high-quality replay and reviewed gold repairs.

Optimized for 2x T4 (Kaggle). Uses accelerate DDP for multi-GPU.
Run with --self-check before uploading, then follow README.md on Kaggle.
"""

from __future__ import annotations

import argparse
import hashlib
import inspect
import json
import os
import random
import re
import shutil
import tempfile
from pathlib import Path

from text_clean import clean_source


MODEL_ID = "ngocdang83/HachimiMT-60-zh-vi"
DATASET_ID = "ngocdang83/tran-vi-teacher"
MODEL_REVISION = "50cd988cefa7773c2663337e54829df8bb036659"
DATASET_REVISION = "63525802de537b11eb28aacbe1d2a23769548758"


def _pair(row: dict) -> tuple[str, str] | None:
    zh = clean_source(str(row.get("zh") or row.get("source") or row.get("source_zh") or ""))
    vi = str(row.get("vi") or row.get("proposed_vi") or row.get("target") or row.get("target_vi") or "").strip()
    if not zh or not vi:
        return None
    return zh, vi


# --- Cổng nghiêm cho replay corpus gốc ---------------------------------------
# Gold đã đọc tay chỉ kiểm tra cấu trúc. Replay phải đạt toàn bộ cổng, kể cả thoại.
_HAN = re.compile(r"[\u3400-\u9fff]")
_MODERN = re.compile(
    r"(?i)(?<!\w)(?:tôi|mình|bạn|cậu|cháu|anh ta|cô ta|cô ấy|cậu ta|ông ta|bà ta)(?!\w)"
)
_MOJIBAKE = re.compile(r"(?:�|Ã|Â(?=\s|[\"'.,;:!?])|â(?:€|™|œ|ž)|Ä(?:‘|’))")
_QUOTE_PAIRS = (("“", "”"), ("「", "」"), ("『", "』"))


def _quotes_balanced(text: str) -> bool:
    return text.count('"') % 2 == 0 and all(text.count(left) == text.count(right) for left, right in _QUOTE_PAIRS)


def _basic_structure_ok(vi: str) -> bool:
    return not (_HAN.search(vi) or _MOJIBAKE.search(vi)) and _quotes_balanced(vi)


def _source_ok(zh: str) -> bool:
    return bool(_HAN.search(zh)) and not _MOJIBAKE.search(zh) and _quotes_balanced(zh)


def _register_ok(vi: str) -> bool:
    """Tương thích script chuẩn bị cũ: gate F cấm register hiện đại cả trong thoại."""
    return not _MODERN.search(vi)


def _replay_ok(zh: str, vi: str) -> bool:
    source_len = len(re.sub(r"\s+", "", zh))
    target_len = len(re.sub(r"\s+", "", vi))
    ratio = target_len / max(1, source_len)
    return (
        _source_ok(zh)
        and _basic_structure_ok(vi)
        and _register_ok(vi)
        and re.findall(r"\d+", zh) == re.findall(r"\d+", vi)
        and 0.25 <= ratio <= 4
    )


def load_approved_gold(path: Path) -> list[dict[str, str]]:
    approved: list[dict[str, str]] = []
    seen_pairs: set[tuple[str, str]] = set()
    vi_by_zh: dict[str, str] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        row = json.loads(line)
        if row.get("status") != "approved":
            raise ValueError(f"{path}:{number} chưa có status=approved")
        pair = _pair(row)
        if pair is None:
            raise ValueError(f"{path}:{number} thiếu zh hoặc vi")
        if not _basic_structure_ok(pair[1]):
            raise ValueError(f"{path}:{number} lỗi cấu trúc cơ bản ở VI")
        if pair in seen_pairs:
            raise ValueError(f"{path}:{number} trùng hoàn toàn cặp ZH/VI")
        if pair[0] in vi_by_zh and vi_by_zh[pair[0]] != pair[1]:
            raise ValueError(f"{path}:{number} cùng ZH nhưng VI xung đột")
        seen_pairs.add(pair)
        vi_by_zh[pair[0]] = pair[1]
        approved.append({"zh": pair[0], "vi": pair[1]})
    if not approved:
        raise ValueError("approved_gold.jsonl rỗng; không train với gold chưa duyệt")
    return approved


def load_eval_reference(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    seen: set[str] = set()
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        row = json.loads(line)
        zh = clean_source(str(row.get("zh") or ""))
        vi = str(row.get("reference_vi") or "").strip()
        if row.get("status") != "locked_eval_reference" or not zh or not vi:
            raise ValueError(f"{path}:{number} không phải eval reference đã khóa")
        if zh in seen:
            raise ValueError(f"{path}:{number} trùng nguồn Trung trong eval")
        seen.add(zh)
        rows.append({"zh": zh, "vi": vi})
    if not rows:
        raise ValueError(f"{path} rỗng")
    return rows


def _source_hash(zh: str) -> str:
    return hashlib.sha256(clean_source(zh).encode("utf-8")).hexdigest()


def load_clean_shard(path: Path, *, require_approved: bool) -> list[dict]:
    """Nạp một shard đã được nhánh data duyệt; không dùng manifest lịch sử."""
    if not require_approved and any(word in path.name.lower() for word in ("review", "quarantine", "pool")):
        raise ValueError(f"{path} không phải shard replay đã duyệt")
    rows: list[dict] = []
    seen_pairs: set[tuple[str, str]] = set()
    vi_by_zh: dict[str, str] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        row = json.loads(line)
        expected_status = "approved" if require_approved else "approved_replay"
        if row.get("status") != expected_status:
            raise ValueError(f"{path}:{number} cần status={expected_status}")
        pair = _pair(row)
        if pair is None or not _basic_structure_ok(pair[1]):
            raise ValueError(f"{path}:{number} không phải cặp ZH/VI sạch")
        if pair in seen_pairs or (pair[0] in vi_by_zh and vi_by_zh[pair[0]] != pair[1]):
            raise ValueError(f"{path}:{number} trùng hoặc xung đột cùng nguồn Trung")
        seen_pairs.add(pair)
        vi_by_zh[pair[0]] = pair[1]
        rows.append({"zh": pair[0], "vi": pair[1], "source_hash": _source_hash(pair[0]),
                     "group": (row.get("novel_id"), row.get("chapter_index"))})
    if not rows:
        raise ValueError(f"{path} rỗng")
    return rows


def combine_clean_shards(gold_shards: list[list[dict]], replay_shards: list[list[dict]]) -> tuple[list[dict], list[dict]]:
    """Gold giữ ưu tiên; mọi trùng/cùng-ZH khác VI còn lại đều là lỗi provenance."""
    gold = [row for shard in gold_shards for row in shard]
    replay = [row for shard in replay_shards for row in shard]
    seen_pairs: set[tuple[str, str]] = set()
    vi_by_zh: dict[str, str] = {}
    for row in gold:
        pair = (row["zh"], row["vi"])
        if pair in seen_pairs:
            raise ValueError("Gold trùng cặp giữa các shard")
        if row["zh"] in vi_by_zh and vi_by_zh[row["zh"]] != row["vi"]:
            raise ValueError("Gold xung đột cùng ZH giữa các shard")
        seen_pairs.add(pair)
        vi_by_zh[row["zh"]] = row["vi"]
    clean_replay: list[dict] = []
    replay_pairs: set[tuple[str, str]] = set()
    for row in replay:
        pair = (row["zh"], row["vi"])
        if row["zh"] in vi_by_zh and vi_by_zh[row["zh"]] != row["vi"]:
            raise ValueError("Replay xung đột cùng ZH với gold hoặc shard khác")
        if pair in seen_pairs:
            continue  # Gold thắng exact duplicate.
        if pair in replay_pairs:
            raise ValueError("Replay trùng cặp giữa các shard")
        replay_pairs.add(pair)
        vi_by_zh[row["zh"]] = row["vi"]
        clean_replay.append(row)
    return gold, clean_replay


def assert_no_leakage(train_rows: list[dict], eval_paths: list[Path]) -> list[dict]:
    """Chặn cùng hash ZH và cùng chương khi shard có metadata chương."""
    eval_rows: list[dict] = []
    for path in eval_paths:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            zh = clean_source(str(row.get("zh") or row.get("source") or row.get("source_zh") or ""))
            if not zh:
                raise ValueError(f"{path}:{number} thiếu zh")
            eval_rows.append({"zh": zh, "vi": str(row.get("reference_vi") or row.get("vi") or ""),
                              "source_hash": _source_hash(zh),
                              "group": (row.get("novel_id"), row.get("chapter_index"))})
    hashes = {row["source_hash"] for row in eval_rows}
    groups = {row["group"] for row in eval_rows if all(value is not None for value in row["group"])}
    leaked = [row for row in train_rows if row["source_hash"] in hashes or row["group"] in groups]
    if leaked:
        raise ValueError(f"Leakage train/eval: {len(leaked)} dòng theo hash ZH hoặc nhóm chương")
    return eval_rows


def _file_manifest(path: Path, rows: list[dict], weight: int) -> dict:
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "rows": len(rows), "weight": weight}


def _line_count(path: Path) -> int:
    return sum(bool(line.strip()) for line in path.read_text(encoding="utf-8").splitlines())


def load_extra_replay(
    path: Path,
    limit: int,
    blocked_zh: set[str] | None = None,
) -> list[dict[str, str]]:
    """Load additional replay pairs from a local JSONL file (e.g. train_v2.jsonl)."""
    if not path.exists():
        return []
    blocked_zh = blocked_zh or set()
    by_zh: dict[str, str] = {}
    conflicts: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        pair = _pair(row)
        if (
            pair is None
            or pair[0] in blocked_zh
            or pair[0] in conflicts
            or not _replay_ok(*pair)
        ):
            continue
        if pair[0] in by_zh and by_zh[pair[0]] != pair[1]:
            by_zh.pop(pair[0])
            conflicts.add(pair[0])
        else:
            by_zh[pair[0]] = pair[1]
    rows = [{"zh": zh, "vi": vi} for zh, vi in by_zh.items()]
    random.Random(42).shuffle(rows)
    return rows[:limit]


def _teacher_tier(row: dict) -> str:
    meta = row.get("meta") or {}
    return str(row.get("teacher_tier") or meta.get("teacher_tier") or "").lower()


def _teacher_line_pairs(row: dict) -> list[tuple[str, str]]:
    """Tách paragraph teacher thành đúng các cặp dòng mà production sử dụng."""
    pair = _pair(row)
    if pair is None:
        return []
    source_lines = pair[0].splitlines()
    target_lines = pair[1].splitlines()
    if len(source_lines) != len(target_lines):
        return []
    lines: list[tuple[str, str]] = []
    for source, target in zip(source_lines, target_lines):
        source, target = clean_source(source), target.strip()
        if bool(source) != bool(target):
            return []
        if source:
            lines.append((source, target))
    return lines


def load_replay(
    token: str | None,
    pro_limit: int,
    replay_limit: int,
    blocked_zh: set[str],
    local_jsonl: Path | None = None,
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    """`local_jsonl` = bản `tran-vi-teacher` đã tải sẵn.

    Dataset đó GATED nên máy không có HF token (ví dụ kernel Kaggle) sẽ chết ngay ở đây.
    Có file local thì đọc thẳng, khỏi mạng và khỏi token — nội dung y hệt bản trên HF.
    """
    if local_jsonl is not None:
        def _stream():
            with local_jsonl.open(encoding="utf-8") as fh:
                for line in fh:
                    if line.strip():
                        yield json.loads(line)
        stream = _stream()
    else:
        from datasets import load_dataset

        stream = load_dataset(DATASET_ID, split="train", streaming=True, token=token,
                              revision=DATASET_REVISION)
    pro: list[dict[str, str]] = []
    replay: list[dict[str, str]] = []
    selected: dict[str, tuple[str, str]] = {}
    conflicts: set[str] = set()
    for row in stream:
        tier = _teacher_tier(row)
        if tier not in {"pro", "flash"}:
            continue
        for pair in _teacher_line_pairs(row):
            if pair[0] in blocked_zh or pair[0] in conflicts or not _replay_ok(*pair):
                continue
            previous = selected.get(pair[0])
            if previous:
                if previous[0] == pair[1]:
                    continue
                bucket = pro if previous[1] == "pro" else replay
                bucket[:] = [item for item in bucket if item["zh"] != pair[0]]
                selected.pop(pair[0])
                conflicts.add(pair[0])
                continue
            item = {
                "zh": pair[0],
                "vi": pair[1],
                "teacher_tier": tier,
                "teacher_model": str((row.get("meta") or {}).get("model") or ""),
                "teacher_row_id": str(row.get("id") or ""),
                "source_hash": _source_hash(pair[0]),
            }
            if tier == "pro" and len(pro) < pro_limit:
                pro.append(item)
                selected[pair[0]] = (pair[1], "pro")
            elif tier == "flash" and len(replay) < replay_limit:
                digest = hashlib.sha256(item["zh"].encode("utf-8")).digest()
                if int.from_bytes(digest[:2], "big") % 7 != 0:
                    continue
                replay.append(item)
                selected[pair[0]] = (pair[1], "replay")
        if len(pro) >= pro_limit and len(replay) >= replay_limit:
            break
    if len(pro) < pro_limit:
        raise RuntimeError(f"Chỉ lấy được {len(pro)}/{pro_limit} hàng Pro từ corpus gốc")
    if len(replay) < replay_limit:
        raise RuntimeError(f"Chỉ lấy được {len(replay)}/{replay_limit} hàng replay từ corpus gốc")
    return pro, replay


def build_train_rows(
    gold: list[dict[str, str]],
    pro: list[dict[str, str]],
    replay: list[dict[str, str]],
    gold_repeat: int,
    extra_replay: list[dict[str, str]] | None = None,
) -> list[dict[str, str]]:
    rows = [*pro, *replay, *(gold * gold_repeat)]
    if extra_replay:
        rows.extend(extra_replay)
    random.Random(20260719).shuffle(rows)
    return rows


def _self_check() -> None:
    assert MODEL_REVISION == "50cd988cefa7773c2663337e54829df8bb036659"
    assert DATASET_REVISION == "63525802de537b11eb28aacbe1d2a23769548758"
    assert clean_source("脸上『露』出神『色』") == "脸上露出神色"
    assert _pair({"source_zh": "甲", "target_vi": "Ất"}) == ("甲", "Ất")
    assert _source_ok('“甲”')
    assert not _source_ok("source only")
    assert not _source_ok("甲Ä‘")
    assert not _source_ok("“甲")
    assert _replay_ok('"甲 12"', '"Hắn có 12 viên."')
    assert not _replay_ok("甲", '“Tôi hiểu rồi.”')
    assert not _replay_ok("甲", "Hắn nói: \"hỏng.")
    assert not _replay_ok("甲", "Hắn nói tiếng 中文.")
    assert not _replay_ok("甲 12", "Hắn có 21 viên.")
    assert not _replay_ok("甲", "Ã©")
    assert _teacher_line_pairs({
        "source_zh": "甲。\n乙。",
        "target_vi": "Giáp.\nẤt.",
    }) == [("甲。", "Giáp."), ("乙。", "Ất.")]
    assert not _teacher_line_pairs({
        "source_zh": "甲。\n乙。",
        "target_vi": "Giáp.",
    })
    assert _teacher_tier({"meta": {"teacher_tier": "Flash_Lite"}}) == "flash_lite"
    import sys
    import types
    flash_source = next(
        f"丙{i}"
        for i in range(100)
        if int.from_bytes(hashlib.sha256(f"丙{i}".encode("utf-8")).digest()[:2], "big") % 7 == 0
    )
    flash_number = re.findall(r"\d+", flash_source)[0]
    fake_datasets = types.ModuleType("datasets")
    fake_datasets.load_dataset = lambda *args, **kwargs: iter([
        {
            "id": "lite",
            "source_zh": "丁。",
            "target_vi": "Đinh.",
            "meta": {"teacher_tier": "flash_lite", "model": "lite"},
        },
        {
            "id": "pro",
            "source_zh": "甲。\n乙。",
            "target_vi": "Giáp.\nẤt.",
            "meta": {"teacher_tier": "pro", "model": "pro"},
        },
        {
            "id": "flash",
            "source_zh": flash_source,
            "target_vi": f"Bính {flash_number}",
            "meta": {"teacher_tier": "flash", "model": "flash"},
        },
    ])
    previous_datasets = sys.modules.get("datasets")
    sys.modules["datasets"] = fake_datasets
    try:
        checked_pro, checked_flash = load_replay(None, 2, 1, set())
        assert [row["teacher_tier"] for row in checked_pro] == ["pro", "pro"]
        assert [row["teacher_tier"] for row in checked_flash] == ["flash"]
    finally:
        if previous_datasets is None:
            sys.modules.pop("datasets", None)
        else:
            sys.modules["datasets"] = previous_datasets
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "approved.jsonl"
        path.write_text('{"zh":"甲","vi":"Ất","status":"approved"}\n', encoding="utf-8")
        assert load_approved_gold(path) == [{"zh": "甲", "vi": "Ất"}]
        eval_path = Path(directory) / "eval.jsonl"
        eval_path.write_text(
            '{"zh":"乙","reference_vi":"B","status":"locked_eval_reference"}\n',
            encoding="utf-8",
        )
        assert load_eval_reference(eval_path) == [{"zh": "乙", "vi": "B"}]
        replay_path = Path(directory) / "replay.jsonl"
        replay_path.write_text(
            '{"zh":"乙","vi":"B"}\n'
            '{"zh":"丙","vi":"C"}\n'
            '{"zh":"丙","vi":"D"}\n'
            '{"zh":"丁","vi":"Đ"}\n',
            encoding="utf-8",
        )
        assert load_extra_replay(replay_path, 10, {"乙"}) == [{"zh": "丁", "vi": "Đ"}]
        path.write_text(
            '{"zh":"甲","vi":"Ất","status":"approved"}\n'
            '{"zh":"甲","vi":"B","status":"approved"}\n',
            encoding="utf-8",
        )
        try:
            load_approved_gold(path)
            raise AssertionError("phải chặn cùng ZH nhưng VI xung đột")
        except ValueError as exc:
            assert "VI xung đột" in str(exc)
    assert len(build_train_rows([{"zh": "甲", "vi": "Ất"}], [], [], 3)) == 3
    assert len(build_train_rows([{"zh": "甲", "vi": "Ất"}], [], [], 3, [{"zh": "乙", "vi": "B"}])) == 4
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        gold_path, eval_path = root / "gold.jsonl", root / "eval.jsonl"
        gold_path.write_text('{"zh":"甲","vi":"Ất","status":"approved","novel_id":1,"chapter_index":1}\n', encoding="utf-8")
        eval_path.write_text('{"zh":"乙","reference_vi":"B","status":"locked_eval_reference","novel_id":2,"chapter_index":1}\n', encoding="utf-8")
        gold = load_clean_shard(gold_path, require_approved=True)
        locked = assert_no_leakage(gold, [eval_path])
        assert {row["zh"] for row in locked} == {"乙"}
        assert _file_manifest(gold_path, gold, 3)["rows"] == 1
        review_pool = root / "review_pool.jsonl"
        review_pool.write_text('{"zh":"丙","vi":"B","status":"approved_replay"}\n', encoding="utf-8")
        try:
            load_clean_shard(review_pool, require_approved=False)
            raise AssertionError("phải chặn review pool")
        except ValueError:
            pass
        replay_one = [{"zh": "甲", "vi": "Khác", "source_hash": _source_hash("甲"), "group": (3, 1)}]
        try:
            combine_clean_shards([gold], [replay_one])
            raise AssertionError("phải chặn conflict xuyên shard")
        except ValueError:
            pass
        chapter_eval = root / "chapters.jsonl"
        chapter_eval.write_text('{"zh":"庚","reference_vi":"G","novel_id":1,"chapter_index":1}\n', encoding="utf-8")
        try:
            assert_no_leakage(gold, [chapter_eval])
            raise AssertionError("phải chặn leakage cùng chương")
        except ValueError:
            pass


def _export_ct2(output_dir: Path) -> None:
    """Xuất CT2 int8. Base HachimiMT-60 không có hàng <pad> thừa ở cuối vocab,
    nên vô hiệu 2 bước cắt pad của CT2 (nếu để mặc định sẽ lệch 24000 vs 23999).
    Dùng Python API thay CLI để monkeypatch có hiệu lực trong cùng tiến trình.
    """
    import ctranslate2.converters.transformers as ct2t
    from ctranslate2.converters import TransformersConverter

    ct2t.MarianMTLoader._remove_pad_weights = lambda self, spec: None
    ct2t.MarianMTLoader.get_vocabulary = ct2t.BartLoader.get_vocabulary

    # transformers 4.48 tuồn kwarg 'dtype' vào MarianMTModel.__init__ (chữ ký cũ không
    # nhận) → TypeError khi bộ chuyển CT2 gọi from_pretrained. Bọc __init__ để bỏ 'dtype'.
    from transformers import MarianMTModel
    _orig_init = MarianMTModel.__init__

    def _init_no_dtype(self, config, *a, **kw):
        kw.pop("dtype", None)
        _orig_init(self, config, *a, **kw)

    MarianMTModel.__init__ = _init_no_dtype

    ct2_dir = output_dir / "ct2-int8_float32"
    TransformersConverter(str(output_dir)).convert(
        str(ct2_dir), quantization="int8_float32", force=True
    )
    for name in ("source.spm", "target.spm", "vocab.json", "tokenizer_config.json"):
        source = output_dir / name
        if source.exists():
            shutil.copy2(source, ct2_dir / name)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gold", type=Path, required=False)
    parser.add_argument("--eval", dest="eval_path", type=Path, required=False)
    parser.add_argument("--clean-gold", type=Path, action="append", default=[])
    parser.add_argument("--clean-replay", type=Path, action="append", default=[])
    parser.add_argument("--eval-chapters", type=Path, action="append", default=[])
    parser.add_argument("--doclevel-corpus", type=Path, default=None,
                        help="Corpus doc-level dựng sẵn (pipeline 17). Bật nhánh doc-level: nạp "
                             "thẳng {zh(có ⟪ctx⟫),vi}, BỎ toàn bộ gold/replay/HF-streaming.")
    parser.add_argument("--eval-holdout", type=int, default=2000,
                        help="Số cặp cuối corpus giữ làm eval (nhánh doc-level).")
    parser.add_argument("--extra-replay", type=Path, default=None,
                        help="Optional local JSONL with extra replay pairs (e.g. train_v2.jsonl)")
    parser.add_argument("--extra-replay-limit", type=int, default=20_000)
    parser.add_argument("--output-dir", type=Path, default=Path("/kaggle/working/hachimi-60-cophong"))
    parser.add_argument("--hf-token", default=os.environ.get("HF_TOKEN"))
    parser.add_argument("--teacher-jsonl", type=Path, default=None,
                        help="Bản tran-vi-teacher tải sẵn; có thì KHÔNG cần token/mạng")
    parser.add_argument("--pro-limit", type=int, default=9_000)
    parser.add_argument("--replay-limit", type=int, default=24_000)
    parser.add_argument("--gold-repeat", type=int, choices=(1, 3), default=1)
    parser.add_argument("--epochs", type=float, default=1.0)
    parser.add_argument("--lr", type=float, default=1e-5)
    parser.add_argument("--per-device-batch", type=int, default=8)
    parser.add_argument("--grad-accum", type=int, default=4)
    parser.add_argument("--warmup-ratio", type=float, default=0.05)
    parser.add_argument("--weight-decay", type=float, default=0.01)
    parser.add_argument("--export-ct2", action="store_true")
    parser.add_argument("--resume-from-checkpoint", type=Path, default=None,
                        help="Chỉ tiếp tục run HF bị ngắt; không phải nền CT2")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        _self_check()
        print("OK")
        return
    if args.doclevel_corpus is None:
        if args.gold is None and not args.clean_gold:
            raise SystemExit("Cần --gold approved_gold.jsonl")
        if args.eval_path is None:
            raise SystemExit("Cần --eval eval_reference.jsonl")

    if args.doclevel_corpus is not None:
        # Nhánh doc-level: corpus dựng sẵn (pipeline 17) đã lọc register/Hán/lặp + trộn
        # người/máy + gắn ⟪ctx⟫. Không cần gold/replay/HF-streaming ở đây.
        corpus = [json.loads(l) for l in args.doclevel_corpus.read_text(encoding="utf-8").splitlines() if l.strip()]
        rows_all = [{"zh": r["zh"], "vi": r["vi"]} for r in corpus]
        random.Random(20260731).shuffle(rows_all)
        holdout = min(args.eval_holdout, len(rows_all) // 20)
        eval_rows = rows_all[:holdout]
        rows = rows_all[holdout:]
        eval_zh = {r["zh"] for r in eval_rows}
        rows = [r for r in rows if r["zh"] not in eval_zh]  # chống rò eval sang train
        print(f"Doc-level corpus: train {len(rows)} · eval-holdout {len(eval_rows)}")
        manifest = {
            "base_model": MODEL_ID,
            "base_model_revision": MODEL_REVISION,
            "seed": 20260731,
            "doclevel_corpus": _file_manifest(args.doclevel_corpus, corpus, 1),
        }
        _train_and_export(args, rows, eval_rows, manifest)
        return

    if args.clean_gold and args.gold:
        raise SystemExit("Chỉ dùng --clean-gold hoặc --gold")
    if args.clean_gold and args.extra_replay:
        raise SystemExit("Không trộn shard sạch với --extra-replay lịch sử")
    forbidden = {"train_v2.jsonl", "train_gold_vnext.jsonl"}
    if any(path.name in forbidden for path in [*args.clean_gold, *args.clean_replay]):
        raise SystemExit("Không dùng train_v2.jsonl hoặc train_gold_vnext.jsonl")
    gold_paths = args.clean_gold or [args.gold]
    gold_shards = [load_clean_shard(path, require_approved=True) for path in gold_paths]
    clean_replay_shards = [load_clean_shard(path, require_approved=False) for path in args.clean_replay]
    clean_gold, clean_replay = combine_clean_shards(gold_shards, clean_replay_shards)
    gold = [{"zh": row["zh"], "vi": row["vi"]} for row in clean_gold]
    eval_rows = load_eval_reference(args.eval_path)
    eval_paths = [args.eval_path, *args.eval_chapters]
    eval_lock_rows = assert_no_leakage([*clean_gold, *clean_replay], eval_paths)
    gold_zh = {row["zh"] for row in gold}
    eval_zh = {row["zh"] for row in eval_lock_rows}
    overlap = gold_zh & eval_zh
    if overlap:
        raise SystemExit(f"Gold trùng eval: {len(overlap)} nguồn Trung")
    print(f"Gold đã duyệt: {len(gold)}")
    print(f"Eval đã khóa: {len(eval_rows)}")

    extra_replay: list[dict[str, str]] = [{"zh": row["zh"], "vi": row["vi"]} for row in clean_replay]
    if args.extra_replay:
        extra_replay = load_extra_replay(
            args.extra_replay,
            args.extra_replay_limit,
            gold_zh | eval_zh,
        )
        print(f"Extra replay từ {args.extra_replay.name}: {len(extra_replay)}")
    blocked_zh = gold_zh | eval_zh | {row["zh"] for row in extra_replay}
    pro, replay = ([], [])
    if args.pro_limit or args.replay_limit:
        pro, replay = load_replay(
            args.hf_token,
            args.pro_limit,
            args.replay_limit,
            blocked_zh,
            args.teacher_jsonl,
        )

    rows = build_train_rows(gold, pro, replay, args.gold_repeat, extra_replay)
    print(f"Train: Pro={len(pro)}, replay={len(replay)}, extra={len(extra_replay)}, gold-weighted={len(gold) * args.gold_repeat}")
    print(f"Total rows: {len(rows)}")

    manifest = {
        "base_model": MODEL_ID,
        "base_model_revision": MODEL_REVISION,
        "teacher_dataset": DATASET_ID,
        "teacher_dataset_revision": DATASET_REVISION,
        "seed": 20260719,
        "resume_from_checkpoint": str(args.resume_from_checkpoint) if args.resume_from_checkpoint else None,
        "clean_gold": [_file_manifest(path, shard, args.gold_repeat) for path, shard in zip(gold_paths, gold_shards)],
        "clean_replay": [_file_manifest(path, shard, 1) for path, shard in zip(args.clean_replay, clean_replay_shards)],
        "effective_clean_gold": len(clean_gold),
        "effective_clean_replay": len(clean_replay),
        "eval_shards": [_file_manifest(path, [{}] * _line_count(path), 0) for path in eval_paths],
        "pro": len(pro), "replay": len(replay), "extra_replay": len(extra_replay),
        "gold": len(gold), "gold_repeat": args.gold_repeat,
    }
    _train_and_export(args, rows, eval_rows, manifest)


def _train_and_export(args, rows: list[dict], eval_rows: list[dict], manifest: dict) -> None:
    import torch
    from transformers import (
        AutoModelForSeq2SeqLM,
        AutoTokenizer,
        DataCollatorForSeq2Seq,
        Seq2SeqTrainer,
        Seq2SeqTrainingArguments,
    )

    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, token=args.hf_token, revision=MODEL_REVISION)
    model = AutoModelForSeq2SeqLM.from_pretrained(MODEL_ID, token=args.hf_token, revision=MODEL_REVISION)
    if torch.cuda.is_available():
        model.gradient_checkpointing_enable()
        model.config.use_cache = False

    def tokenize(items: list[dict[str, str]]) -> list[dict]:
        inputs = tokenizer(
            [row["zh"] for row in items],
            text_target=[row["vi"] for row in items],
            truncation=True,
            max_length=448,
        )
        labels = inputs.pop("labels")
        inputs["labels"] = labels
        return [
            {key: values[index] for key, values in inputs.items()}
            for index in range(len(items))
        ]

    class RowsDataset(torch.utils.data.Dataset):
        def __init__(self, items: list[dict]):
            self.items = items

        def __len__(self) -> int:
            return len(self.items)

        def __getitem__(self, index: int) -> dict:
            return self.items[index]

    tokenized_train = RowsDataset(tokenize(rows))
    tokenized_eval = RowsDataset(tokenize(eval_rows))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    training_options = {
        "output_dir": str(args.output_dir),
        "learning_rate": args.lr,
        "num_train_epochs": args.epochs,
        "per_device_train_batch_size": args.per_device_batch,
        "per_device_eval_batch_size": args.per_device_batch,
        "gradient_accumulation_steps": args.grad_accum,
        "fp16": torch.cuda.is_available(),
        "warmup_ratio": args.warmup_ratio,
        "weight_decay": args.weight_decay,
        "lr_scheduler_type": "cosine",
        "eval_steps": 100,
        "save_strategy": "steps",
        "save_steps": 100,
        "save_total_limit": 3,
        "logging_steps": 20,
        "predict_with_generate": True,
        "generation_max_length": 448,
        "report_to": "none",
        "seed": 20260719,
        "dataloader_num_workers": 2 if torch.cuda.is_available() else 0,
        "ddp_find_unused_parameters": False,
    }
    strategy_key = (
        "eval_strategy"
        if "eval_strategy" in inspect.signature(Seq2SeqTrainingArguments).parameters
        else "evaluation_strategy"
    )
    training_options[strategy_key] = "steps"
    training_args = Seq2SeqTrainingArguments(**training_options)
    trainer_options = dict(
        model=model,
        args=training_args,
        train_dataset=tokenized_train,
        eval_dataset=tokenized_eval,
        data_collator=DataCollatorForSeq2Seq(tokenizer, model=model),
    )
    processor_key = (
        "processing_class"
        if "processing_class" in inspect.signature(Seq2SeqTrainer).parameters
        else "tokenizer"
    )
    trainer_options[processor_key] = tokenizer
    trainer = Seq2SeqTrainer(**trainer_options)
    if args.resume_from_checkpoint and not all((args.resume_from_checkpoint / name).is_file() for name in ("model.safetensors", "trainer_state.json")):
        raise SystemExit("--resume-from-checkpoint chỉ nhận run HF bị ngắt có model.safetensors + trainer_state.json")
    trainer.train(resume_from_checkpoint=str(args.resume_from_checkpoint) if args.resume_from_checkpoint else None)
    trainer.save_model(str(args.output_dir))
    trainer.accelerator.wait_for_everyone()
    if trainer.is_world_process_zero():
        tokenizer.save_pretrained(str(args.output_dir))
        (args.output_dir / "training_mix.json").write_text(
            json.dumps({
                **manifest,
                "eval": len(eval_rows),
                "total_rows": len(rows),
                "epochs": args.epochs,
                "lr": args.lr,
                "effective_batch": args.per_device_batch * args.grad_accum,
            }, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        if args.export_ct2:
            _export_ct2(args.output_dir)
        print(f"Xong: {args.output_dir}")


if __name__ == "__main__":
    main()
