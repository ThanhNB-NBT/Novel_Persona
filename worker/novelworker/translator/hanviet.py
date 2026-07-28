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

# chữ đa âm mà âm đầu trong bảng nguồn KHÔNG phải âm phổ biến trong TÊN RIÊNG
# (phát hiện qua thực chiến — thêm dần khi gặp). Chỉ thêm chữ CHẮC CHẮN: han_viet()
# chỉ chạy trên tên đã tách (person/place/sect), nên ưu tiên âm-làm-tên là an toàn;
# chữ nào âm-tên còn mập mờ (乐 lạc/nhạc, 重 trùng/trọng) thì ĐỪNG ép, kẻo hại diện rộng.
_PREFERRED = {
    "宁": "ninh",   # 宁 tên → Ninh (mặc định bảng cũng ninh, giữ chắc)
    "曾": "tăng",   # họ 曾 → Tăng (曾国藩 Tăng Quốc Phiên); mặc định 'tằng' là nghĩa "đã từng"
}

# term_type áp quy tắc Hán-Việt bắt buộc; item/skill có thể dịch nghĩa ("Kiếm Lửa") → không ép
_HV_TYPES = {"person", "place", "sect"}

_HAN = re.compile(r"[一-鿿㐀-䶿]")

# Chữ chuyên dùng để PHIÊN ÂM tên nước ngoài (音译用字). Tác giả Trung viết 埃尔顿 chứ
# không viết "Elton", nên muốn giữ tên Tây ở dạng Latin thì phải nhận ra từ phía chữ Hán.
_TRANSLIT_CHARS = set(
    "阿埃艾奥澳巴贝彼布波伯博达德迪蒂多顿俄厄尔法菲弗夫芙戈格哈赫"
    "基吉杰卡凯克科库拉莱兰朗劳勒雷莉丽琳卢鲁伦罗洛玛曼梅蒙米娜奈尼诺"
    "帕佩皮普齐乔琼萨塞桑瑟森莎沙什斯司苏索塔泰特提托图瓦威韦维沃乌西希夏"
    "谢辛雅亚娅扬伊依尤约兹泽詹珍朱茜妮丝黛琪蕾茉薇利摩安"
)
_NAME_DOT = re.compile(r"[·•‧・]")
# Họ người Trung: 林平安/李希希/马夫人 cũng toàn chữ nằm trong bảng phiên âm, nhưng chúng
# là tên Trung và phải giữ Hán-Việt. Tên bắt đầu bằng họ thì không coi là tên ngoại.
_CHINESE_SURNAMES = set(
    "赵钱孙李周吴郑王冯陈褚卫蒋沈韩杨朱秦尤许何吕施张孔曹严华金魏陶姜"
    "戚谢邹喻柏水窦章云苏潘葛奚范彭郎鲁韦昌马苗凤花方俞任袁柳鲍史唐费"
    "岑薛雷贺倪汤滕殷罗毕郝安常乐于时傅皮卞齐康伍余元卜顾孟平黄和穆萧尹"
    "姚邵湛汪祁毛禹狄米贝明臧计伏成戴宋茅庞熊纪舒屈项祝董梁杜阮蓝闵"
    "林刁钟徐邱骆高夏蔡田樊胡凌霍虞万支柯昝管卢莫房裘缪干解应宗丁宣贲邓劳"
)


def looks_western(zh: str | None) -> bool:
    """Đoán cụm chữ Hán này là PHIÊN ÂM một cái tên nước ngoài.

    Tín hiệu: dấu chấm giữa tên (罗林·埃尔顿 — người Trung không viết vậy), hoặc cụm ≥3 chữ
    mà ≥3/4 là chữ chuyên phiên âm và KHÔNG mở đầu bằng một họ người Trung.
    Ngưỡng đặt cao vì nhầm theo chiều ngược lại (biến tên Trung thành chữ Latin) tệ hơn
    nhiều so với bỏ sót một tên Tây: 林黛玉, 哈尔滨, 内蒙古 phải giữ Hán-Việt.
    """
    zh = (zh or "").strip()
    if not zh:
        return False
    hits = sum(1 for char in zh if char in _TRANSLIT_CHARS)
    if _NAME_DOT.search(zh):
        # Dấu chấm thôi chưa đủ: 内力型·瞬身, 《破阵子·地球困》 cũng có dấu chấm.
        return hits >= 1
    if len(zh) < 3 or zh[0] in _CHINESE_SURNAMES:
        return False
    return hits >= 3 and hits / len(zh) >= 0.75


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


