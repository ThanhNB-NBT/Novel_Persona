"""Lọc kaihe (bản dịch NGƯỜI, căn theo chương) thành mỏ neo câu-level cho vòng train v5.

Vì sao: teacher-v4 là 100% data máy-sinh → đúng kịch bản model collapse (DATA_CHUAN trục 1).
kaihe là bản dịch người, căn theo chương → mỏ neo chống sụp. Nhưng gu dự án CẤM giọng
"anh/em" sến trong văn kể, và lo nhất là LỘN XỘN giọng (một nhân vật gọi hai kiểu). Nên lọc
theo đúng cổng DATA_CHUAN mục 4:
  - cổng 4  (nhất quán xưng hô): loại CHƯƠNG có một nhân vật bị gọi hai kiểu (nàng vs cô ta/ấy,
             hắn vs anh ta) — KHÔNG phải "cấm từ".
  - cổng 4b (anh/em sến): loại chương ngôn tình đầy "anh/em" ngôi 1-2 trong lời kể.

Các cổng register/Hán/ratio/số/lặp cấp DÒNG để `kaggle_train._replay_ok` (nhánh --extra-replay)
lo — tránh trùng cổng và tránh quyết định "mình" hai nơi. Đây CHỈ thêm cái extra-replay thiếu:
tính nhất quán cấp chương + tách câu.

Chạy:  python -m pipeline.19_build_anchor_kaihe   (từ worker/hachimi/)
Ra:    data/kaihe_anchor.jsonl  ({zh, vi}) + in số rơi từng cổng + 20 mẫu đọc tay.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from text_clean import clean_source  # noqa: E402
# Dùng LẠI chính cổng của kaggle_train để shard kaihe khớp hệt các replay shard khác
# (register cấm modern, Hán sạch, ngoặc cân, ratio, số khớp) — tránh chế cổng lệch.
from kaggle_train import _replay_ok  # noqa: E402

HERE = Path(__file__).resolve().parents[1]
SRC = HERE / "data" / "kaihe" / "aligned_chapters.jsonl"
OUT = HERE / "data" / "kaihe_anchor.jsonl"

_QUOTED = re.compile(r"[“「『\"](.*?)[”」』\"]", re.S)  # bỏ thoại → còn lời kể
# Xung đột giới: một nhân vật gọi hai kiểu trong LỜI KỂ của cùng chương.
_NANG = re.compile(r"(?i)(?<!\w)nàng(?!\w)")
_CO_TA = re.compile(r"(?i)(?<!\w)cô (?:ta|ấy)(?!\w)")
_HAN_PRON = re.compile(r"(?i)(?<!\w)hắn(?!\w)")
_ANH_TA = re.compile(r"(?i)(?<!\w)anh (?:ta|ấy)(?!\w)")
# "anh/em" làm đại từ sến ngôi 1-2, KHÔNG phải danh từ thân tộc (anh trai/em gái) hay "anh ấy".
_SEN = re.compile(r"(?i)(?<!\w)(?:anh|em)(?!\w)(?!\s*(?:trai|gái|ấy|họ|ta\b))")
SEN_MAX = 3  # >3 lượt sến/chương = ngôn tình, loại


def _narration(vi_lines: list[str]) -> str:
    return _QUOTED.sub("", "\n".join(vi_lines))


def chapter_rejected(vi_lines: list[str]) -> str | None:
    """Trả lý do loại chương (None = giữ). Xét trên LỜI KỂ, không xét thoại."""
    narr = _narration(vi_lines)
    if _NANG.search(narr) and _CO_TA.search(narr):
        return "conflict_female"
    if _HAN_PRON.search(narr) and _ANH_TA.search(narr):
        return "conflict_male"
    if len(_SEN.findall(narr)) > SEN_MAX:
        return "sen_anh_em"
    return None


def build() -> dict:
    stats = {"chapters": 0, "aligned": 0, "conflict_female": 0, "conflict_male": 0,
             "sen_anh_em": 0, "kept_chapters": 0, "line_pairs": 0, "gate_replay": 0, "dup": 0}
    seen: set[str] = set()
    samples: list[tuple[str, str]] = []
    ch_no = 0
    with open(SRC, encoding="utf-8", errors="surrogatepass") as fin, \
            open(OUT, "w", encoding="utf-8") as fout:
        for line in fin:
            if not line.strip():
                continue
            stats["chapters"] += 1
            try:
                d = json.loads(line)
            except Exception:
                continue
            zl, vl = d.get("zh_lines") or [], d.get("vi_lines") or []
            if len(zl) != len(vl) or not zl:
                continue  # chỉ dùng chương khớp dòng
            stats["aligned"] += 1
            reason = chapter_rejected(vl)
            if reason:
                stats[reason] += 1
                continue
            stats["kept_chapters"] += 1
            ch_no += 1
            for zh_raw, vi_raw in zip(zl, vl):
                zh, vi = clean_source(str(zh_raw)), str(vi_raw).strip()
                if not zh or not vi:
                    continue
                if not _replay_ok(zh, vi):   # cùng cổng với mọi replay shard khác
                    stats["gate_replay"] += 1
                    continue
                if zh in seen:               # 1 vi / zh → không xung đột cùng nguồn khi load
                    stats["dup"] += 1
                    continue
                seen.add(zh)
                fout.write(json.dumps(
                    {"zh": zh, "vi": vi, "status": "approved_replay", "source": "kaihe_anchor",
                     "novel_id": None, "chapter_index": ch_no}, ensure_ascii=True) + "\n")
                stats["line_pairs"] += 1
                if len(samples) < 20 and stats["line_pairs"] % 1499 == 0:
                    samples.append((zh, vi))
    stats["_samples"] = samples
    return stats


def main() -> None:
    s = build()
    samples = s.pop("_samples")
    print(json.dumps(s, ensure_ascii=True, indent=2))
    print(f"\n=> {OUT}  ({s['line_pairs']} cap dong tu {s['kept_chapters']} chuong)\n")
    print("--- 20 MAU (doc tay: register co hop van ke co trang / nhat quan xung ho?) ---")
    for zh, vi in samples:
        # in an toan tren console cp1252
        print("ZH:", zh.encode("ascii", "backslashreplace").decode())
        print("VI:", vi.encode("ascii", "backslashreplace").decode(), "\n")


def _self_check() -> None:
    # xung đột giới trong lời kể → loại
    assert chapter_rejected(["Nàng cười.", "Cô ta quay đi."]) == "conflict_female"
    assert chapter_rejected(["Hắn gật đầu.", "Anh ta bỏ đi."]) == "conflict_male"
    # thoại có "cô ấy" KHÔNG tính (chỉ xét lời kể)
    assert chapter_rejected(["Nàng nói: “Cô ấy đâu rồi?”"]) is None
    # sến anh/em nhiều → loại; thân tộc "anh trai"/"em gái" KHÔNG tính
    assert chapter_rejected(["Anh đi đi.", "Em ở lại.", "Anh nhớ em.", "Em thương anh."]) == "sen_anh_em"
    assert chapter_rejected(["Anh trai nàng tới.", "Em gái hắn khóc."]) is None
    print("selfcheck OK")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        _self_check()
    else:
        main()
