"""Lọc bỏ dòng hỏng khỏi bộ đã dịch, khi không còn credit để dịch lại.

HAI LUẬT, cố ý hẹp. Đo 03/09 trên 114.939 dòng của hai bộ crawl:

1. `vi` CÒN CHỮ HÁN -> bỏ (625 dòng, 0,54%).
   Phần lớn chỉ lọt lẻ một hai chữ ("một trận意外", "ả遛狗 nữ", "第六章 Xuân Tam Thập
   Nương"), chỉ 5 dòng lọt nặng. Nhưng đích huấn luyện mà còn chữ Hán là dạy model chép
   chữ Hán ra bản dịch — hỏng đúng thứ Hachimi đang phải chữa. Bỏ 0,54% rẻ hơn nhiều.

2. MẤT SỐ, nhưng CHỈ trong dòng có định dạng hệ thống -> bỏ.
   Không bỏ đại trà: `三个人` -> "ba người" làm mất chữ số mà là dịch ĐÚNG, tiếng Việt
   viết số nhỏ bằng chữ. Chỉ khi nguồn có 【】 hoặc cặp "chữ：số" thì con số mới là dữ
   liệu bảng biểu, mất là sai nghĩa chứ không phải sai văn phong.

KHÔNG bỏ dòng chỉ vì lệch số A-rập ngoài hai ngữ cảnh trên — đo được 826 dòng lệch mà
phần lớn là ca `三` -> "ba" hợp lệ; cắt hết là vứt dữ liệu tốt.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HAN = re.compile(r"[一-鿿]")
ARAB = re.compile(r"\d+")
# Dòng định dạng hệ thống: có khối 【】 hoặc cặp "chữ：số" kiểu 力量：38
HE_THONG = re.compile(r"【|[：:]\s*\d")


def hong(zh: str, vi: str) -> str:
    """Trả lý do bỏ, hoặc chuỗi rỗng nếu dòng dùng được."""
    if HAN.search(vi):
        return "lot chu Han"
    if HE_THONG.search(zh):
        thieu = set(ARAB.findall(zh)) - set(ARAB.findall(vi))
        if thieu:
            return "mat so trong bang he thong"
    return ""


def main(argv=None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", type=Path)
    ap.add_argument("--apply", action="store_true", help="ghi đè thật; mặc định chỉ đếm")
    args = ap.parse_args(argv)

    import collections
    for path in args.paths:
        ly_do = collections.Counter()
        tmp = path.with_suffix(path.suffix + ".tmp")
        giu = tong = 0
        with path.open(encoding="utf-8") as fin, tmp.open("w", encoding="utf-8") as fout:
            for line in fin:
                if not line.strip():
                    continue
                r = json.loads(line)
                tong += 1
                why = hong(r.get("zh") or "", r.get("vi") or "")
                if why:
                    ly_do[why] += 1
                    continue
                giu += 1
                fout.write(line if line.endswith("\n") else line + "\n")
        print(f"{path.name}: {tong:,} → giữ {giu:,} (bỏ {tong - giu}, "
              f"{(tong - giu) / tong * 100:.2f}%)")
        for k, v in ly_do.most_common():
            print(f"    {k}: {v}")
        if args.apply:
            tmp.replace(path)
        else:
            tmp.unlink()
    if not args.apply:
        print("(chạy thử — thêm --apply để ghi thật)")


def _self_check() -> None:
    assert hong("他走了", "Hắn đi rồi") == ""
    assert hong("因为意外", "Bởi một trận意外") == "lot chu Han"
    # Số viết thành chữ trong văn xuôi là ĐÚNG, không được bỏ — ca dễ cắt oan nhất
    assert hong("面前有3个人", "Trước mặt có ba người") == ""
    # Nhưng mất số trong bảng hệ thống là sai nghĩa
    assert hong("【军体拳：56/100】", "【Quân Thể Quyền】") == "mat so trong bang he thong"
    assert hong("力量：38", "Lực lượng: 38") == ""
    print("clean self-check OK")


if __name__ == "__main__":
    import sys
    if "--self-check" in sys.argv:
        _self_check()
    else:
        main()
