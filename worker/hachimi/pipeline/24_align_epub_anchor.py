"""Căn câu zh ↔ bản dịch TAY (epub) để dựng mỏ neo người dịch — nguồn thứ hai sau kaihe.

Vì sao cần: kaihe chỉ có 90 bộ truyện, mà trục quyết định là ĐA DẠNG chứ không phải lượng
(DATA_CHUAN.md trục 2). Kho epub cho ~2.300 bản dịch tay của ~2.300 dịch giả khác nhau, nên
lấy ÍT chương từ NHIỀU truyện mới đúng, đừng cày sâu vài truyện.

CHẠY Ở ĐÂU: box production (cần model Hachimi + chương Trung trong R2). Đầu vào là
`clean_testset.jsonl` dựng bởi bước ghép epub×DB; đầu ra còn phải qua cổng chương/dòng
(xem cuối file) và **phải chấm lại bằng LaBSE** trước khi train (DATA_CHUAN.md mục 1).

Cách: Hachimi dịch từng câu Trung ra bản MÁY, rồi căn bản máy với bản người bằng quy hoạch
động trên độ tương đồng chữ. Dùng chính Hachimi làm cầu thì không phải nuôi thêm encoder
đa ngữ 471M trên box (LaBSE để dành chấm lại ở máy nhà, xem pipeline/15_score_labse.py).

Ra: {zh, vi, score} — vi là câu của NGƯỜI, không phải của máy.
"""
from __future__ import annotations
import json, re, sys, time, unicodedata
from difflib import SequenceMatcher
from pathlib import Path
import ctranslate2, sentencepiece as spm

# Chạy được cả trên box (mount /bench, /prod) lẫn máy dev — nơi có 8 nhân AVX512 nên
# align nhanh hơn nhiều. Trỏ đường dẫn bằng biến môi trường.
import os
HERE = Path(os.environ.get("ANCHOR_DATA", "/bench"))
MODEL_DIR = os.environ.get("HACHIMI_DIR", "/prod")
EOS = "</s>"
ZH_SENT = re.compile(r"[^。！？!?…]*[。！？!?…]+|[^。！？!?…]+")
VI_SENT = re.compile(r"[^.!?…]*[.!?…]+|[^.!?…]+")
# Hai câu tiếng Việt BẤT KỲ đã tương đồng ~0,30 (cùng hư từ) — phải trừ nền đó đi, nếu
# không thuật toán ghép bừa và trôi hàng (đo 29/08: ngưỡng 0,34 cho ra 100% cặp sai).
BASE = 0.30
MIN_SCORE = 0.50      # sim thô tối thiểu để nhận một cặp
SKIP_COST = 0.04      # bỏ một câu rẻ hơn ghép sai — thà mất data còn hơn data bẩn
BAND = 12             # dải lệch cho phép giữa hai chỉ số (người dịch gộp/tách nhiều)


