"""Đối chiếu phiên âm Hán-Việt bằng BẢNG TRA — không để LLM đoán.

Âm Hán-Việt của mỗi chữ Hán là quy tắc tra cứu cố định (罗=la, 森=sâm), model nhỏ
hay phiên bừa kiểu pinyin ("Lao Sen"). Bảng data/hanviet.tsv: ph0ngp/hanviet-pinyin-words
(MIT) + Unihan kTraditionalVariant để phủ giản thể; ~13.6k chữ, đa âm ngăn bằng '|'.
"""
from __future__ import annotations

import re
from pathlib import Path

_TSV = Path(__file__).resolve().parent.parent / "data" / "hanviet.tsv"
_table: dict[str, list[str]] | None = None

# chữ đa âm mà âm đầu trong bảng nguồn KHÔNG phải âm phổ biến trong tên riêng
# (phát hiện qua thực chiến — thêm dần khi gặp)
_PREFERRED = {"宁": "ninh"}

# term_type áp quy tắc Hán-Việt bắt buộc; item/skill có thể dịch nghĩa ("Kiếm Lửa") → không ép
_HV_TYPES = {"person", "place", "sect"}

_HAN = re.compile(r"[一-鿿㐀-䶿]")


def _load() -> dict[str, list[str]]:
    global _table
    if _table is None:
        _table = {}
        with open(_TSV, encoding="utf-8") as f:
            for line in f:
                if line.startswith("#") or "\t" not in line:
                    continue
                ch, readings = line.rstrip("\n").split("\t", 1)
                rs = readings.split("|")
                pref = _PREFERRED.get(ch)
                if pref:  # đưa âm ưu tiên lên đầu, chèn mới nếu bảng thiếu
                    if pref in rs:
                        rs.remove(pref)
                    rs.insert(0, pref)
                _table[ch] = rs
    return _table


def han_viet(zh: str) -> str | None:
    """Phiên âm Hán-Việt mặc định (âm đầu bảng từng chữ), Title Case.
    None nếu có chữ ngoài bảng — không đoán bừa."""
    t = _load()
    parts = []
    for ch in zh:
        rs = t.get(ch)
        if not rs:
            return None
        parts.append(rs[0].capitalize())
    return " ".join(parts)


def transliteration_suspect(zh: str | None, vi: str | None, term_type: str | None) -> bool:
    """Tên riêng không phải phiên âm/ngoại danh hợp lệ thì đánh dấu để chờ duyệt."""
    if not zh or not vi or term_type not in _HV_TYPES:
        return False
    chars = [ch for ch in zh if _HAN.search(ch)]
    if len(chars) != len(zh) or (vi.isascii() and len(vi.split()) == 1):
        return False
    syls = vi.split()
    if not syls or _HAN.search(vi):
        return True
    t = _load()
    if len(syls) == len(chars) and all(t.get(ch) and s.lower() in t[ch]
                                             for ch, s in zip(chars, syls)):
        return False
    # Cùng khuôn reconcile đang xét là cố phiên âm; reconcile sẽ tự sửa nếu bảng tra được.
    return not (all(s[:1].isupper() for s in syls)
                and (len(syls) == len(chars) or term_type == "person"))


def reconcile(zh: str | None, vi: str | None, term_type: str | None) -> str | None:
    """Sửa phiên âm LLM theo bảng tra. Trả về vi (giữ nguyên hoặc đã sửa).

    NGUYÊN TẮC: chỉ sửa khi model đang CỐ PHIÊN ÂM mà phiên sai; không bao giờ đè
    một bản dịch NGHĨA ("đồn cảnh sát", "suối nhỏ" — giữ nguyên, kể cả khi Hán-Việt
    tồn tại). Bài học chạy thật 2026-07: ép mù quáng làm bản dịch tệ đi.

    - Chỉ xét person/place/sect (quy tắc: tên riêng Trung → Hán-Việt).
    - vi còn sót chữ Hán → thay bằng bản tra (vi thô chưa dịch không bao giờ đúng).
    - "Cố phiên âm" = số từ == số chữ Hán VÀ mọi từ viết hoa ("Lao Sen", "Châu Viễn").
      Ngoài khuôn đó (dịch nghĩa, cụm mô tả) → giữ nguyên.
    - Phiên đúng chuẩn (mỗi từ khớp MỘT âm hợp lệ của chữ tương ứng, kể cả đa âm
      长 trường/trưởng) → giữ. Phiên lệch (pinyin bừa) → thay bằng bản tra.
    - Tên ngoại 1 từ ASCII (Anna, Jack) → giữ theo quy tắc prompt.
    """
    if not zh or not vi or term_type not in _HV_TYPES:
        return vi
    chars = [ch for ch in zh if _HAN.search(ch)]
    if len(chars) != len(zh):  # lẫn Latin/số/dấu · → tên ngoại/hỗn hợp, không đụng
        return vi
    if _HAN.search(vi):  # vi còn nguyên chữ Hán → chưa dịch gì, tra thẳng
        return han_viet(zh) or vi
    if vi.isascii() and len(vi.split()) == 1:
        return vi  # tên ngoại 1 từ (Anna, Jack, Jean-Pierre, goblin)
    if "-" in vi:  # phiên âm gạch nối có dấu ("An-đê-ri-an") — kiểu bị cấm → tra bảng thay
        return han_viet(zh) or vi
    syls = vi.split()
    all_upper = all(s[:1].isupper() for s in syls)
    # person: tên người Trung không có "dịch nghĩa" toàn viết hoa hợp lệ → lệch số từ
    # ("Héc Nơ" 2 từ / 赫克诺 3 chữ) vẫn là phiên hỏng, không cần đếm khớp
    attempting = all_upper and (len(syls) == len(chars) or term_type == "person")
    if not attempting:
        return vi  # dịch nghĩa / cụm mô tả có từ thường — tôn trọng lựa chọn của model
    if len(syls) != len(chars):  # person lệch số từ → phiên hỏng chắc chắn, tra thẳng
        return han_viet(zh) or vi
    t = _load()
    if all(t.get(ch) and s.lower() in t[ch] for ch, s in zip(chars, syls)):
        return vi  # phiên đúng chuẩn (kể cả chọn âm khác của chữ đa âm)
    fixed = han_viet(zh)
    return fixed or vi
