"""Chạy THẬT nhánh --doclevel-corpus của kaggle_train.main (train được monkeypatch).

Lý do có test này: self-check cũ không đụng nhánh doclevel nên đã lọt lỗi thiếu tham số
`manifest` khi gọi _train_and_export — người dùng dính lỗi trên Kaggle. Test này gọi main()
đúng như CLI, chặn ở _train_and_export, và kiểm nó nhận đủ 4 tham số (manifest là dict).
"""
import importlib.util
import json
import pathlib
import sys

_KT = pathlib.Path(__file__).resolve().parents[1] / "hachimi" / "pipeline" / "kaggle_train.py"


def _load():
    if str(_KT.parent) not in sys.path:
        sys.path.insert(0, str(_KT.parent))  # để kaggle_train import được text_clean cùng thư mục
    spec = importlib.util.spec_from_file_location("kaggle_train", _KT)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["kaggle_train"] = mod
    spec.loader.exec_module(mod)
    return mod


def test_doclevel_branch_calls_train_with_manifest(monkeypatch):
    kt = _load()
    corpus = pathlib.Path(__file__).parent / "_tmp_doclevel_corpus.jsonl"
    corpus.write_text("".join(
        json.dumps({"zh": f"他走{i}。", "vi": f"Hắn đi {i}.", "ctx_len": 0}, ensure_ascii=False) + "\n"
        for i in range(100)), encoding="utf-8")

    captured = {}

    def fake_train(args, rows, eval_rows, manifest):
        captured["rows"] = rows
        captured["eval_rows"] = eval_rows
        captured["manifest"] = manifest

    monkeypatch.setattr(kt, "_train_and_export", fake_train)
    monkeypatch.setattr(sys, "argv", ["kaggle_train.py",
                                      "--doclevel-corpus", str(corpus),
                                      "--eval-holdout", "10"])
    try:
        kt.main()
    finally:
        corpus.unlink(missing_ok=True)

    assert isinstance(captured["manifest"], dict), "phải truyền manifest (dict) — lỗi cũ thiếu nó"
    assert captured["manifest"]["base_model"] == kt.MODEL_ID
    assert len(captured["eval_rows"]) == 5   # min(10, 100//20)
    assert len(captured["rows"]) == 95
    # eval không rò sang train
    eval_zh = {r["zh"] for r in captured["eval_rows"]}
    assert not (eval_zh & {r["zh"] for r in captured["rows"]})
