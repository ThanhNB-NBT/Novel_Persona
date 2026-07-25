"""Sinh booster REGISTER tổng hợp: câu LỜI KỂ với 他/她/我 -> hắn/nàng/ta.
Cả zh lẫn vi tự điền theo slot => đáp án đúng theo cấu tạo (không cần thầy).
Dạy model: lời kể ngôi ba nam=hắn nữ=nàng; ngôi nhất/nội tâm 我=ta (KHÔNG tôi/mình)."""
import json
import itertools

OUT = r"E:\Novel_Project\worker\hachimi_finetune\dataset\booster.jsonl"

# (zh vế động từ, vi vế động từ) — curate CHUẨN, tự nhiên
VERBS = [
    ("握紧双拳", "siết chặt song quyền"),
    ("皱起眉头", "nhíu mày"),
    ("深吸一口气", "hít sâu một hơi"),
    ("缓缓睁开眼睛", "chậm rãi mở mắt"),
    ("转身离去", "xoay người rời đi"),
    ("点了点头", "gật đầu"),
    ("摇了摇头", "lắc đầu"),
    ("冷冷一笑", "cười lạnh một tiếng"),
    ("心中暗喜", "trong lòng thầm mừng"),
    ("心中一沉", "trong lòng chùng xuống"),
    ("抬头望向天空", "ngẩng đầu nhìn lên bầu trời"),
    ("低下了头", "cúi đầu xuống"),
    ("缓缓站起身", "chậm rãi đứng dậy"),
    ("停下脚步", "dừng bước"),
    ("握住了剑柄", "nắm lấy chuôi kiếm"),
    ("闭上双眼", "nhắm hai mắt lại"),
    ("长出一口气", "thở phào một hơi"),
    ("嘴角勾起一抹冷笑", "khóe miệng nhếch lên một nụ cười lạnh"),
    ("快步走上前", "rảo bước tiến lên"),
    ("微微一怔", "khẽ sững người"),
    ("眉头紧锁", "nhíu chặt mày"),
    ("抬手挥出一剑", "vung tay chém ra một kiếm"),
    ("心中升起一丝不安", "trong lòng dấy lên một tia bất an"),
    ("沉默了片刻", "trầm mặc trong chốc lát"),
    ("目光扫过四周", "ánh mắt quét qua xung quanh"),
    ("神色凝重", "sắc mặt ngưng trọng"),
    ("轻轻叹了口气", "khẽ thở dài"),
    ("握紧了手中的长剑", "nắm chặt thanh trường kiếm trong tay"),
    ("眼神变得冰冷", "ánh mắt trở nên lạnh lẽo"),
    ("向后退了一步", "lùi về sau một bước"),
    ("缓缓抬起头", "chậm rãi ngẩng đầu"),
    ("面色微微一变", "sắc mặt khẽ biến"),
    ("死死盯着前方", "chằm chằm nhìn về phía trước"),
    ("心头一紧", "trong lòng thắt lại"),
    ("咬了咬牙", "nghiến răng"),
    ("露出一丝微笑", "lộ ra một nụ cười"),
]

# (zh chủ ngữ, vi chủ ngữ) — 我 trong LỜI KỂ/nội tâm phải là 'ta'
SUBJ = [("他", "hắn"), ("她", "nàng"), ("我", "ta")]

# (zh tiền tố, vi tiền tố) — có tiền tố thì đại từ viết thường
PREFIX = [
    ("", ""),
    ("此时，", "Lúc này, "),
    ("片刻后，", "Chốc lát sau, "),
    ("闻言，", "Nghe vậy, "),
    ("下一刻，", "Khoảnh khắc tiếp theo, "),
    ("想到这里，", "Nghĩ đến đây, "),
    ("说到这里，", "Nói đến đây, "),
]


def cap(s: str) -> str:
    return s[:1].upper() + s[1:]


rows = []
seen = set()
# câu đơn: [tiền tố] + chủ ngữ + động từ
for (zp, vp), (zs, vs), (zv, vv) in itertools.product(PREFIX, SUBJ, VERBS):
    zh = f"{zp}{zs}{zv}。"
    vi = f"{vp}{vs if zp else cap(vs)} {vv}."
    if zh in seen:
        continue
    seen.add(zh)
    rows.append({"zh": zh, "vi": vi, "domain": "register_booster", "status": "approved"})

# câu 2 vế: chủ ngữ + V1，V2  (dạy giữ đại từ nhất quán, không đổi giữa chừng)
for (zs, vs), (z1, v1), (z2, v2) in itertools.product(SUBJ, VERBS, VERBS):
    if z1 == z2:
        continue
    zh = f"{zs}{z1}，{v2 and z2}。".replace("None", "")
    zh = f"{zs}{z1}，{z2}。"
    vi = f"{cap(vs)} {v1}, {v2}."
    if zh in seen:
        continue
    seen.add(zh)
    rows.append({"zh": zh, "vi": vi, "domain": "register_booster", "status": "approved"})
    if len(rows) >= 1200:
        break

with open(OUT, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
print(f"Sinh {len(rows)} câu booster register -> {OUT}")
print("Mẫu:")
for r in rows[:3] + rows[-3:]:
    print("  ", r["zh"], "->", r["vi"])
