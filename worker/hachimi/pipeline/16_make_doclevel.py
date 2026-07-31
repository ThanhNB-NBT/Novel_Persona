"""Dựng cặp train DOC-LEVEL cho bậc 2 — cho model THẤY ngữ cảnh để hết bịa chủ ngữ.

Vấn đề đã đo (docs/PLAN_CHAT_LUONG..., mục 2.7-2.8): model dịch TỪNG DÒNG nên khi nguồn lược
chủ ngữ (开口说道：) nó tự bịa "Hắn/Nàng" rồi đoán giới bừa. 27/104 ca cả 6 beam đều bịa —
n-best không cứu được, chỉ ngữ cảnh mới cứu. Cách chuẩn nhất mà KHÔNG đổi kiến trúc (max_pos
512 đủ chỗ): nhét 1-2 dòng nguồn phía trước làm ngữ cảnh.

Định dạng (concat "context-as-input, translate-current-only"):
    source = ctx_zh_1 ⟨SEP⟩ ... ⟨SEP⟩ ctx_zh_k ⟨SEP⟩ cur_zh
    target = cur_vi                          (CHỈ dịch dòng hiện tại)

Model học "cho ngữ cảnh này, dịch câu CUỐI". Lúc chạy cũng ghép y hệt rồi lấy nguyên output —
không phải căn xem câu nào là câu hiện tại. Ngữ cảnh dùng nguồn TRUNG, không phải bản dịch, để
tránh dồn lỗi dịch sai của dòng trước.

    python 16_make_doclevel.py <chuong_aligned.jsonl> <ra.jsonl> [--ctx 2] [--sep "⟪ctx⟫"]
    python 16_make_doclevel.py --self-check

Vào: jsonl, mỗi dòng một CHƯƠNG dạng {"zh": "dòng\\ndòng...", "vi": "..."} (số dòng khớp),
HOẶC {"zh_lines": [...], "vi_lines": [...]}. Ra: jsonl cặp {zh, vi, ctx_len} sẵn cho kaggle_train.

Lưu ý tokenizer: SEP là chuỗi thường, SentencePiece sẽ học nó trong lúc train — KHÔNG cần thêm
special token / mổ vocab. Nhưng phải train MỚI trên định dạng này; ném thẳng vào model cũ vô ích.
Giữ SEP cố định giữa data train và code chạy (hachimi_engine), lệch một ký tự là hỏng.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

DEFAULT_SEP = "⟪ctx⟫"   # ⟪ctx⟫ — hiếm, khó trùng nội dung nguồn
DEFAULT_CTX = 2


def chapter_lines(row: dict) -> tuple[list[str], list[str]] | None:
    if "zh_lines" in row and "vi_lines" in row:
        zh, vi = row["zh_lines"], row["vi_lines"]
    else:
        zh = (row.get("zh") or "").split("\n")
        vi = (row.get("vi") or "").split("\n")
    zh = [l.strip() for l in zh]
    vi = [l.strip() for l in vi]
    if len(zh) != len(vi):
        return None
    return zh, vi


def doclevel_pairs(zh: list[str], vi: list[str], ctx: int, sep: str) -> list[dict]:
    """Mỗi dòng có nội dung → một cặp train, ghép tối đa `ctx` dòng nguồn phía trước làm ngữ cảnh."""
    out: list[dict] = []
    for i, (zh_cur, vi_cur) in enumerate(zip(zh, vi)):
        if not zh_cur or not vi_cur:
            continue
        prev = [zh[j] for j in range(max(0, i - ctx), i) if zh[j]]
        source = (sep.join([*prev, zh_cur]) if prev else zh_cur)
        out.append({"zh": source, "vi": vi_cur, "ctx_len": len(prev)})
    return out


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", nargs="?", type=Path)
    ap.add_argument("output", nargs="?", type=Path)
    ap.add_argument("--ctx", type=int, default=DEFAULT_CTX)
    ap.add_argument("--sep", default=DEFAULT_SEP)
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check or not args.input:
        _self_check()
        return

    rows = [json.loads(l) for l in args.input.read_text(encoding="utf-8").splitlines() if l.strip()]
    pairs: list[dict] = []
    skipped = 0
    for row in rows:
        lines = chapter_lines(row)
        if lines is None:
            skipped += 1
            continue
        pairs.extend(doclevel_pairs(*lines, ctx=args.ctx, sep=args.sep))
    args.output.write_text(
        "".join(json.dumps(p, ensure_ascii=False) + "\n" for p in pairs), encoding="utf-8")
    with_ctx = sum(1 for p in pairs if p["ctx_len"])
    print(f"{len(rows)} chương ({skipped} bỏ vì lệch số dòng) → {len(pairs)} cặp")
    print(f"  có ngữ cảnh: {with_ctx} ({with_ctx / max(1, len(pairs)):.0%}) · SEP={args.sep!r} ctx={args.ctx}")
    print(f"→ {args.output}")


def _self_check() -> None:
    zh = ["他走进房间。", "开口说道：“你来了。”", "转身离去。"]
    vi = ["Hắn bước vào phòng.", "Mở miệng nói: “Ngươi đến rồi.”", "Xoay người rời đi."]
    pairs = doclevel_pairs(zh, vi, ctx=2, sep="|")
    assert len(pairs) == 3
    # Dòng đầu không có ngữ cảnh.
    assert pairs[0] == {"zh": "他走进房间。", "vi": "Hắn bước vào phòng.", "ctx_len": 0}
    # Dòng 2 (lược chủ ngữ) được ghép 1 dòng ngữ cảnh phía trước.
    assert pairs[1]["zh"] == "他走进房间。|开口说道：“你来了。”"
    assert pairs[1]["vi"] == "Mở miệng nói: “Ngươi đến rồi.”" and pairs[1]["ctx_len"] == 1
    # Dòng 3 ghép tối đa 2 dòng trước.
    assert pairs[2]["zh"] == "他走进房间。|开口说道：“你来了。”|转身离去。"
    assert pairs[2]["ctx_len"] == 2
    # Dòng rỗng bị bỏ, không tính làm ngữ cảnh.
    p2 = doclevel_pairs(["", "开口道。"], ["", "Mở miệng."], ctx=2, sep="|")
    assert len(p2) == 1 and p2[0]["ctx_len"] == 0
    # Chương lệch số dòng → None.
    assert chapter_lines({"zh": "a\nb", "vi": "x"}) is None
    print("16_make_doclevel OK")


if __name__ == "__main__":
    main()
