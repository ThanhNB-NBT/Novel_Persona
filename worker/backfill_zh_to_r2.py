"""Một lần: dời content_zh của chương done từ Supabase sang R2 rồi NULL cột (nhẹ DB).

Chạy TRÊN VPS nơi có .env đủ credential R2 + Supabase:
    python backfill_zh_to_r2.py            # chạy thật
    python backfill_zh_to_r2.py --dry-run  # chỉ đếm, không ghi

An toàn để chạy lại: chỉ đụng chương done còn content_zh not-null; NULL cột SAU khi
put R2 thành công. Đứt giữa chừng thì chạy lại là xong nốt phần còn lại.
"""
from __future__ import annotations

import sys

from novelworker import blob, db

DRY = "--dry-run" in sys.argv
BATCH = 200


def main() -> None:
    if not blob.enabled():
        sys.exit("R2 chưa cấu hình (.env thiếu R2_*) — không có chỗ để dời. Dừng.")

    moved = failed = 0
    while True:
        rows = (
            db.sb().table("chapters")
            .select("id, content_zh")
            .eq("translation_status", "done")
            .not_.is_("content_zh", "null")
            .limit(BATCH)
            .execute()
        ).data or []
        if not rows:
            break
        for ch in rows:
            zh = ch.get("content_zh")
            if not zh:
                continue
            if DRY:
                moved += 1
                continue
            if blob.put_zh(ch["id"], zh):
                db.sb().table("chapters").update(
                    {"content_zh": None}, returning="minimal").eq("id", ch["id"]).execute()
                moved += 1
            else:
                failed += 1
        print(f"...đã xử lý {moved} (lỗi {failed})", flush=True)
        if DRY:  # dry-run: limit không NULL nên vòng lặp sẽ lặp mãi — chạy 1 batch là đủ ước lượng
            print("(dry-run: dừng sau 1 batch, nhân lên để ước lượng tổng)")
            break

    print(f"XONG. Đã dời {moved} chương sang R2, {failed} lỗi (giữ lại DB).")


if __name__ == "__main__":
    main()