_LATIN_PERSON = re.compile(r"^[A-Z][A-Za-z]*(?:[ .'\-][A-Za-z]+){0,2}$")
_syllables: set[str] | None = None


def _vi_syllables() -> set[str]:
    """Mọi âm Hán-Việt trong bảng, bỏ dấu — dùng để nhận ra một cụm ASCII là tiếng Việt
    không dấu ("Long gia", "Vong Linh") hay là tiếng Anh ("Awakening Stone")."""
    global _syllables
    if _syllables is None:
        strip = str.maketrans("àáảãạằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợ"
                              "ùúủũụưừứửữựỳýỷỹỵđ",
                              "aaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooo"
                              "uuuuuuuuuuuyyyyyd")
        _syllables = {r.lower().translate(strip) for rs in _load().values() for r in rs}
    return _syllables


# Từ MỘT TIẾNG bị chặn. Không có luật nào tách được "orc/goblin/slime" (giữ — tiếng Việt
# không có từ tương đương) khỏi "robot/computer/dagger" (rác — có từ Việt hiển nhiên), nên
# đây là DANH SÁCH, gom từ 309 từ một-tiếng thật trong glossary ngày 28/07/2026.
# Cố ý KHÔNG chặn: chủng loài/thuật ngữ game-net đã quen (goblin, orc, elf, dwarf, troll,
# ogre, slime, npc, boss, buff, debuff, guild, mod, instance, respawn, cosplay, anime, idol),
# từ mượn đã Việt hoá (kimono, ninja, karate, sake, cola, macaron), thuật ngữ khoa học
# (proton, electron, adrenaline, methanol, palladium) và tên riêng viết hoa.
# Gặp từ rác mới thì THÊM VÀO ĐÂY — đừng đổi sang luật đoán, đã thử và nó cắt nhầm.
_ENGLISH_COMMON = frozenset("""
acceleration acupoint agency agility alarm angel antelope apple archer armor aunt badge
bandage basketball bass battery battlecruiser battleship battlestar block book boy branch
bride bus camera candle card carrier case chainmail character charge cleric clubhouse
cocktail coder coffee computer container cruiser crystal dagger demon destroyer device
dollar domain dragon dreadnought dungeon endurance energy engine envelope euro experience
fierce fireball fireman football forest game ghost girl gold goodbye grape gun headset
hello helmet hotel human inn intelligence jail knife knight lake level library lifeboat
lightning lock longsword mama manor meridian meridians meteor mine moto mountain mountains
mud nightclub nurse outpost pager palanquin palette parchment party pharmacy phone pickup
pie pizza player playground poker puppet radio rapier rice rickshaw robot robots roulette
safehouse scanner shameless shark shortbow shutup skeleton slum smartphone snacks sniper
snow soap spacesuit spearman staff stamp starship stone strawberry strength strong suit
suitcase supercomputer superpower syringe system tank taxi terminal tiger toothpaste torch
umbrella unit vaccine vendor video wand warlock warship waterfall waves website wine wood
wristband
babaishui dantian fabao gohuo jiaosuo kimshouchi lazhu luoli mingwen neigong niepan xiuxian
abilities advanced alchemist armory assassin attack awakening awoke beast captain champion
cleaner common construction cultivator daoist damage defend defense dexterity dimensional
elder elite emperor equipment explosion foundry freshman gate general grain guards hangar
headquarters heir hollow hope hospital instinct intermediate inventory junior legend
legendary light loading luck mage magician mailman marketplace mechanic meditation
mentality mercenaries military mimicry miracle mirror mortal move mythic officer ordinary
origin orphanage perception petrification points portal possession priest prophet rare
reflex resurrection rogue sergeant server shopkeeper skill smelting sorceress soul
spaceship speed spell spirit stamina stealth talent tavern vagrant vehicle warehouse
warrior woman zone zones
alliance blue borderline chip constitution dad ding earth epic grandfather green hell
hypnosis magic papa pasta qi wolfman
""".split())

