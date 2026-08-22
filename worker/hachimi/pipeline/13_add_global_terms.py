"""Thêm term GLOBAL cho những lỗi mà finetune đã chứng minh là không sửa được.

Vòng v4 cho thấy booster vài chục dòng không đè nổi prior của model: 高校 vẫn ra "Cao
hiệu", 冷却时间 vẫn ra "Thời gian hồi chiêu", 哥哥/姐姐 vẫn ra "anh trai/chị gái" dù đã
có mẫu trong data. Những thứ này là ÁNH XẠ CỐ ĐỊNH — đúng việc của glossary + termguard,
cưỡng chế được 100% và có hiệu lực ngay, không cần train lại.

Mặc định CHỈ IN RA; thêm `--write` mới ghi DB.
"""
from __future__ import annotations

import sys

from novelworker import db


# (chữ Trung, bản dịch bắt buộc, ghi chú)
TERMS = [
    ("哥哥", "ca ca", "xưng hô cổ phong, không dùng 'anh trai'"),
    ("姐姐", "tỷ tỷ", "xưng hô cổ phong, không dùng 'chị gái'"),
    ("妹妹", "muội muội", "xưng hô cổ phong, không dùng 'em gái'"),
    ("弟弟", "đệ đệ", "xưng hô cổ phong, không dùng 'em trai'"),
    ("冷却时间", "CD", "truyện võng du dùng CD, không dịch 'thời gian hồi chiêu'"),
    ("高校", "trường cao đẳng", "model hay ra 'Cao tá'/'Cao hiệu' — chữ vô nghĩa"),
    # Đợt 26/07: đo trên glossary thật (term xuất hiện ở ≥5 truyện, xem bản dịch nào
    # thắng phiếu). Năm cái dưới đây ĐA SỐ đang sai — bảng Hán-Việt của dự án là trọng tài.
    ("筑基", "Trúc Cơ", "hanviet=Trúc Cơ; 82 truyện, bản thắng đang là 'chúc cơ' (sai âm)"),
    ("元婴", "Nguyên Anh", "hanviet=Nguyên Anh; 57 truyện, tản mát ra 'nguyên doanh' (sai âm)"),
    ("天赋", "thiên phú", "hanviet=Thiên Phú; 44 truyện, có nhánh 'thiên phúc' (sai âm)"),
    ("异能", "dị năng", "46 truyện, model đẻ ra 'năng lực dị năng'/'năng lực dị' (lặp, cụt)"),
    ("金手指", "kim thủ chỉ", "gu truyện chuyển ngữ; 'kim chỉ nam'/'kim chỉ' là sai nghĩa"),
    # Đợt 5/8: đọc tay v5 thấy dịch KHÔNG NHẤT QUÁN trong cùng chương ('đệ tử nòng cốt' vs
    # 'đệ tử hạch tâm'). 1-nghĩa, an toàn ép global. Bản dưới là ĐỀ XUẤT — đổi nếu gu muốn
    # 'hạch tâm'. Đây là term chung, LLM không trích nên không tự vào glossary → phải thêm tay.
    ("核心弟子", "đệ tử nòng cốt", "5/8: cùng chương ra 2 kiểu (nòng cốt/hạch tâm); chốt 1 bản"),
    # Hạng 2 (7/8) — LÓNG/THƯƠNG HIỆU BẤT NHỊ NGHĨA. Chỉ thêm term gần như luôn 1 nghĩa,
    # an toàn ép global (termguard khớp thô term_zh in zh; đa nghĩa sẽ bắn nhầm — xem EXCLUDE).
    ("嘎腰子", "lấy thận", "meme mổ cướp thận; model ra 'bóp eo'. Niche, ~luôn 1 nghĩa"),
    ("网吧", "quán net", "internet cafe, ánh xạ 1:1 tuyệt đối"),
    ("开黑", "chơi tổ đội", "lóng game 'tổ đội có voice'; model ra 'mở màn'. ĐỀ XUẤT — tinh gu VI"),
]
# Hạng 2 — ĐA NGHĨA, KHÔNG ép global (bắn nhầm ngữ cảnh khác). Để dành cho vòng train
# Hạng 1 dưới dạng ví dụ phân biệt ngữ cảnh (DictDis), hoặc thêm per-novel cho truyện game/mạt chược:
#   自摸  = mạt chược "tự ù/tự mò"  NHƯNG cũng "tự sờ" → ép global sẽ hỏng cảnh thân mật
#   脉动  = nước Mizone            NHƯNG cũng "nhịp đập/mạch động" → ép global phá câu tả cảnh
# ĐÃ THỬ VÀ BỎ: 高中 → "trường cấp ba". Model vốn dịch đúng 高中生 = "dáng vẻ học sinh
# cấp ba"; ép term làm câu tệ đi ("trông như thật của trường cấp ba"). Chỉ ép những chỗ
# model thật sự dịch sai, đừng ép cái nó đã làm đúng.
REMOVE = ["高中"]


def existing() -> dict[str, dict]:
    rows = (
        db.sb().table("glossary_terms").select("id,term_zh,correct_vi,approved,novel_id")
        .is_("novel_id", "null").execute().data or []
    )
    return {row["term_zh"]: row for row in rows if row.get("term_zh")}


def main(write: bool) -> None:
    have = existing()
    todo = []
    for zh, vi, note in TERMS:
        current = have.get(zh)
        if current and (current.get("correct_vi") or "").strip() == vi and current.get("approved"):
            print(f"  = {zh:8} đã có đúng '{vi}'")
            continue
        todo.append((zh, vi, note, current))
        action = "sửa" if current else "thêm"
        print(f"  {action:4} {zh:8} -> {vi:18} {('(cũ: ' + str(current.get('correct_vi')) + ')') if current else ''}")
    drop = [have[zh] for zh in REMOVE if zh in have]
    for row in drop:
        print(f"  gỡ  {row['term_zh']:8} (đã thử, làm câu tệ hơn)")
    if not write:
        print(f"\n{len(todo)} term sẽ ghi, {len(drop)} term sẽ gỡ — chạy thử, thêm --write để ghi DB.")
        return
    for row in drop:
        db.sb().table("glossary_terms").delete().eq("id", row["id"]).execute()
    for zh, vi, note, current in todo:
        payload = {"term_zh": zh, "correct_vi": vi, "term_type": "other",
                   "approved": True, "note": note or None, "novel_id": None}
        if current:
            db.sb().table("glossary_terms").update(
                {"correct_vi": vi, "approved": True, "wrong_vi": current.get("correct_vi"), "note": note or None}
            ).eq("id", current["id"]).execute()
        else:
            db.sb().table("glossary_terms").insert(payload).execute()
    print(f"Đã ghi {len(todo)} term global.")


def self_check() -> None:
    assert len({zh for zh, _, _ in TERMS}) == len(TERMS), "trùng term_zh"
    assert all(len(zh) >= 2 and vi.strip() for zh, vi, _ in TERMS), "termguard cần term ≥2 ký tự"
    print(f"13_add_global_terms OK — {len(TERMS)} term")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        self_check()
    else:
        main("--write" in sys.argv)
