"""Lắp corpus DOC-LEVEL cho bậc 2: trộn kaihe (người dịch) + tran-vi-teacher (in-domain).

Vì sao trộn (docs/DATA_CHUAN.md + đo 31/07):
- **kaihe** = mỏ neo NGƯỜI dịch (chống model collapse), nhưng thuật toán căn của họ theo tên
  riêng nên under-cover "lược chủ ngữ", và có chương ngôn tình anh/em.
- **tran-vi-teacher** = Gemini in-domain, đúng register hắn/nàng, phủ subject-drop tốt — nhưng
  là data máy (không được để một mình → collapse).
Trộn: teacher lo register + subject-drop, kaihe làm mỏ neo người + đa dạng.

Lọc mỗi CHƯƠNG trước khi dựng cặp:
1. số dòng zh==vi (bỏ chương lệch căn).
2. register "anh/em sến": bỏ chương mà anh/em (ngôi 1-2) LẤN ngươi trong thoại — user chốt
   31/07: hắn/cô OK, ta-ngươi tốt, anh/em sến không hợp văn viết.
3. nhất quán giọng theo giới (một nhân vật không bị gọi hai kiểu).
Rồi dựng cặp doc-level `ctx ⟨SEP⟩ câu → dịch câu`, lọc từng dòng (Hán sót/tỉ lệ/lặp),
gắn nhãn {source, human}. Trộn với trần để giữ tỉ lệ người ≥ --min-human.

    python 17_build_doclevel_corpus.py            # dựng ra data/doclevel_corpus.jsonl
    python 17_build_doclevel_corpus.py --self-check

Cần: data/kaihe/aligned_chapters.jsonl và data/tran_vi_teacher.jsonl đã tải (gated, dùng HF_TOKEN).
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import random
import re
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data"
KAIHE = DATA / "kaihe" / "aligned_chapters.jsonl"
TEACHER = DATA / "tran_vi_teacher.jsonl"
OUT = DATA / "doclevel_corpus.jsonl"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parent / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_m16 = _load("16_make_doclevel")
_m14 = _load("14_gate_corpus")
SEP = _m16.DEFAULT_SEP

_Q = re.compile(r"[“「『\"](.*?)[”」』\"]", re.S)
# "anh"/"em" làm xưng hô ngôi 1-2 (sến). Đếm TOÀN VĂN (cả lời kể) — user chốt lỗi sến nằm ở
# "văn viết", không riêng thoại. So với hệ ta-ngươi: nếu anh/em lấn át thì đó là register hỏng.
_ANH_EM = re.compile(r"(?i)(?<!\w)(?:anh|em)(?!\w)")
_TA_NGUOI = re.compile(r"(?i)(?<!\w)(?:ta|ngươi)(?!\w)")
# Đại từ hiện đại CẤM ở CẤP DÒNG (đọc tay 31/07 thấy teacher lọt "Tôi" trong thoại — đúng lỗi
# 524 đang chống). KHÔNG gồm "mình/bạn/cháu": "của mình" là phản thân hợp lệ, lọc sẽ giết oan.
_MOD_LINE = re.compile(r"(?i)(?<!\w)(?:tôi|cậu|anh ta|cô ta|cô ấy|ông ta|bà ta)(?!\w)")


def _register_ok(vi_lines: list[str]) -> bool:
    """Bỏ chương ngôn tình anh/em: anh/em (ngôi 1-2) lấn át ta-ngươi trên toàn văn."""
    text = "\n".join(vi_lines)
    anh_em = len(_ANH_EM.findall(text))
    ta_nguoi = len(_TA_NGUOI.findall(text))
    return anh_em <= max(3, ta_nguoi)  # lác đác thì cho qua; lấn át ta-ngươi thì loại


def chapter_pairs(zh: list[str], vi: list[str], *, human: bool, source: str, ctx: int) -> list[dict]:
    zh = [x.strip() for x in zh]
    vi = [x.strip() for x in vi]
    if len(zh) != len(vi) or not any(zh):
        return []
    if not _register_ok(vi):
        return []
    if _m14.chapter_conflicts(vi):  # lệch giọng theo giới
        return []
    out = []
    for p in _m16.doclevel_pairs(zh, vi, ctx=ctx, sep=SEP):
        cur = p["zh"].rsplit(SEP, 1)[-1] if p["ctx_len"] else p["zh"]
        if _m14.row_reject({"zh": cur, "vi": p["vi"]}, set()):  # Hán sót/tỉ lệ/lặp trên DÒNG hiện tại
            continue
        if _MOD_LINE.search(p["vi"]):  # đại từ hiện đại: đúng lỗi đang chống, đừng dạy lại
            continue
        out.append({**p, "human": human, "source": source})
    return out


def iter_kaihe(ctx: int):
    for ln in KAIHE.read_text(encoding="utf-8").splitlines():
        if ln.strip():
            r = json.loads(ln)
            yield from chapter_pairs(r["zh_lines"], r["vi_lines"], human=True, source="kaihe", ctx=ctx)


def iter_teacher(ctx: int):
    with TEACHER.open(encoding="utf-8") as f:
        for ln in f:
            if not ln.strip():
                continue
            r = json.loads(ln)
            zh = (r.get("source_zh") or r.get("source") or "").split("\n")
            vi = (r.get("target_vi") or r.get("target") or "").split("\n")
            yield from chapter_pairs(zh, vi, human=False, source="teacher", ctx=ctx)


def main(argv=None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ctx", type=int, default=2)
    ap.add_argument("--min-human", type=float, default=0.30, help="tỉ lệ dòng người tối thiểu")
    ap.add_argument("--cap", type=int, default=600_000, help="trần tổng số cặp")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
        return

    kaihe = list(iter_kaihe(args.ctx))
    teacher = list(iter_teacher(args.ctx))
    print(f"kaihe: {len(kaihe):,} cặp qua lọc · teacher: {len(teacher):,} cặp qua lọc")

    # Giữ tỉ lệ người ≥ min-human trong trần cap.
    rnd = random.Random(20260731)
    rnd.shuffle(kaihe); rnd.shuffle(teacher)
    n_human = min(len(kaihe), args.cap)
    n_mach = min(len(teacher), int(n_human * (1 - args.min_human) / args.min_human))
    total = n_human + n_mach
    if total > args.cap:  # co lại giữ tỉ lệ
        n_human = int(args.cap * args.min_human) if len(kaihe) >= args.cap * args.min_human else len(kaihe)
        n_mach = args.cap - n_human
    mix = kaihe[:n_human] + teacher[:n_mach]
    rnd.shuffle(mix)
    OUT.write_text("".join(json.dumps(p, ensure_ascii=False) + "\n" for p in mix), encoding="utf-8")

    h = sum(1 for p in mix if p["human"])
    ctx_share = sum(1 for p in mix if p["ctx_len"]) / max(1, len(mix))
    print(f"\nTRỘN: {len(mix):,} cặp · người {h:,} ({h/len(mix):.0%}) · có ngữ cảnh {ctx_share:.0%}")
    print(f"→ {OUT}")
    print("Bước sau: đọc tay 50 dòng (docs/DATA_CHUAN mục 4), rồi train từ base teacher-v4.")


def _self_check() -> None:
    # register: chương anh/em sến bị bỏ
    assert not _register_ok(['Nàng nói: "Anh yêu em không?" Em hỏi anh, anh nhìn em.'])
    assert _register_ok(['Hắn nói: "Ngươi đi đi." Nàng gật đầu.'])
    # chapter_pairs: chương sạch ra cặp có nhãn
    zh = ["他走进房间。", "开口说道：“你来了。”"]
    vi = ["Hắn bước vào phòng.", "Mở miệng nói: “Ngươi đến rồi.”"]
    ps = chapter_pairs(zh, vi, human=True, source="kaihe", ctx=2)
    assert len(ps) == 2 and ps[1]["source"] == "kaihe" and ps[1]["human"] is True
    # dòng có đại từ hiện đại bị bỏ, "của mình" thì giữ
    assert chapter_pairs(["他来了。", "我说。"], ["Hắn tới rồi.", "Tôi nói."],
                         human=False, source="teacher", ctx=1) == \
        [{"zh": "他来了。", "vi": "Hắn tới rồi.", "ctx_len": 0, "human": False, "source": "teacher"}]
    assert len(chapter_pairs(["他握剑。", "他护住自己。"], ["Hắn cầm kiếm.", "Hắn bảo vệ chính mình."],
                             human=False, source="teacher", ctx=1)) == 2
    assert ps[1]["zh"].endswith("开口说道：“你来了。”") and SEP in ps[1]["zh"]
    # chương lệch số dòng → rỗng
    assert chapter_pairs(["a", "b"], ["x"], human=False, source="teacher", ctx=2) == []
    print("17_build_doclevel_corpus OK")


if __name__ == "__main__":
    main()