def norm(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    return re.sub(r"[^a-z0-9 ]", " ", "".join(c for c in s if not unicodedata.combining(c)))


def _grams(s: str) -> set[str]:
    t = norm(s).replace(" ", "")
    return {t[i:i + 3] for i in range(len(t) - 2)}


def sim(a: str, b: str) -> float:
    """Jaccard trên 3-gram ký tự: ổn định hơn SequenceMatcher khi hai câu lệch độ dài."""
    ga, gb = _grams(a), _grams(b)
    if not ga or not gb:
        return 0.0
    return len(ga & gb) / len(ga | gb)


def split_zh(text: str) -> list[str]:
    return [m.group(0).strip() for line in text.split("\n") if line.strip()
            for m in ZH_SENT.finditer(line) if m.group(0).strip()]


def split_vi(text: str) -> list[str]:
    return [m.group(0).strip() for line in text.split("\n") if line.strip()
            for m in VI_SENT.finditer(line) if len(m.group(0).strip()) > 1]


def align(mt: list[str], human: list[str]) -> list[tuple[int, int, float]]:
    """Quy hoạch động monotonic: cho phép 1-1, 1-2, 2-1. Trả (i_mt, j_human, điểm)."""
    n, m = len(mt), len(human)
    NEG = -1e9
    dp = [[NEG] * (m + 1) for _ in range(n + 1)]
    back = [[None] * (m + 1) for _ in range(n + 1)]
    dp[0][0] = 0.0
    for i in range(n + 1):
        for j in range(m + 1):
            if dp[i][j] == NEG or abs(i * m - j * n) > BAND * max(n, m):
                continue
            for di, dj in ((1, 1), (1, 2), (2, 1), (1, 0), (0, 1)):
                ni, nj = i + di, j + dj
                if ni > n or nj > m:
                    continue
                if di == 0 or dj == 0:
                    gain = -SKIP_COST
                else:
                    raw = sim(" ".join(mt[i:ni]), " ".join(human[j:nj]))
                    gain = (raw - BASE) if raw >= MIN_SCORE else -SKIP_COST * 2
                if dp[i][j] + gain > dp[ni][nj]:
                    dp[ni][nj] = dp[i][j] + gain
                    back[ni][nj] = (i, j, gain)
    i, j, out = n, m, []
    while (i, j) != (0, 0):
        step = back[i][j]
        if step is None:
            break
        pi, pj, gain = step
        if pi < i and pj < j and gain > 0:
            out.append((slice(pi, i), slice(pj, j), gain + BASE))
        i, j = pi, pj
    return out[::-1]


def gate(rows: list[dict]) -> list[dict]:
    """Cổng chất lượng: nhất quán xưng hô cấp CHƯƠNG + `_replay_ok` cấp DÒNG.

    Dùng lại nguyên cổng của kaihe (pipeline/19 + kaggle_train) để shard epub khớp hệt các
    shard khác — đừng chế cổng riêng. Đo 29/08: 1.225 cặp căn -> 637 cặp qua cổng (52%).
    """
    import importlib.util
    here = Path(__file__).resolve().parent
    sys.path.insert(0, str(here))
    from kaggle_train import _replay_ok
    spec = importlib.util.spec_from_file_location("anchor", here / "19_build_anchor_kaihe.py")
    anchor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(anchor)
    by_ch: dict[tuple, list[dict]] = {}
    for r in rows:
        by_ch.setdefault((r["novel_id"], r["chapter_index"]), []).append(r)
    kept = []
    for group in by_ch.values():
        if anchor.chapter_rejected([g["vi"] for g in group]):
            continue
        kept += [g for g in group if _replay_ok(g["zh"], g["vi"])]
    return kept


def pair_ok(mt_chapter: str, human: str) -> float:
    """Cặp chương có THẬT SỰ cùng nội dung không — epub đánh số lệch DB nên phải kiểm.

    Đo 29/08 trên 82 cặp: trung vị chrF 57, cặp <40 là lệch chương thật. Align cặp lệch vào
    thì thuật toán vẫn cho ra "kết quả" điểm đẹp mà nội dung sai hoàn toàn.
    """
    import sacrebleu
    return sacrebleu.sentence_chrf(mt_chapter, [human]).score


def main() -> None:
    n_ch = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    model = sys.argv[2] if len(sys.argv) > 2 else MODEL_DIR
    src_name = os.environ.get("ANCHOR_INPUT", "clean_testset.jsonl")
    rows = [json.loads(l) for l in (HERE / src_name).open(encoding="utf-8")][:n_ch]
    src, tgt = spm.SentencePieceProcessor(), spm.SentencePieceProcessor()
    src.load(f"{model}/source.spm"); tgt.load(f"{model}/target.spm")
    tr = ctranslate2.Translator(model, device="cpu", compute_type="int8", intra_threads=4)
    out, t0 = [], time.time()
    tot_zh = kept = n_lech = 0
    for r in rows:
        zh = split_zh(r["zh"])
        human = split_vi(r["vi_human"])
        if not zh or not human:
            continue
        res = tr.translate_batch([src.encode(s, out_type=str)[:110] + [EOS] for s in zh],
                                 beam_size=2, max_decoding_length=256, max_batch_size=16)
        mt = [tgt.decode([t for t in x.hypotheses[0] if t != EOS]) for x in res]
        if pair_ok(" ".join(mt), r["vi_human"]) < 50:
            n_lech += 1
            continue
        tot_zh += len(zh)
        for si, sj, score in align(mt, human):
            if score >= MIN_SCORE:  # gain đã cộng lại BASE ở align()
                out.append({"zh": " ".join(zh[si]), "vi": " ".join(human[sj]),
                            "score": round(score, 3), "novel_id": r["novel_id"],
                            "chapter_index": r["chapter_index"]})
                kept += len(zh[si])
    dt = time.time() - t0
    (HERE / "epub_anchor_raw.jsonl").write_text(
        "\n".join(json.dumps(o, ensure_ascii=False) for o in out), encoding="utf-8")
    print(f"{len(rows)} chương vào · bỏ {n_lech} cặp LỆCH (chrF<50) · {tot_zh} câu Trung · "
          f"căn được {kept} câu ({kept/max(1,tot_zh):.0%}) → {len(out)} cặp · {dt:.0f}s")
    for o in out[:5]:
        print(f"\n  [{o['score']}] ZH: {o['zh'][:90]}")
        print(f"          VI: {o['vi'][:110]}")


main()
