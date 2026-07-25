"""Đổi các term tên phương Tây trong glossary từ phiên âm Hán-Việt sang chữ Latin.

Chạy một lần sau khi chốt gu "tên Tây giữ chữ Latin" (25/07). Nguồn đề xuất:
`data/source/western_names_proposed.jsonl`. Bản cũ được ghi vào `wrong_vi` để prompt/job
patch còn sửa được các chương đã dịch theo cách gọi cũ.

Mặc định CHỈ IN RA; thêm `--write` mới ghi DB.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from novelworker import db
from novelworker.translator import hanviet


PROPOSED = Path(__file__).resolve().parents[1] / "data" / "source" / "western_names_proposed.jsonl"

# Sửa tay sau khi đọc lại: thầy đoán theo âm nên trượt mấy tên có nguồn gốc rõ.
OVERRIDE = {
    "克利普斯": "Crepus",        # cha của Diluc — cùng truyện đã có 迪卢克/诺艾尔
    "邓恩·哈兰德": "Dunn Haaland",  # 哈兰德 là Haaland
    "依鲁卡": "Iruka",
}
# Tên NGƯỜI TRUNG bị nhận nhầm là tên Tây — giữ nguyên Hán-Việt.
SKIP_ZH = {"劳德诺"}  # nhân vật Tiếu Ngạo Giang Hồ, không phải "Laudano"


def rows_to_apply() -> list[dict]:
    rows = [json.loads(line) for line in PROPOSED.read_text(encoding="utf-8").splitlines() if line.strip()]
    out = []
    for row in rows:
        zh = row["zh"]
        vi_moi = OVERRIDE.get(zh) or (row.get("vi_moi") or "").strip()
        if not vi_moi or zh in SKIP_ZH:
            continue
        # Bộ nhận dạng đã siết lại sau khi sinh file: bỏ các dòng giờ không còn là tên Tây
        # (tên kỹ năng/tựa sách có dấu chấm như 外力型·风吼, 《破阵子·地球困》).
        if not hanviet.looks_western(zh):
            continue
        if vi_moi == (row.get("vi_cu") or "").strip():
            continue
        out.append({**row, "vi_moi": vi_moi})
    return out


def main(write: bool) -> None:
    rows = rows_to_apply()
    print(f"{len(rows)} term sẽ đổi sang chữ Latin"
          + ("" if write else "  (chạy thử — thêm --write để ghi DB)"))
    for row in rows:
        mark = "*" if row["zh"] in OVERRIDE else " "
        print(f" {mark} nv{row['novel_id']:<6} {row['zh']:16} {row['vi_cu']:28} -> {row['vi_moi']}")
    if not write:
        return
    done = 0
    for row in rows:
        try:
            db.sb().table("glossary_terms").update({
                "correct_vi": row["vi_moi"],
                "wrong_vi": row["vi_cu"],  # để job patch sửa được chương đã dịch kiểu cũ
            }).eq("id", row["id"]).execute()
            done += 1
        except Exception as error:  # noqa: BLE001 — báo rồi chạy tiếp, không bỏ dở cả lô
            print(f"   LỖI id={row['id']}: {error}")
    print(f"Đã ghi {done}/{len(rows)} term.")


def self_check() -> None:
    rows = rows_to_apply()
    assert rows, "không có term nào để đổi"
    assert all(row["vi_moi"].isascii() or " " in row["vi_moi"] for row in rows)
    assert not any(row["zh"] in SKIP_ZH for row in rows)
    assert {row["zh"] for row in rows} & set(OVERRIDE), "override phải nằm trong danh sách"
    assert not any("·" in row["zh"] and not hanviet.looks_western(row["zh"]) for row in rows)
    print(f"11_apply_western_names OK — {len(rows)} term")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        self_check()
    else:
        main("--write" in sys.argv)
