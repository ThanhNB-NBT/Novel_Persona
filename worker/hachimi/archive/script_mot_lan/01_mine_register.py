"""Mine ca lỗi register CĂN DÒNG CHẶT: chỉ chương có số dòng-có-chữ zh==vi khớp đúng
(Hachimi giữ khung dòng; lệch = bản cũ/lỗi -> bỏ). Xuất error_cases.jsonl sạch."""
import json
import re
import sys
from novelworker import db
from novelworker.translator.lint import _DIALOGUE

sb = db.sb()
OUT = r"E:\Novel_Project\worker\hachimi_finetune\dataset\error_cases.jsonl"
CAP = int(sys.argv[1]) if len(sys.argv) > 1 else 2000

_V = r"(?:đã|sẽ|đang|vẫn|cũng|bị|được|phải|không|chẳng|liền|lại|có|là|cảm|nghĩ|biết|muốn|thấy|nhìn|nói|ngồi|đứng|đi|quay)"
MINH = re.compile(rf"(?:^|[,;]\s*|\b(?:thì|nhưng|và|rồi|nên|mà|vì|khi|nếu|còn)\s+)mình\s+{_V}\b", re.I)
TOI = re.compile(rf"(?<!của )(?<!cho )\btôi\s+{_V}\b", re.I)
CAU = re.compile(rf"\bcậu\s+{_V}\b", re.I)  # cậu ĐẠI TỪ (loại cậu bé/nhóc/chủ)
# đại từ hiện đại ngôi ba — lỗi rõ ràng, không dính phản thân
MODERN3 = re.compile(r"\b(?:anh ta|anh ấy|cô ta|cô ấy|cậu ta|ông ta|bà ta)\b", re.I)
HAN = re.compile(r"[一-鿿]")


def leaky(vi_line: str) -> bool:
    narr = _DIALOGUE.sub(" ", vi_line)
    return bool(MINH.search(narr) or TOI.search(narr) or CAU.search(narr) or MODERN3.search(narr))


seen = set()
out = []
frm = 0
n_chap = n_aligned = 0
while len(out) < CAP:
    b = sb.table("chapters").select("novel_id,chapter_index,content_zh,content_vi") \
        .eq("translation_status", "done").not_.is_("content_zh", "null") \
        .eq("model_used", "hachimi").range(frm, frm + 199).execute().data or []
    if not b:
        break
    for c in b:
        n_chap += 1
        zl = [x.strip() for x in (c["content_zh"] or "").split("\n") if x.strip()]
        vl = [x.strip() for x in (c["content_vi"] or "").split("\n") if x.strip()]
        if len(zl) != len(vl):
            continue  # khung lệch -> bỏ cả chương (căn dòng không tin được)
        n_aligned += 1
        for z, v in zip(zl, vl):
            if not HAN.search(z) or len(z) > 180 or not leaky(v):
                continue
            ratio = len(v) / max(len(z), 1)
            if not (1.8 <= ratio <= 4.5):  # cặp lệch nghĩa/cụt -> bỏ
                continue
            h = hash(z)
            if h in seen:
                continue
            seen.add(h)
            out.append({"zh": z, "vi_model": v, "tag": "register",
                        "novel_id": c["novel_id"], "chapter_index": c["chapter_index"]})
            if len(out) >= CAP:
                break
        if len(out) >= CAP:
            break
    frm += 200

with open(OUT, "w", encoding="utf-8") as f:
    for r in out:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
print(f"Quét {n_chap} chương, {n_aligned} chương khung khớp. Ghi {len(out)} ca sạch -> {OUT}")
