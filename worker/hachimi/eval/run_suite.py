"""Cổng vào duy nhất của bộ đánh giá Hachimi.

Trước đây `eval/` có 26 script rời, mỗi lần đo phải nhớ chạy cái nào theo thứ tự nào,
và manifest thì còn trỏ đường dẫn Windows của cây thư mục đã bị gom lại từ 25/07.
File này gom phần *luôn phải chạy* lại thành một lệnh.

Hai tầng, tách nhau vì tầng dưới chạy được ở mọi nơi còn tầng trên thì không:

  check   Toàn vẹn 3 tập eval khoá + quét rò rỉ train/eval + soi môi trường.
          CHỈ dùng thư viện chuẩn — chạy được ngay cả khi chưa cài gì.
  score   Đo một model CT2 trên tập khoá. Cần ctranslate2 + transformers.

Chạy:
    cd worker && PYTHONPATH=. python3 hachimi/eval/run_suite.py check
    cd worker && PYTHONPATH=. python3 hachimi/eval/run_suite.py check --update-manifest
    cd worker && PYTHONPATH=. python3 hachimi/eval/run_suite.py score models/hachimi-ct2

`check` trả về mã thoát khác 0 khi có gì đó thật sự sai (thiếu file, rò rỉ, sha lệch)
nên gọi được từ CI hoặc từ hook.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

HUB = Path(__file__).resolve().parents[1]
EVAL_LOCKED = HUB / "data" / "eval_locked"
MANIFEST = Path(__file__).resolve().parent / "hachimi_eval_suite_manifest.json"

# Tập khoá: tên -> (file, khoá chứa bản tham chiếu)
LOCKED = {
    "reference_60": (EVAL_LOCKED / "eval_reference_60.jsonl", "reference_vi"),
    "game_english": (EVAL_LOCKED / "eval_game_english_locked.jsonl", "reference_vi"),
    "fullchapters": (EVAL_LOCKED / "hachimi_vnext_e_fullchapters.jsonl", None),
}
# Nơi chứa dữ liệu train — bất cứ dòng nào trùng eval là rò rỉ.
TRAIN_DIRS = (HUB / "data" / "gold", HUB / "data" / "replay")

# Thư viện cần cho tầng `score`, kèm lý do để thông báo thiếu nói được điều hữu ích.
SCORE_DEPS = {
    "ctranslate2": "chạy model CT2 đã export",
    "transformers": "tokenizer Marian",
    "sentencepiece": "tokenizer Marian cần bản gốc SPM",
}


# ---------------------------------------------------------------- tiện ích

def _rows(path: Path):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.strip():
            yield number, json.loads(line)


def _zh(row: dict) -> str:
    """Cùng thứ tự khoá mà kaggle_train.assert_no_leakage dùng, để hai bên đo cùng một thứ."""
    return str(row.get("zh") or row.get("source") or row.get("source_zh") or "")


def _norm(text: str) -> str:
    return re.sub(r"\s+", "", text)


def _hash(text: str) -> str:
    return hashlib.sha256(_norm(text).encode("utf-8")).hexdigest()


def _sha_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Report:
    """Gom kết quả để in một lần, và nhớ đã có lỗi thật hay chưa."""

    def __init__(self) -> None:
        self.lines: list[str] = []
        self.failed = False

    def ok(self, text: str) -> None:
        self.lines.append(f"  OK   {text}")

    def warn(self, text: str) -> None:
        self.lines.append(f"  CHU Y {text}")

    def fail(self, text: str) -> None:
        self.lines.append(f"  LOI  {text}")
        self.failed = True

    def head(self, text: str) -> None:
        self.lines.append(f"\n{text}")

    def show(self) -> None:
        print("\n".join(self.lines))


# ---------------------------------------------------------------- check

def check_locked(rep: Report) -> dict:
    """Ba tập eval phải còn nguyên: tồn tại, đọc được, mọi dòng có ZH."""
    rep.head("[1/3] Tap eval khoa")
    manifest: dict = {}
    for name, (path, ref_key) in LOCKED.items():
        if not path.exists():
            rep.fail(f"{name}: thieu file {path}")
            continue
        try:
            rows = list(_rows(path))
        except json.JSONDecodeError as exc:
            rep.fail(f"{name}: JSONL hong — {exc}")
            continue
        thieu_zh = [n for n, r in rows if not _zh(r).strip()]
        thieu_ref = [n for n, r in rows if ref_key and not str(r.get(ref_key) or "").strip()]
        manifest[name] = {"path": str(path.relative_to(HUB)), "rows": len(rows), "sha256": _sha_file(path)}
        if thieu_zh:
            rep.fail(f"{name}: {len(thieu_zh)} dong thieu ZH (dong {thieu_zh[:5]})")
        elif thieu_ref:
            rep.fail(f"{name}: {len(thieu_ref)} dong thieu {ref_key} (dong {thieu_ref[:5]})")
        else:
            rep.ok(f"{name}: {len(rows)} dong, sha {manifest[name]['sha256'][:12]}")
    return manifest


def check_manifest(rep: Report, moi: dict, cap_nhat: bool) -> None:
    """Manifest là thứ chứng minh 'eval đã khoá' — nó lệch thì mọi so sánh cũ mất nghĩa."""
    rep.head("[2/3] Manifest")
    if not MANIFEST.exists():
        rep.warn(f"chua co {MANIFEST.name} — chay lai voi --update-manifest de tao")
        cu = {}
    else:
        cu = json.loads(MANIFEST.read_text(encoding="utf-8"))

    lech = []
    for name, info in moi.items():
        truoc = cu.get(name)
        if not isinstance(truoc, dict) or "sha256" not in truoc:
            lech.append(f"{name}: manifest chua ghi")
        elif truoc["sha256"] != info["sha256"]:
            lech.append(f"{name}: sha lech (manifest {truoc['sha256'][:12]} vs file {info['sha256'][:12]})")
        elif truoc.get("rows") != info["rows"]:
            lech.append(f"{name}: so dong lech ({truoc.get('rows')} vs {info['rows']})")

    if cap_nhat:
        giu = {k: v for k, v in cu.items() if k not in moi}
        MANIFEST.write_text(json.dumps({**giu, **moi}, ensure_ascii=False, indent=2), encoding="utf-8")
        rep.ok(f"da ghi lai {MANIFEST.name} theo file thuc te ({len(moi)} tap)")
        for m in lech:
            rep.warn(f"da sua: {m}")
        return

    if not lech:
        rep.ok("manifest khop file thuc te")
    for m in lech:
        # Manifest cũ trỏ đường dẫn Windows là chuyện đã biết; nói rõ cách chữa thay vì chỉ kêu.
        rep.fail(f"{m}  -> neu doi la co y: chay lai voi --update-manifest")


def check_leakage(rep: Report) -> None:
    """Cùng luật với pipeline/kaggle_train.assert_no_leakage: trùng hash ZH HOẶC trùng chương."""
    rep.head("[3/3] Ro ri train/eval")
    hashes: dict[str, str] = {}
    groups: dict[tuple, str] = {}
    for name, (path, _) in LOCKED.items():
        if not path.exists():
            continue
        for _, row in _rows(path):
            zh = _zh(row)
            if zh.strip():
                hashes[_hash(zh)] = name
            nid, cidx = row.get("novel_id"), row.get("chapter_index")
            if nid is not None and cidx is not None:
                groups[(nid, cidx)] = name

    tong = 0
    for folder in TRAIN_DIRS:
        if not folder.exists():
            rep.warn(f"khong co {folder.relative_to(HUB)} — bo qua")
            continue
        for path in sorted(folder.glob("*.jsonl")):
            dinh = []
            for number, row in _rows(path):
                zh = _zh(row)
                if zh.strip() and _hash(zh) in hashes:
                    dinh.append((number, "hash ZH", hashes[_hash(zh)]))
                    continue
                key = (row.get("novel_id"), row.get("chapter_index"))
                if key in groups:
                    dinh.append((number, "cung chuong", groups[key]))
            if dinh:
                tong += len(dinh)
                vidu = ", ".join(f"dong {n} ({ly}, tap {t})" for n, ly, t in dinh[:3])
                rep.fail(f"{path.relative_to(HUB)}: {len(dinh)} dong ro ri — {vidu}")
    if not tong:
        rep.ok(f"khong co dong train nao trung eval ({len(hashes)} hash, {len(groups)} chuong duoc canh)")


def check_env(rep: Report) -> None:
    """Không phải lỗi — chỉ nói thẳng tầng `score` chạy được hay không, ngay bây giờ."""
    rep.head("[moi truong] tang `score`")
    thieu = []
    for mod, ly_do in SCORE_DEPS.items():
        try:
            __import__(mod)
            rep.ok(f"{mod} — {ly_do}")
        except ImportError:
            thieu.append(mod)
            rep.warn(f"THIEU {mod} — {ly_do}")
    models = HUB.parent / "models"
    co = sorted(p.name for p in models.glob("*") if p.is_dir()) if models.exists() else []
    rep.ok(f"model co san: {', '.join(co) or 'khong co'}")
    if thieu:
        rep.warn("=> `score` chua chay duoc. Dung mot venv rieng, dung cai vao python3 he thong:")
        rep.warn(f"   python3 -m venv ~/.venvs/hachimi && ~/.venvs/hachimi/bin/pip install {' '.join(thieu)}")


def cmd_check(args) -> int:
    rep = Report()
    moi = check_locked(rep)
    check_manifest(rep, moi, args.update_manifest)
    check_leakage(rep)
    check_env(rep)
    rep.show()
    print("\nKET LUAN:", "CO LOI — doc muc LOI o tren" if rep.failed else "eval khoa con nguyen, khong ro ri")
    return 1 if rep.failed else 0


# ---------------------------------------------------------------- score

def cmd_score(args) -> int:
    thieu = [m for m in SCORE_DEPS if not _co(m)]
    if thieu:
        print(f"Thieu thu vien: {', '.join(thieu)}")
        print(f"  python3 -m venv ~/.venvs/hachimi && ~/.venvs/hachimi/bin/pip install {' '.join(thieu)}")
        print("  roi chay lai bang python cua venv do.")
        return 2

    model = Path(args.model).resolve()
    if not (model / "model.bin").exists():
        print(f"Khong thay model CT2 o {model} (thieu model.bin)")
        return 2

    sys.path.insert(0, str(HUB.parent))
    from hachimi.eval import eval_common as ec  # noqa: E402  — chỉ import khi thật sự đo

    import ctranslate2  # noqa: E402
    from transformers import AutoTokenizer  # noqa: E402

    tok = AutoTokenizer.from_pretrained(args.tokenizer or str(model))
    tran = ctranslate2.Translator(str(model), device="cpu")

    def dich(zh: str) -> str:
        toks = tok.convert_ids_to_tokens(tok.encode(zh))
        out = tran.translate_batch([toks], max_batch_size=args.batch)[0].hypotheses[0]
        return tok.decode(tok.convert_tokens_to_ids(out), skip_special_tokens=True)

    ket_qua = {}
    for name in args.tap:
        path, ref_key = LOCKED[name]
        if ref_key is None:
            print(f"bo qua {name}: tap nay khong co ban tham chieu mot-doi-mot")
            continue
        sims, quote_loi, han_sot = [], 0, 0
        rows = list(_rows(path))[: args.limit or None]
        for i, (_, row) in enumerate(rows, 1):
            vi = dich(_zh(row))
            sims.append(ec.similarity(str(row[ref_key]), vi))
            quote_loi += 0 if ec.balanced_quotes(vi) else 1
            han_sot += 1 if re.search(r"[一-鿿]", vi) else 0
            if args.verbose:
                print(f"  [{i}/{len(rows)}] sim={sims[-1]:.4f}")
        ket_qua[name] = {
            "rows": len(sims),
            "similarity_tb": round(sum(sims) / len(sims), 4) if sims else 0.0,
            "quote_loi": quote_loi,
            "han_sot": han_sot,
        }

    ra = {"model": str(model), "ket_qua": ket_qua}
    print(json.dumps(ra, ensure_ascii=False, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps(ra, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\nDa ghi {args.out}")
    print("\nLUU Y: similarity chi la chi bao ky tu, KHONG thay cho doc tay "
          "(xem hachimi_eval_locked.md).")
    return 0


def _co(mod: str) -> bool:
    try:
        __import__(mod)
        return True
    except ImportError:
        return False


# ---------------------------------------------------------------- self-check

def cmd_self_check(_) -> int:
    """Kiểm chính file này, theo lệ mọi script pipeline đều có --self-check."""
    assert _hash("a b") == _hash("ab"), "hash phai bo khoang trang"
    assert _zh({"source_zh": "x"}) == "x" and _zh({"zh": "y", "source_zh": "x"}) == "y"
    r = Report()
    r.ok("x"); assert not r.failed
    r.fail("y"); assert r.failed
    assert set(LOCKED) == {"reference_60", "game_english", "fullchapters"}
    print("self-check OK")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Bo danh gia Hachimi — mot cong vao")
    sub = ap.add_subparsers(dest="cmd")

    c = sub.add_parser("check", help="toan ven eval khoa + ro ri + moi truong (stdlib)")
    c.add_argument("--update-manifest", action="store_true", help="ghi lai manifest theo file thuc te")
    c.set_defaults(func=cmd_check)

    s = sub.add_parser("score", help="do mot model CT2 tren tap khoa")
    s.add_argument("model", help="thu muc model CT2, vd models/hachimi-ct2")
    s.add_argument("--tokenizer", help="thu muc tokenizer neu khac model")
    s.add_argument("--tap", nargs="+", default=["reference_60", "game_english"], choices=list(LOCKED))
    s.add_argument("--limit", type=int, default=0, help="chi do N dong dau (de thu nhanh)")
    s.add_argument("--batch", type=int, default=8)
    s.add_argument("--out", help="ghi ket qua ra file JSON")
    s.add_argument("--verbose", action="store_true")
    s.set_defaults(func=cmd_score)

    sub.add_parser("self-check", help="tu kiem file nay").set_defaults(func=cmd_self_check)

    # Theo le cua pipeline/: `--self-check` la co, khong phai lenh con.
    if "--self-check" in sys.argv[1:]:
        return cmd_self_check(None)

    args = ap.parse_args()
    if not getattr(args, "func", None):
        ap.print_help()
        return 0
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
