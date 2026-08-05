"""Probe: novel_ner_v2 (chi-vi) có thay được bước trích tên bằng LLM không?

Trích tên hiện tại chạy LLM nền (_extract_names_bg trong worker.py): 38-79s/call, đôi khi
hỏng, token không vào sổ. Ý tưởng: NER LOCAL phát hiện cụm tên trong text zh, rồi phiên âm
bằng hanviet.han_viet (deterministic) — bỏ hẳn LLM cho việc này.

Đây là PROBE, không phải bản thay: nó cho thấy NER bắt được những tên nào, nhanh cỡ nào,
ăn bao nhiêu RAM — để quyết có đáng làm thật không. Đọc tay output là bước nghiệm thu.

Chạy:  python -m hachimi.eval.probe_ner_names <file_chuong_zh.txt>
  (file: 1 chương text tiếng Trung; hoặc để trống dùng đoạn mẫu thủ công)

Cần: pip install "transformers>=4.40" torch  (nặng ~vài trăm MB — cân nhắc RAM VPS 2GB!)
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

MODEL_ID = "chi-vi/novel_ner_v2"  # token classification, ~0.3B — GPL-3.0
SAMPLE = (
    "叶凡握紧手中长剑，转身望向林婉儿。“青云宗的人来了。”他低声道。"
    "远处，赵德海带着几名弟子快步走来，身后是玄天剑派的旗帜。"
)


def _load_pipeline():
    try:
        from transformers import pipeline
    except ImportError:
        sys.exit("Thiếu deps: pip install \"transformers>=4.40\" torch")
    # aggregation_strategy=simple: gộp sub-token thành cụm tên hoàn chỉnh
    return pipeline("token-classification", model=MODEL_ID, aggregation_strategy="simple")


def main() -> None:
    text = Path(sys.argv[1]).read_text(encoding="utf-8") if len(sys.argv) > 1 else SAMPLE

    print(f"Tải {MODEL_ID} …")
    t0 = time.time()
    ner = _load_pipeline()
    print(f"  nạp model: {time.time() - t0:.1f}s")

    t0 = time.time()
    ents = ner(text)
    dt = time.time() - t0

    # phiên âm Hán-Việt cho từng cụm bắt được (dùng chính hàm production)
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from novelworker.translator import hanviet  # noqa: E402

    seen: dict[str, str] = {}
    for e in ents:
        zh = e["word"].replace(" ", "")
        if zh and zh not in seen:
            seen[zh] = f'{hanviet.han_viet(zh)}  [{e.get("entity_group", "?")}, {e["score"]:.2f}]'

    print(f"\n{len(text)} ký tự · NER {dt:.2f}s · {len(seen)} cụm tên/thuật ngữ:\n")
    for zh, hv in seen.items():
        print(f"  {zh:<12} → {hv}")
    print(
        "\nSo với baseline: 1 call LLM trích tên đo trên VPS tốn 38-79s (memory llm-latency-vps)."
        "\nNghiệm thu TAY: cụm nào KHÔNG phải tên riêng (bắt nhầm)? tên nào SÓT? phiên âm sai?"
    )


if __name__ == "__main__":
    main()