# Dấu thanh CHỈ có trong pinyin, không có trong tiếng Việt (macron ā, caron ǎ, ü có dấu).
# Không dùng á à í ì — tiếng Việt dùng chung, quét bằng chúng là bắt nhầm 31k dòng đúng.
_PINYIN_TONE = re.compile(r"[āēīōūǖǎěǐǒǔǚǘǜǹ]")


def english_meaning(zh: str | None, vi: str | None, term_type: str | None) -> bool:
    """True khi `vi` là cụm TIẾNG ANH dịch nghĩa, không phải bản dịch tiếng Việt.

    Model trích tên xấu (qwen3-next-80b, 25-26/07/2026) trả 觉醒石 → "Awakening Stone",
    七班 → "Class 7": chúng không bao giờ dùng được (cổng `_is_safe_pending_term` chặn)
    mà vẫn ngập màn Thuật ngữ. Nhận diện: cụm ASCII NHIỀU TỪ có ít nhất một từ không
    phải âm Hán-Việt. Giữ lại có chủ đích:
      * một từ ASCII (goblin, slime, Anna) — đúng luật prompt, reconcile() cũng giữ;
      * tên người Latin ≤3 từ (Tony Stark) — ngoại lệ tên Tây đã có sẵn;
      * cụm ASCII toàn âm Hán-Việt ("Long Gia", "Vong Linh") — tiếng Việt không dấu.
    Đánh đổi đã biết: 纽约 → "New York" cũng bị coi là tiếng Anh. Chấp nhận được vì
    term chưa duyệt loại này KHÔNG vào prompt dịch, mất nó chỉ mất một dòng gợi ý.

    Từ MỘT tiếng thì tra `_ENGLISH_COMMON` — trừ khi chữ Hán gốc đúng là phiên âm tên
    ngoại (德鲁依 → druid giữ, dù 'druid' có nằm trong danh sách hay không)."""
    s = (vi or "").strip()
    if _PINYIN_TONE.search(s):
        return True      # "Bèi Sàngshī Bìngdú" — pinyin thô, chưa dịch gì
    if not s.isascii():
        return False
    if " " not in s:
        return (s.lower() in _ENGLISH_COMMON) and not looks_western(zh)
    if term_type == "person" and _LATIN_PERSON.match(s):
        return False
    syl = _vi_syllables()
    toks = re.findall(r"[A-Za-z]+", s)
    return bool(toks) and any(t.lower() not in syl for t in toks)


def transliteration_suspect(zh: str | None, vi: str | None, term_type: str | None) -> bool:
    """Tên riêng không phải phiên âm/ngoại danh hợp lệ thì đánh dấu để chờ duyệt."""
    if not zh or not vi or term_type not in _HV_TYPES:
        return False
    chars = [ch for ch in zh if _HAN.search(ch)]
    if len(chars) != len(zh) or (vi.isascii() and (len(vi.split()) == 1 or looks_western(zh))):
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
    # Tên Tây nhiều từ ("Simon Elton"): giữ chữ Latin, đừng ép thành "Tây Mông Ai Nhĩ Đốn".
    # Chỉ khi nguồn đúng là phiên âm ngoại — tên Trung viết pinyin ("Long Aotian") vẫn bị
    # bảng tra sửa như cũ.
    if vi.isascii() and looks_western(zh):
        return vi
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
