"""Chuẩn hoá thuật ngữ văn bản hệ thống (truyện có hệ thống / LitRPG).

CỐ Ý LÀM HẸP. Quét toàn bộ 9,37 triệu dòng ngày 03/09 cho thấy phần lớn cái trông như
"dịch không nhất quán" thật ra là biến thể HỢP LỆ, sửa đi là làm hỏng:

    叮  -> keng / leng   ĐÚNG khi là 叮叮当当 (tiếng kim loại, tiếng chuông), không phải
                         tiếng thông báo. Chỉ 叮~ / 叮！ / 叮， đi kèm 系统/恭喜 mới là thông báo.
    等级 -> đẳng cấp 473 / cấp bậc 398   — chia gần đôi, cả hai đều dùng được
    奖励 -> thưởng 276 / phần thưởng 192 — khác vai ngữ pháp, động từ vs danh từ
    经验 -> kinh nghiệm / điểm kinh nghiệm — cái sau đúng cho 经验值
    解锁 -> mở khóa / mở khoá — chỉ khác cách bỏ dấu, cùng một chữ

Sau khi loại hết các ca trên, số dòng SAI THẬT trên 9,37 triệu chỉ còn:

    宿主 -> "túc chủ"        49   (ký chủ áp đảo 258/23 trong mẫu, thống nhất về ký chủ)
    叮   -> "Ting" (hệ thống) 41   (Đinh áp đảo 201/13)
    熟练度 -> "thuần thục độ"   4   (calque kiểu convert, đúng là "độ thuần thục")
    面板 -> "diện bản"         2   (calque kiểu convert, đúng là "bảng")

Tức 96 dòng. Bảng này KHÔNG đáng để dựng thành một tầng xử lý nặng, nhưng chạy thì rẻ và
nó chặn được lỗi tái diễn ở các đợt dịch sau — nên để nguyên đây, đừng nới thêm luật nếu
chưa quét lại và đếm được ca sai thật.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

# (mẫu chữ Hán bắt buộc có trong nguồn, mẫu sai trong bản dịch, bản thay)
LUAT: list[tuple[re.Pattern, re.Pattern, str]] = [
    # Luật viết HOA phải đứng TRƯỚC luật re.I, nếu không luật re.I nuốt mất và trả về
    # bản thường — mất chữ hoa đầu câu.
    (re.compile(r"宿主"), re.compile(r"\bTúc [Cc]hủ\b"), "Ký chủ"),
    (re.compile(r"宿主"), re.compile(r"\btúc chủ\b"), "ký chủ"),
    # Chỉ đổi 叮 khi ĐÚNG là tiếng thông báo hệ thống — kèm dấu ngắt rồi tới chữ hệ thống.
    (re.compile(r"叮\s*[~～！!，,]"), re.compile(r"\bTing\b"), "Đinh"),
    (re.compile(r"叮\s*[~～！!，,]"), re.compile(r"\bting\b"), "đinh"),
    (re.compile(r"熟练度"), re.compile(r"\bthuần thục độ\b", re.I), "độ thuần thục"),
    (re.compile(r"面板"), re.compile(r"\bdiện bản\b", re.I), "bảng"),
]


def fix(zh: str, vi: str) -> tuple[str, int]:
    n = 0
    for zp, vp, thay in LUAT:
        if not zp.search(zh):
            continue
        vi, k = vp.subn(thay, vi)
        n += k
    return vi, n


def main(argv=None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path, help="file jsonl có trường zh/vi")
    ap.add_argument("--apply", action="store_true", help="ghi đè thật; mặc định chỉ đếm")
    args = ap.parse_args(argv)

    tmp = args.path.with_suffix(args.path.suffix + ".tmp")
    rows = hit = 0
    with args.path.open(encoding="utf-8") as fin, tmp.open("w", encoding="utf-8") as fout:
        for line in fin:
            if not line.strip():
                continue
            r = json.loads(line)
            rows += 1
            vi, n = fix(r.get("zh") or "", r.get("vi") or "")
            if n:
                hit += 1
                r["vi"] = vi
            fout.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"{rows:,} dòng · sửa {hit} dòng")
    if args.apply:
        tmp.replace(args.path)
        print(f"đã ghi đè {args.path}")
    else:
        tmp.unlink()
        print("(chạy thử — thêm --apply để ghi thật)")


def _self_check() -> None:
    # Ca SAI: phải sửa
    assert fix("宿主获得奖励", "Túc chủ nhận thưởng")[0] == "Ký chủ nhận thưởng"
    assert fix("【叮~系统提示", "【Ting~ Hệ thống")[0] == "【Đinh~ Hệ thống"
    assert fix("熟练度提升", "thuần thục độ tăng")[0] == "độ thuần thục tăng"
    # Ca ĐÚNG: tuyệt đối không đụng — đây là chỗ dễ làm hỏng nhất
    assert fix("叮叮当当的铃铛声", "tiếng chuông keng keng")[1] == 0, "sửa nhầm tiếng chuông"
    assert fix("等级提升", "Đẳng cấp tăng")[1] == 0
    assert fix("获得奖励", "nhận được phần thưởng")[1] == 0
    # Khong co chu Han tuong ung thi khong dung, du ban dich co tu do
    assert fix("他走了", "Túc chủ đi rồi")[1] == 0, "sửa khi nguồn không có 宿主"
    print("normalize self-check OK")


if __name__ == "__main__":
    import sys
    if "--self-check" in sys.argv:
        _self_check()
    else:
        main()
