"""Cổng nghiệm thu CORPUS — thực thi `docs/DATA_CHUAN.md`.

Khác các cổng cũ (07-13) ở chỗ: những cổng đó chấm từng dòng do thầy viết, cổng này chấm
**cả một lô data** trước khi cho vào train, gồm cả các điều kiện về THÀNH PHẦN lô mà không
dòng đơn lẻ nào vi phạm được (tỉ lệ bản dịch người, độ phủ kiểu câu).

    python 14_gate_corpus.py <file.jsonl> [--out-dir DIR]
    python 14_gate_corpus.py <file.jsonl> --calibrate    # in phân vị để CHỌN ngưỡng
    python 14_gate_corpus.py --self-check

Định dạng vào: jsonl có `zh`, `vi`, tuỳ chọn `source` (tên corpus) và `human` (bool — bản dịch
người hay máy sinh), `chapter_id` (gom dòng theo chương để chấm nhất quán xưng hô).

LaBSE (cổng căn đúng) là **tuỳ chọn**: thiếu `sentence_transformers` thì bỏ qua cổng đó và nói
rõ trong báo cáo, không im lặng cho qua. Model ~1,8 GB nên chỉ chạy ở máy nhà, đừng đụng VPS.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

# ── Ngưỡng ────────────────────────────────────────────────────────────────────────────────
# CHƯA HIỆU CHỈNH. Mượn từ nghiên cứu (LaBSE ≥0,70) và ước từ mẫu nhỏ. Chạy --calibrate trên
# một lô đã biết là tốt rồi thay số ở đây TRƯỚC khi tin kết quả — bài học hachimi_rhythm_research.
LABSE_MIN = 0.70
LEN_RATIO = (2.0, 4.5)
MIN_ZH_FOR_RATIO = 20          # nguồn ngắn hơn thì tỉ lệ là nhiễu, không chấm
MAX_CONFLICT_CHAPTERS = 0.10   # ≤10% chương được phép xung đột xưng hô
MIN_HUMAN_SHARE = 0.20         # ≥20% dòng phải từ bản dịch người (mỏ neo chống model collapse)
MIN_TYPE_SHARE = 0.05          # không kiểu câu nào dưới 5%

HAN = re.compile(r"[一-鿿]")
ZH_PRONOUN = re.compile(r"[他她它]")
ZH_NOT_SUBJECT = re.compile(r"[他她它]们|其[他她它]")
ZH_QUOTED = re.compile(r"[“「『](.*?)[”」』]", re.S)
VI_QUOTED = re.compile(r"[“\"](.*?)[”\"]", re.S)
REPEAT = re.compile(r"(?i)\b([\wÀ-ỹ]+(?:\s+[\wÀ-ỹ]+){0,2})\s+\1\b")
GAME_TERM = re.compile(r"等级|技能|冷却|属性|经验|副本|装备|BOSS|CD")


# ── Kiểu câu (đa nhãn) ────────────────────────────────────────────────────────────────────
def sentence_types(zh: str) -> set[str]:
    """Nhãn kiểu câu. Đa nhãn vì một câu có thể vừa là thoại vừa có số."""
    narration = ZH_NOT_SUBJECT.sub("", ZH_QUOTED.sub("", zh))
    tags = set()
    if ZH_QUOTED.search(zh):
        tags.add("thoại")
    else:
        tags.add("lời kể")
    if re.match(r"^\s*[他她它](?!们)", zh):
        tags.add("chủ ngữ đại từ")
    elif narration.strip() and not ZH_PRONOUN.search(narration):
        # Không có đại từ nào trong lời kể → hoặc chủ ngữ là tên riêng, hoặc lược hẳn.
        tags.add("lược chủ ngữ" if re.match(r"^\s*[一-鿿]{1,2}[了着过]|^\s*(?:开口|低声|冷声|怒|笑|当即|随即|旋即)", zh)
                 else "chủ ngữ tên riêng")
    if zh.count("，") + zh.count("、") >= 3:
        tags.add("chuỗi phẩy dài")
    if re.search(r"[【\[]", zh):
        tags.add("độc thoại ngoặc vuông")
    if re.search(r"\d", zh) or GAME_TERM.search(zh):
        tags.add("số / thuật ngữ game")
    if len(ZH_QUOTED.findall(zh)) > 1:
        tags.add("nhiều lượt thoại")
    if len(zh) > 120:
        tags.add("câu dài")
    return tags


# ── Cổng theo DÒNG ────────────────────────────────────────────────────────────────────────
def row_reject(row: dict, seen: set[str]) -> str | None:
    zh, vi = (row.get("zh") or "").strip(), (row.get("vi") or "").strip()
    if not zh or not vi:
        return "thiếu zh hoặc vi"
    if zh in seen:
        return "trùng nguồn Trung"
    if HAN.search(vi):
        return "còn chữ Hán"
    # Câu nguồn quá ngắn thì tỉ lệ là nhiễu: "三十年河东三十年河西。" (11 chữ) ra bản dịch đúng
    # vẫn cho tỉ lệ 6,1. Chỉ chấm tỉ lệ khi nguồn đủ dài để con số có nghĩa.
    if len(zh) >= MIN_ZH_FOR_RATIO and not LEN_RATIO[0] <= len(vi) / len(zh) <= LEN_RATIO[1]:
        return "tỉ lệ dài bất thường (sót hoặc thêm thắt)"
    # Lặp CHỈ tính khi nguồn không lặp — "Ba mươi năm Hà Đông ba mươi năm Hà Tây" là điệp ngữ đúng.
    for group in REPEAT.findall(vi):
        if vi.lower().count(group.lower()) > _zh_repeat_budget(zh):
            return "lặp cụm không có gốc ở nguồn"
    labse = row.get("labse")
    if labse is not None and labse < LABSE_MIN:
        return f"căn lệch (LaBSE {labse:.2f})"
    return None


def _zh_repeat_budget(zh: str) -> int:
    """Nguồn lặp bao nhiêu thì đích được phép lặp bấy nhiêu."""
    best = 1
    for size in (2, 3, 4):
        for i in range(len(zh) - size + 1):
            best = max(best, zh.count(zh[i:i + size]))
    return best


# ── Cổng theo CHƯƠNG: nhất quán xưng hô ───────────────────────────────────────────────────
# Tiêu chí là MỘT nhân vật có bị gọi hai kiểu không — KHÔNG phải "có chứa từ hiện đại không".
# Sai lầm đó suýt làm vứt nhầm 80% một dataset tốt (31/07/2026).
GENDER_WORDS = {
    "nữ": (r"nàng", r"cô|cô ấy|cô ta"),
    "nam": (r"hắn", r"anh ta|ông ta|người đàn ông"),
}
MIN_SHARE_TO_COUNT = 0.2   # bên yếu phải ≥20% bên mạnh mới tính là xung đột thật, không phải lỡ tay


def chapter_conflicts(vi_lines: list[str]) -> list[str]:
    narration = VI_QUOTED.sub(" ", "\n".join(vi_lines))
    out = []
    for gender, (co_phong, hien_dai) in GENDER_WORDS.items():
        a = len(re.findall(r"(?i)(?<!\w)(?:" + co_phong + r")(?!\w)", narration))
        b = len(re.findall(r"(?i)(?<!\w)(?:" + hien_dai + r")(?!\w)", narration))
        if a and b and min(a, b) / max(a, b) >= MIN_SHARE_TO_COUNT:
            out.append(f"{gender} ({a} vs {b})")
    return out


# ── Chạy ──────────────────────────────────────────────────────────────────────────────────
def load(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def calibrate(rows: list[dict]) -> None:
    """In phân vị để CHỌN ngưỡng từ dữ liệu thật, thay vì bịa số."""
    def pct(values: list[float], p: float) -> float:
        values = sorted(values)
        return values[min(len(values) - 1, int(p * len(values)))] if values else 0.0

    ratios = [len(r["vi"]) / len(r["zh"]) for r in rows if r.get("zh") and r.get("vi")]
    print(f"{len(ratios)} dòng — tỉ lệ ký tự đích/nguồn:")
    for p in (0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99):
        print(f"   p{int(p * 100):02d} = {pct(ratios, p):.2f}")
    labse = [r["labse"] for r in rows if r.get("labse") is not None]
    if labse:
        print("LaBSE cosine:")
        for p in (0.01, 0.05, 0.25, 0.5):
            print(f"   p{int(p * 100):02d} = {pct(labse, p):.3f}")
    else:
        print("LaBSE: chưa chấm (chạy score_labse trước) → chưa hiệu chỉnh được cổng căn đúng")
    print("\n→ Đặt LEN_RATIO quanh [p01, p99], LABSE_MIN quanh p05 của lô ĐÃ BIẾT là tốt.")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", nargs="?", type=Path)
    ap.add_argument("--out-dir", type=Path)
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check or not args.input:
        self_check()
        return

    rows = load(args.input)
    if args.calibrate:
        calibrate(rows)
        return

    seen: set[str] = set()
    approved, rejects = [], []
    reasons: Counter[str] = Counter()
    for row in rows:
        reason = row_reject(row, seen)
        if reason:
            reasons[reason] += 1
            rejects.append({**row, "reject_reason": reason})
            continue
        seen.add(row["zh"].strip())
        approved.append(row)

    print(f"== Cổng theo dòng: đạt {len(approved)}/{len(rows)}")
    for reason, count in reasons.most_common():
        print(f"   loại {count:6d}: {reason}")
    if not any(r.get("labse") is not None for r in rows):
        print("   [!] CHƯA chấm LaBSE — cổng 'căn đúng' KHÔNG chạy. Kết quả chỉ là sàng thô.")

    # Cổng theo chương
    chapters: dict[str, list[str]] = defaultdict(list)
    for row in approved:
        chapters[str(row.get("chapter_id", "?"))].append(row["vi"])
    if len(chapters) > 1:
        bad = {cid: c for cid, lines in chapters.items() if (c := chapter_conflicts(lines))}
        share = len(bad) / len(chapters)
        ok = "ĐẠT" if share <= MAX_CONFLICT_CHAPTERS else "RỚT"
        print(f"\n== Nhất quán xưng hô: {len(bad)}/{len(chapters)} chương xung đột "
              f"({share:.0%}, trần {MAX_CONFLICT_CHAPTERS:.0%}) — {ok}")
        for cid, why in list(bad.items())[:5]:
            print(f"   chương {cid}: {', '.join(why)}")

    # Cổng theo lô
    human = sum(1 for r in approved if r.get("human"))
    share = human / max(1, len(approved))
    print(f"\n== Mỏ neo bản dịch người: {human}/{len(approved)} = {share:.0%} "
          f"(cần ≥{MIN_HUMAN_SHARE:.0%}) — {'ĐẠT' if share >= MIN_HUMAN_SHARE else 'RỚT'}")
    if not any("human" in r for r in approved):
        print("   [!] Không dòng nào có trường `human` — gắn nhãn nguồn trước, đừng đoán.")

    types: Counter[str] = Counter()
    for row in approved:
        types.update(sentence_types(row["zh"]))
    print(f"\n== Độ phủ kiểu câu (cần mỗi kiểu ≥{MIN_TYPE_SHARE:.0%}):")
    for tag, count in types.most_common():
        s = count / max(1, len(approved))
        print(f"   {'ok ' if s >= MIN_TYPE_SHARE else 'THIẾU'} {tag:24s} {count:6d}  {s:5.1%}")

    out_dir = args.out_dir or args.input.parent
    (out_dir / f"{args.input.stem}_approved.jsonl").write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in approved), encoding="utf-8")
    (out_dir / f"{args.input.stem}_rejects.jsonl").write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rejects), encoding="utf-8")
    print(f"\n→ {out_dir / (args.input.stem + '_approved.jsonl')}")
    print("\nCòn MỘT cổng không tự động hoá được: đọc tay 50 dòng. Đừng bỏ.")


def self_check() -> None:
    good = {"zh": "他握紧长枪，转身离去。", "vi": "Hắn nắm chặt trường thương, xoay người rời đi."}
    assert row_reject(good, set()) is None
    assert row_reject(good, {good["zh"]}) == "trùng nguồn Trung"
    assert row_reject({**good, "vi": "Hắn nắm chặt 长枪."}, set()) == "còn chữ Hán"
    # Undertranslation: chỉ chấm được khi nguồn đủ dài (≥20 chữ Hán).
    dai = {"zh": "他握紧手中的长枪，缓缓转身离去，山谷里的风卷着落叶扑面而来。",
           "vi": "Hắn nắm chặt trường thương, xoay người rời đi, gió cuốn lá vàng táp vào mặt."}
    assert row_reject(dai, set()) is None
    assert row_reject({**dai, "vi": "Hắn đi."}, set()) == "tỉ lệ dài bất thường (sót hoặc thêm thắt)"
    # Nguồn ngắn thì KHÔNG chấm tỉ lệ — tránh chặn nhầm như ca điệp ngữ bên dưới.
    assert row_reject({**good, "vi": "Hắn đi."}, set()) is None
    assert row_reject({**good, "labse": 0.4}, set()).startswith("căn lệch")
    # Điệp ngữ CÓ trong nguồn thì không phải lỗi lặp.
    diep = {"zh": "三十年河东三十年河西。", "vi": "Ba mươi năm Hà Đông ba mươi năm Hà Tây, chớ khinh thiếu niên nghèo!"}
    assert row_reject(diep, set()) is None, "điệp ngữ đúng bị chặn nhầm"
    lap = {"zh": "他很生气。", "vi": "Hắn rất tức giận rất tức giận, mặt đỏ bừng lên vì quá tức."}
    assert row_reject(lap, set()) == "lặp cụm không có gốc ở nguồn"

    # Nhất quán xưng hô: nam=hắn + nữ=cô là NHẤT QUÁN (hai nhân vật khác giới), không phải lỗi.
    assert chapter_conflicts(["Hắn nhìn cô.", "Hắn cười, cô quay đi.", "Cô im lặng."]) == []
    assert chapter_conflicts(["Nàng nhìn ra xa.", "Cô cúi đầu.", "Nàng thở dài.", "Cô khóc."])
    # Đại từ trong THOẠI không tính vào lời kể.
    assert chapter_conflicts(['Nàng nói: "Cô ta đi rồi." Nàng thở dài.']) == []

    assert "lược chủ ngữ" in sentence_types("开口说道：“好吧！”")
    assert "chủ ngữ đại từ" in sentence_types("他握紧长枪。")
    assert "thoại" in sentence_types("他说：“走吧。”")
    assert "chuỗi phẩy dài" in sentence_types("风起，云涌，天暗，雨落。")
    print("14_gate_corpus OK")


if __name__ == "__main__":
    main()
