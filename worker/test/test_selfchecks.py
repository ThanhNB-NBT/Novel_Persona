"""Kéo mọi self-check kiểu script vào pytest.

Vì sao cần: phần lớn test trong thư mục này viết theo kiểu `def main(): assert...` rồi
chạy dưới `if __name__ == "__main__"`. pytest CHỈ thu hàm tên `test_*`, nên trước file
này CI chạy `pytest test/` mà bỏ qua 17/27 file — toàn bộ self-check adapter (biquge,
dingdian, piaotia, shuba, faloo, dedup, health…) chưa bao giờ được kiểm trong CI, và
pipeline vẫn xanh. Phát hiện 2026-07-26.

Cách trám: tự dò module nào có `main()` mà KHÔNG có hàm `test_*` rồi gọi `main()` như
một test. File self-check viết sau này được phủ tự động, không phải nhớ đăng ký gì.
"""
import importlib
import pathlib
import sys

import pytest

_DIR = pathlib.Path(__file__).parent
sys.path.insert(0, str(_DIR))
sys.path.insert(0, str(_DIR.parent))


def _script_style_modules() -> list[str]:
    names = []
    for f in sorted(_DIR.glob("test_*.py")):
        if f.name == pathlib.Path(__file__).name:
            continue
        src = f.read_text(encoding="utf-8", errors="ignore")
        # có main() và không có hàm test_* nào → pytest đang bỏ sót file này
        if "def main(" in src and "def test_" not in src:
            names.append(f.stem)
    return names


@pytest.mark.parametrize("modname", _script_style_modules())
def test_selfcheck(modname: str) -> None:
    mod = importlib.import_module(modname)
    assert hasattr(mod, "main"), f"{modname} không có main()"
    rc = mod.main()
    # phần lớn main() trả None và tự assert; vài cái (e2e) trả mã thoát
    assert rc in (None, 0), f"{modname}.main() trả mã lỗi {rc}"
