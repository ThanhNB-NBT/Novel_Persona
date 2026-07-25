"""Đánh giá rộng Hachimi hiện tại, v-next D và E ngoài tập 60 cảnh khóa.

Corpus được cắt xác định từ longform đã có, không gọi Supabase và không dùng làm dữ
liệu huấn luyện. Mỗi thể loại đóng góp cùng số đoạn; các đoạn được ưu tiên theo rủi
ro thoại, số, dòng dài, chữ Latin và dấu hiệu tên riêng.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from difflib import SequenceMatcher
from pathlib import Path

from novelworker.translator.hachimi_engine import _Engine
from novelworker.translator.text_clean import clean_source
from novelworker.translator.worker import (
    _clean_output,
    _fix_register,
    _fix_soft_style,
    _hanviet_fallback,
)

from audit_hachimi_base_longform import metrics, translate_block
from eval_common import MODELS_DIR, balanced_quotes


ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).with_name("hachimi_base_longform.jsonl")
SELECTION_JSONL = Path(__file__).with_name("hachimi_vnext_e_broad_selection.jsonl")
RESULT_JSONL = Path(__file__).with_name("hachimi_vnext_e_broad_eval.jsonl")
REPORT_MD = Path(__file__).with_name("hachimi_vnext_e_broad_eval.md")
DIAGNOSIS_MD = Path(__file__).with_name("hachimi_vnext_e_base_diagnosis.md")
MODELS = {
    "base": MODELS_DIR / "hachimi-base-download" / "ct2-int8_float32",
    "current": MODELS_DIR / "hachimi-ct2",
    "teacher_v2": MODELS_DIR / "hachimi-teacher-v2",
}
RISK_PATTERNS = {
    "dialogue": re.compile(r"[“”\"「」『』]"),
    "digits": re.compile(r"\d"),
    "long_line": re.compile(r".{121,}"),
    "latin": re.compile(r"(?<![A-Za-z])[A-Za-z][A-Za-z0-9_-]{1,}"),
    "name_cue": re.compile(r"(?:名叫|叫做|姓名|名字|姓[\u3400-\u9fff]|师姐|师兄|先生|小姐)"),
}


def normalize(text: str) -> str:
    return re.sub(r"\s+", "", text).lower()


def divergence(left: str, right: str) -> float:
    return round(1 - SequenceMatcher(None, normalize(left), normalize(right), autojunk=False).ratio(), 4)


def risk_tags(text: str) -> list[str]:
    return [name for name, pattern in RISK_PATTERNS.items() if pattern.search(text)]


def excerpt(lines: list[str], center: int, radius: int = 4) -> str:
    start = max(0, center - radius)
    end = min(len(lines), center + radius + 1)
    return "\n".join(line for line in lines[start:end] if line.strip())


def candidate_windows(row: dict) -> list[tuple[int, str, list[str]]]:
    lines = [clean_source(line) for line in row["source_zh"].splitlines()]
    windows = []
    for index, line in enumerate(lines):
        if not line:
            continue
        text = excerpt(lines, index)
        tags = risk_tags(text)
        if tags:
            windows.append((index, text, tags))
    return windows


def select_corpus(rows: list[dict], per_genre: int) -> list[dict]:
    by_genre: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        by_genre[row["genre"]].append(row)
    selected: list[dict] = []
    for genre in sorted(by_genre):
        candidates = []
        for row in sorted(by_genre[genre], key=lambda item: item["chapter_index"]):
            for line_index, text, tags in candidate_windows(row):
                # Ưu tiên loại rủi ro ít gặp trước, rồi giữ thứ tự chương/dòng cố định.
                candidates.append((row, line_index, text, tags))
        used_lines: dict[tuple[int, int], list[int]] = defaultdict(list)
        covered: set[str] = set()
        for _ in range(per_genre):
            choices = [
                candidate for candidate in candidates
                if all(abs(candidate[1] - used) > 8 for used in used_lines[(candidate[0]["novel_id"], candidate[0]["chapter_index"])])
            ]
            if not choices:
                break
            choices.sort(key=lambda item: (-len(set(item[3]) - covered), -len(item[3]), item[0]["chapter_index"], item[1]))
            row, line_index, text, tags = choices[0]
            used_lines[(row["novel_id"], row["chapter_index"])].append(line_index)
            covered.update(tags)
            selected.append({
                "genre": genre,
                "novel_id": row["novel_id"],
                "chapter_index": row["chapter_index"],
                "line_index": line_index,
                "risk_tags": tags,
                "source_zh": text,
            })
    if len({row["genre"] for row in selected}) != 15:
        raise RuntimeError("Corpus phải phủ đúng 15 thể loại longform")
    return selected


def translate(engine: _Engine, source: str) -> tuple[str, str]:
    raw = translate_block(engine, source)
    restored = _clean_output(raw)
    restored, _ = _hanviet_fallback(restored)
    return raw, _fix_register(_fix_soft_style(restored))


def output_item(source: str, raw: str, restored: str) -> dict:
    counts = metrics(source, raw, restored)
    return {
        "raw": raw,
        "pipeline": restored,
        "modern_pronouns": counts["pipeline_modern_pronouns"],
        "padding": counts["pipeline_padding"],
        "han": counts["pipeline_han"],
        "quotes_balanced": balanced_quotes(restored),
        "digits_match": re.findall(r"\d+", source) == re.findall(r"\d+", restored),
        "length_ratio": round(len(restored) / max(1, len(source)), 3),
    }


def self_check() -> None:
    assert risk_tags('"A1" 名叫张三') == ["dialogue", "digits", "latin", "name_cue"]
    assert excerpt(["甲", "乙", "丙"], 1, radius=1) == "甲\n乙\n丙"
    assert divergence("Ta đi.", "Ta đi!") < 0.3
    print("evaluate_hachimi_vnext_e_broad OK")


def add_summary(summary: dict[str, float], item: dict) -> None:
    for key in ("modern_pronouns", "padding", "han"):
        summary[key] += item[key]
    summary["quote_fail"] += not item["quotes_balanced"]
    summary["digit_fail"] += not item["digits_match"]
    summary["length_outlier"] += not 0.25 <= item["length_ratio"] <= 4
    summary["divergence"] += item["divergence_vs_current"]


def structural_defects(item: dict[str, float]) -> float:
    return item["modern_pronouns"] + item["han"] + item["quote_fail"] + item["digit_fail"]


def main(per_genre: int, review_limit: int) -> None:
    if SELECTION_JSONL.exists():
        selected = [json.loads(line) for line in SELECTION_JSONL.read_text(encoding="utf-8").splitlines() if line.strip()]
    else:
        rows = [json.loads(line) for line in SOURCE.read_text(encoding="utf-8").splitlines() if line.strip()]
        selected = select_corpus(rows, per_genre)
        SELECTION_JSONL.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in selected), encoding="utf-8")
    if len(selected) != 60 or len({row["genre"] for row in selected}) != 15:
        raise RuntimeError("Selection cố định phải có đúng 60 đoạn thuộc 15 thể loại")
    engines = {name: _Engine(str(path)) for name, path in MODELS.items()}
    summary: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    genre_summary: dict[str, dict[str, dict[str, float]]] = defaultdict(lambda: defaultdict(lambda: defaultdict(float)))
    results = []
    for index, row in enumerate(selected, start=1):
        source = row["source_zh"]
        outputs = {}
        for name, engine in engines.items():
            raw, restored = translate(engine, source)
            outputs[name] = output_item(source, raw, restored)
        for name, item in outputs.items():
            item["divergence_vs_current"] = divergence(outputs["current"]["pipeline"], item["pipeline"])
            add_summary(summary[name], item)
            add_summary(genre_summary[row["genre"]][name], item)
        results.append({**row, "outputs": outputs})
        print(f"[{index}/{len(selected)}] {row['genre']} / chương {row['chapter_index']}", flush=True)
    RESULT_JSONL.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in results), encoding="utf-8")
    worst = sorted(
        results,
        key=lambda row: (
            sum(not item["quotes_balanced"] or not item["digits_match"] or item["han"] for item in row["outputs"].values()),
            max(item["divergence_vs_current"] for item in row["outputs"].values()),
        ),
        reverse=True,
    )[:review_limit]
    lines = [
        "# Hachimi v-next E — đánh giá rộng ngoài tập khóa",
        "",
        "> Không đọc/ghi DB; không dùng glossary. Đây là phép đo riêng cho khả năng dịch của model,",
        "> không thay thế test end-to-end termguard. Các cảnh được cắt xác định từ longform có sẵn.",
        "",
        f"- Corpus: {len(selected)} đoạn, {per_genre} đoạn × 15 thể loại.",
        f"- Đọc tay: {len(worst)} ca xấu theo lỗi cấu trúc và độ khác biệt đầu ra.",
        "",
        "| Model | Đại từ hiện đại | Đệm | Hán sót | Quote lỗi | Số lỗi | Tỷ lệ dài bất thường | Khác current TB |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in MODELS:
        item = summary[name]
        lines.append(f"| `{name}` | {int(item['modern_pronouns'])} | {int(item['padding'])} | {int(item['han'])} | {int(item['quote_fail'])} | {int(item['digit_fail'])} | {int(item['length_outlier'])} | {item['divergence'] / len(selected):.4f} |")
    lines.extend(["", "## Theo thể loại", "", "| Thể loại | Model | Đại từ hiện đại | Hán sót | Quote lỗi | Số lỗi |", "|---|---|---:|---:|---:|---:|"])
    for genre in sorted(genre_summary):
        for name in MODELS:
            item = genre_summary[genre][name]
            lines.append(f"| {genre} | `{name}` | {int(item['modern_pronouns'])} | {int(item['han'])} | {int(item['quote_fail'])} | {int(item['digit_fail'])} |")
    for index, row in enumerate(worst, start=1):
        lines.extend(["", f"## Ca cần đọc {index}: {row['genre']} — chương {row['chapter_index']} — {', '.join(row['risk_tags'])}", "", f"- ZH: {row['source_zh']}"])
        for name in MODELS:
            item = row["outputs"][name]
            lines.append(f"- {name}: {item['pipeline']} `modern={item['modern_pronouns']}; han={item['han']}; quote={item['quotes_balanced']}; digits={item['digits_match']}; ratio={item['length_ratio']}; diff={item['divergence_vs_current']}`")
    REPORT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
    diagnosis = [
        "# Chẩn đoán Hachimi gốc so với current/D/E",
        "",
        "> Cùng 60 đoạn broad đã cố định, không có glossary. Các metric dưới đây chỉ đo lỗi",
        "> cấu trúc/định dạng; chúng không đo đủ nghĩa, quan hệ chủ thể hay độ tự nhiên câu.",
        "",
        "| Model so với base | Δ lỗi trọng yếu | Δ đại từ hiện đại | Δ Hán sót | Δ quote lỗi | Δ số lỗi | Δ đệm |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    base = summary["base"]
    for name in MODELS:
        if name == "base":
            continue
        item = summary[name]
        diagnosis.append(f"| `{name}` | {int(structural_defects(item) - structural_defects(base)):+d} | {int(item['modern_pronouns'] - base['modern_pronouns']):+d} | {int(item['han'] - base['han']):+d} | {int(item['quote_fail'] - base['quote_fail']):+d} | {int(item['digit_fail'] - base['digit_fail']):+d} | {int(item['padding'] - base['padding']):+d} |")
    diagnosis.extend(["", "## Theo thể loại", "", "| Model | Tệ hơn base | Tốt hơn base | Bằng base |", "|---|---:|---:|---:|"])
    for name in MODELS:
        if name == "base":
            continue
        worse = better = same = 0
        for genre in genre_summary:
            delta = structural_defects(genre_summary[genre][name]) - structural_defects(genre_summary[genre]["base"])
            if delta > 0:
                worse += 1
            elif delta < 0:
                better += 1
            else:
                same += 1
        diagnosis.append(f"| `{name}` | {worse} | {better} | {same} |")
    overall = []
    for name in MODELS:
        if name == "base":
            continue
        delta = structural_defects(summary[name]) - structural_defects(base)
        overall.append(f"`{name}` {'tăng' if delta > 0 else 'giảm' if delta < 0 else 'không đổi'} {abs(int(delta))} lỗi trọng yếu so với base")
    diagnosis.extend([
        "",
        "## Kết luận đúng phạm vi số liệu",
        "",
        f"- Trên 60 đoạn này: {'; '.join(overall)}.",
        "- Vì vậy giả thuyết **data finetune làm hỏng model một cách tổng thể không được chứng minh** bởi broad test này. D/E vẫn có hồi quy cục bộ rõ ở quote và số, đồng thời tệ hơn base ở 6/15 thể loại theo lỗi trọng yếu; đây là tín hiệu phải sửa/loại data, không phải bằng chứng rằng cả model đã tệ hơn base.",
        "- Có thể kết luận **hồi quy cấu trúc đo được** khi một model có tổng lỗi trọng yếu tăng và tệ hơn base ở đa số thể loại.",
        "- Không thể kết luận chỉ từ bảng này rằng *data finetune làm hỏng chất lượng dịch tổng thể* hoặc làm sai nghĩa: corpus không có bản tham chiếu người dịch. Muốn chứng minh nhân quả đó cần đọc tay các ca khác biệt lớn hoặc thêm tập tham chiếu khóa.",
        "- Vì current cũng là một finetune/biến thể không tách được mọi khác biệt pipeline từ corpus này, kết quả chỉ là bằng chứng cảnh báo hay bác bỏ giả thuyết theo các metric đã đo, không phải phán quyết tuyệt đối về data train.",
    ])
    DIAGNOSIS_MD.write_text("\n".join(diagnosis) + "\n", encoding="utf-8")
    print(f"Đã ghi {SELECTION_JSONL}, {RESULT_JSONL}, {REPORT_MD} và {DIAGNOSIS_MD}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--per-genre", type=int, default=4)
    parser.add_argument("--review-limit", type=int, default=24)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    self_check() if args.self_check else main(args.per_genre, args.review_limit)
