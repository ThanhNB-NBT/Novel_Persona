"""Kéo self-check của cổng corpus vào pytest.

Bài học termguard (26/07): self-check chỉ chạy khi gọi tay thì CI vẫn xanh trong lúc bug
sống nhiều ngày. Module tên bắt đầu bằng số nên phải nạp bằng importlib.
"""
import importlib.util
import pathlib

_PIPELINE = pathlib.Path(__file__).resolve().parents[1] / "hachimi" / "pipeline"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, _PIPELINE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_gate_corpus_selfcheck():
    _load("14_gate_corpus").self_check()


def test_doclevel_selfcheck():
    _load("16_make_doclevel")._self_check()
