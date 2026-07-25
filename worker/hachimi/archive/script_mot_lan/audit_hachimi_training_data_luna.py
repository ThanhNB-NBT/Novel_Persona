"""Kiểm toán dữ liệu fine-tune Hachimi bằng thư viện chuẩn.

Script chỉ đọc JSONL và mã nguồn train, rồi ghi một báo cáo vào cùng thư mục.
Không sửa dữ liệu, không gọi mạng và không ghi DB.
"""

from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from difflib import SequenceMatcher
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "hachimi_finetune"
OUT = Path(__file__).with_name("hachimi_training_data_audit_luna.md")
HAN = re.compile(r"[\u3400-\u9fff]")
MOJIBAKE = re.compile(r"(?:Ã|Â|â€|ðŸ|ï¼|ã€|\*\*)")
AUTHOR = re.compile(r"作者|本章|求票|收藏|订阅|感谢|读者|完本|笔者|编辑")
MODERN = re.compile(r"\b(?:tôi|mình|cậu|anh ta|cô ta|cậu ta|ông ta|bà ta)\b", re.I)
NAME_STUCK = re.compile(r"[a-z][A-ZĐ][a-z]{2,}")
FILES = sorted(ROOT.rglob("*.jsonl"))


def pair(row: dict) -> tuple[str, str]:
    if row.get("zh_lines"):
        return "\n".join(str(item).strip() for item in row["zh_lines"]), ""
    return (
        str(row.get("zh") or row.get("source") or row.get("source_zh") or "").strip(),
        str(row.get("vi") or row.get("target") or row.get("target_vi") or row.get("proposed_vi") or row.get("vi_model") or "").strip(),
    )


def load(path: Path) -> tuple[list[tuple[int, dict]], list[str]]:
    rows, errors = [], []
    with path.open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                rows.append((number, json.loads(line)))
            except json.JSONDecodeError as exc:
                errors.append(f"dòng {number}: {exc.msg}")
    return rows, errors


def fmt(value: str, limit: int = 180) -> str:
    return value.replace("\n", " ").strip()[:limit]


def sample(items: list[tuple[str, str, str, int, str]], limit: int = 5) -> list[str]:
    return [f"{source}:{line}: {fmt(zh)} | {fmt(vi)} | {reason}" for source, zh, vi, line, reason in items[:limit]]


def near_pairs(rows: list[tuple[int, dict]], limit: int = 12) -> list[tuple[str, str, int, str]]:
    candidates: dict[str, list[tuple[int, str, str]]] = defaultdict(list)
    for line, row in rows:
        zh, vi = pair(row)
        if len(zh) < 24:
            continue
        for gram in {zh[i:i + 4] for i in range(0, min(len(zh) - 3, 80), 4)}:
            candidates[gram].append((line, zh, vi))
    found, seen = [], set()
    for values in candidates.values():
        if len(values) > 40:
            continue
        for i, left in enumerate(values):
            for right in values[i + 1:]:
                key = tuple(sorted((left[0], right[0])))
                if key in seen or left[1] == right[1]:
                    continue
                seen.add(key)
                score = SequenceMatcher(None, left[1], right[1]).ratio()
                if score >= 0.92:
                    found.append(("train_gold_vnext", left[1], left[0], f"gần dòng {right[0]}, ZH giống {score:.2f}; VI đối chiếu: {fmt(right[2], 80)}"))
                    if len(found) >= limit:
                        return found
    return found


def inspect(name: str, rows: list[tuple[int, dict]]) -> dict:
    pairs = Counter(pair(row) for _, row in rows)
    zhs = defaultdict(list)
    for line, row in rows:
        zhs[pair(row)[0]].append((line, pair(row)[1]))
    conflicts = [(zh, values[0][1], values[0][0], "cùng ZH có VI khác") for zh, values in zhs.items() if len({vi for _, vi in values}) > 1]
    flags: dict[str, list[tuple[str, str, str, int, str]]] = defaultdict(list)
    for line, row in rows:
        zh, vi = pair(row)
        source = name
        if not zh or not vi:
            flags["thiếu ZH/VI"].append((source, zh, vi, line, vi or "VI trống"))
        if HAN.search(vi):
            flags["VI còn chữ Hán"].append((source, zh, vi, line, "VI còn chữ Hán"))
        if MODERN.search(vi):
            flags["xưng hô hiện đại cần duyệt"].append((source, zh, vi, line, "có đại từ hiện đại; chưa kết luận sai"))
        if NAME_STUCK.search(vi):
            flags["tên/chữ Latin dính"].append((source, zh, vi, line, "nghi dính từ Latin"))
        if MOJIBAKE.search(zh) or MOJIBAKE.search(vi):
            flags["artefact ký tự/dấu câu"].append((source, zh, vi, line, "nghi mojibake hoặc marker"))
        if AUTHOR.search(zh):
            flags["author note/meta"].append((source, zh, vi, line, "ZH có từ khóa lời tác giả/meta"))
        if len(zh) >= 20 and not 0.25 <= len(vi) / len(zh) <= 5:
            flags["tỷ lệ độ dài bất thường"].append((source, zh, vi, line, f"tỷ lệ ký tự VI/ZH={len(vi)/len(zh):.2f}"))
        if sum(ch.isdigit() for ch in zh) != sum(ch.isdigit() for ch in vi):
            flags["số liệu không khớp cần duyệt"].append((source, zh, vi, line, "số chữ số ZH/VI khác nhau"))
        if vi.count('"') % 2:
            flags["dấu thoại không cân"].append((source, zh, vi, line, "số dấu quote tiếng Việt lẻ"))
    return {"rows": len(rows), "pairs": pairs, "zhs": zhs, "conflicts": conflicts, "flags": flags}


def main() -> None:
    loaded = {p.relative_to(ROOT).as_posix(): load(p) for p in FILES}
    audits = {name: inspect(name, rows) for name, (rows, _) in loaded.items()}
    manifest = audits.get("dataset/train_gold_vnext.jsonl")
    lines = ["# Kiểm toán dữ liệu fine-tune Hachimi — Luna", "", "Phạm vi: đọc toàn bộ JSONL dưới `worker/hachimi_finetune`; không train, không DB, không sửa gold. `status=approved` chỉ là trạng thái trong file, không phải bằng chứng người duyệt.", "", "## 1. Thống kê toàn bộ JSONL", "", "| Tập | Dòng | Cặp duy nhất | Trùng cặp dư | ZH trùng | ZH xung đột VI | JSON lỗi |", "|---|---:|---:|---:|---:|---:|---:|"]
    for name, (rows, errors) in loaded.items():
        data = audits[name]
        duplicate = sum(n - 1 for n in data["pairs"].values() if n > 1)
        zh_dup = sum(len(v) - 1 for v in data["zhs"].values() if len(v) > 1)
        lines.append(f"| `{name}` | {len(rows)} | {len(data['pairs'])} | {duplicate} | {zh_dup} | {len(data['conflicts'])} | {len(errors)} |")
    lines += ["", "`_kaggle_upload/` chứa bản sao của `dataset/` cho hai manifest train; không coi đó là dữ liệu mới.", ""]

    lines += ["## 2. Phân bố domain/source", "", "| Tập | domain | source/provenance | số dòng |", "|---|---|---|---:|"]
    for name, (rows, _) in loaded.items():
        domains = Counter(str(r.get("domain", "<thiếu>")) for _, r in rows)
        sources = Counter(str(r.get("source_file", r.get("source", "<thiếu>"))) for _, r in rows)
        for domain, count in domains.most_common():
            source_text = ", ".join(f"{key}={value}" for key, value in sources.most_common(4)) if domain == domains.most_common(1)[0][0] else ""
            lines.append(f"| `{name}` | `{domain}` | {source_text} | {count} |")

    lines += ["", "## 3. Provenance và cách train thực tế", "", "- `dataset/train_gold_vnext.jsonl` có các trường `id`, `domain`, `status`, `zh`, `vi`; các dòng được trộn từ gold cũ, register và booster. Cần đối chiếu theo cặp ZH/VI, không chỉ theo `status`.", "- So sánh theo cặp với các file thành phần:"]
    if manifest:
        for source in ("approved_gold.jsonl", "dataset/register_gold.jsonl", "dataset/labeled_gold.jsonl", "dataset/booster.jsonl"):
            if source not in audits:
                continue
            source_pairs = audits[source]["pairs"]
            present = sum(manifest["pairs"][item] for item in source_pairs if item in manifest["pairs"])
            lines.append(f"  - `{source}`: {len(source_pairs)} cặp duy nhất; {present} lượt xuất hiện trong manifest (trước hệ số lặp).")
    train_code = (ROOT / "kaggle_train.py").read_text(encoding="utf-8")
    model = re.search(r'MODEL_ID\s*=\s*["\']([^"\']+)', train_code)
    lines += [f"- Script train dùng base model `{model.group(1) if model else 'không tìm thấy'}`; không thấy cơ chế resume checkpoint.", "- Mặc định `gold_repeat=5`; `load_extra_replay` xáo trộn seed 42, lọc register rồi lấy tối đa 20.000 dòng từ `train_v2.jsonl`; replay chính lấy từ dataset Hugging Face `DATASET_ID`, không nằm đầy đủ trong thư mục này.", "- `train_gold_vnext` không nên truyền nguyên trạng nếu chưa tách provenance và duyệt lại: booster tự sinh, register_gold được suy ra từ labeled/error cases, còn approved là nhãn nhập file.", ""]

    if manifest:
        near = near_pairs(loaded["dataset/train_gold_vnext.jsonl"][0])
        lines += ["## 4. Vấn đề dữ liệu và mẫu cụ thể", "", f"- Cặp ZH trùng nhưng VI khác trong manifest: **{len(manifest['conflicts'])}**.", f"- Cặp gần trùng (SequenceMatcher, ZH >= 0,92; mẫu giới hạn): **{len(near)}**."]
        for item in manifest["conflicts"][:5]:
            lines.append(f"  - `train_gold_vnext.jsonl:{item[2]}`: {fmt(item[0])} | {fmt(item[1])} | {item[3]}")
        for item in near[:5]:
            lines.append(f"  - `train_gold_vnext.jsonl:{item[2]}`: {fmt(item[1])} | {item[3]}")
        for flag, items in manifest["flags"].items():
            lines += ["", f"### {flag}: {len(items)}", ""]
            lines.extend(f"- {line}" for line in sample(items))

    lines += ["", "## 5. Phân loại hành động", "", "- **Giữ ứng viên:** chỉ các cặp có ZH/VI đầy đủ, không trùng cặp, provenance truy được và người duyệt xác nhận bản dịch; không suy ra từ `approved`.", "- **Cách ly trước train:** mọi dòng có artefact ký tự/dấu câu, thiếu trường, xung đột cùng ZH khác VI, author note/meta, hoặc duplicate do trộn manifest.", "- **Cần người duyệt:** các cờ xưng hô, tên Latin dính, tỷ lệ độ dài, chữ số và câu thiếu/thừa ngữ cảnh. Đây là danh sách kiểm tra, không phải phán quyết bản dịch sai.", "- **Bộ ứng viên đề xuất:** manifest dedup theo cặp ZH/VI; giữ riêng `approved_gold` đã xác minh provenance, `register_gold` sau khi người duyệt xác nhận từng dòng, và `booster` như bộ thí nghiệm riêng. Không tạo bản dịch mới trong kiểm toán này.", "", "## 6. Giới hạn", "", "Near-duplicate là heuristic stdlib trên manifest, không thay cho đọc ngữ cảnh. Regex xưng hô không phân biệt tuyệt đối lời thoại, ngôi kể hay chủ thể; các mẫu đã nêu phải được đọc lại trước quyết định."]
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(OUT)


if __name__ == "__main__":
    main()
