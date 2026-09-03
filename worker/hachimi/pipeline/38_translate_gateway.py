"""Dịch hàng loạt zh→vi qua cổng OpenAI-compatible, có kiểm khớp NỘI DUNG và chạy tiếp được.

Vì sao không dùng `eval/gateway_client.py`: script đó nói chuẩn Anthropic `/v1/messages` với
cổng nghimmo (khoá đã hết hạn), và tin vào số dòng model trả về. Bản này nói chuẩn OpenAI,
đổi cổng chỉ cần `--base-url`, và **không tin bất cứ dấu hiệu hình thức nào**.

BA KIỂU HỎNG ĐÃ ĐO ĐƯỢC (01-02/09), cả ba đều QUA mọi phép kiểm hình thức:

1. **Chép nguyên nguồn** — trả đủ N dòng, JSON hợp lệ, thứ tự đúng, nhưng là tiếng Trung
   (stali `req/claude-fable-5` lô 300; deepseek-v4-pro lô 30 và 120).
2. **Rơi dòng giữa chừng** — trả N−1 dòng, mọi dòng sau điểm rơi bị TRƯỢT một vị trí. Đếm
   dòng không thấy gì bất thường ngoài con số lệch 1.
3. **Tự đánh lại số thứ tự** — bắt model trả `{"n":…}` thì nó đánh `n` = 1..N theo thứ tự nó
   sinh, không giữ số của câu nguồn. Đo lô 300: đủ 299 số, khớp nội dung chỉ 54%.

⇒ Cổng DUY NHẤT tin được là **đối chiếu âm Hán-Việt giữa `zh` và `vi`** (`aligned_rate`).
Lô nào dưới `--min-align` thì gọi lại CẢ LÔ, đổi model, cuối cùng mới chia đôi. Không bao giờ
vá từng dòng — vá lẻ là đúng cách đẻ ra lệch dòng của lượt prose 401 lô.

Model: đo trên 45-60 câu (mẫu nhỏ, chênh lệch phần lớn là nhiễu):

| model | khớp | phiên âm | convert/1k |
|---|---|---|---|
| `deepseek-v4-flash` | 44/45 | 34,1% | **1,88** |
| `deepseek/deepseek-v4-pro` | 43/45 | **38,7%** | 0,95 |
| *mốc người dịch* | — | *38,5%* | *1,86* |

flash viết tiếng Việt tự nhiên hơn, pro bám chữ Hán hơn và nhanh gấp 2,6.

⚠ **`pro` đứng TRƯỚC** — bảng trên là lô 45 câu, và chốt theo nó thì SAI. Chạy thật trên
chương dài (49-66 câu) thì `flash` hỏng số dòng gần như mọi lô, mỗi lượt phí ~180 giây rồi
mới rơi sang `pro`; đo được 2 chương/35 phút ⇒ 45 chương mất ~11 giờ. Đảo lại còn ~3 giờ.
Bài học: đừng chốt chuỗi model bằng mẫu 45 câu, phải đo trên văn thật.

Đã loại: `glm-5.3` (agentrouter) — 565 giây cho 45 câu rồi vẫn hỏng parse, chậm gấp 8 lần
`pro`. Nhóm Claude/GPT của agentrouter trả 402 hết quota dù trang hiện số dư $175.

    python 38_translate_gateway.py --chapters 45 --out ~/hachimi-work/scratch/crawl_vi.jsonl
    python 38_translate_gateway.py --self-check
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(HERE.parents[0]))          # worker/ để import novelworker

DEFAULT_BASE = "https://api.vilao.ai/v1"
DEFAULT_KEY = Path.home() / "hachimi-work/secrets/vilao.key"
DEFAULT_MODELS = "deepseek/deepseek-v4-pro,deepseek-v4-flash"
_HAN = re.compile(r"[一-鿿]")
_WORD = re.compile(r"[a-zà-ỹđ]+", re.IGNORECASE)
_SENT = re.compile(r"(?<=[。！？”])")

RULES = """Dịch các câu tiếng Trung sau sang tiếng Việt, văn phong tiểu thuyết tiên hiệp/huyền huyễn.

QUY TẮC QUAN TRỌNG NHẤT — giữ Hán-Việt CÓ CHỌN LỌC, không rải đều:

GIỮ nguyên âm Hán-Việt (viết hoa từng chữ nếu là tên riêng):
  · Tên người, môn phái, công pháp, bảo vật, địa danh: 南宫正雄 → Nam Cung Chính Hùng
  · Thuật ngữ tu tiên / tu luyện: 仙族 → Tiên tộc · 元婴 → Nguyên Anh · 金丹 → Kim Đan
  · Xưng hô cổ phong: 前辈 → tiền bối · 道友 → đạo hữu

DỊCH RA NGHĨA (KHÔNG phiên âm) — danh từ chung, động từ, tính từ đời thường:
  · 小熊猫 → "gấu trúc đỏ", KHÔNG phải "tiểu hùng miêu"
  · 脖子 → "cổ", KHÔNG phải "bột tử"
  · 头痛 → "đau đầu", KHÔNG phải "đầu thống"
Hỏi: người Việt đọc truyện tiên hiệp có dùng từ đó không? Có thì giữ, không thì dịch nghĩa.

TRẬT TỰ TỪ — phải viết lại theo tiếng Việt, CẤM bê nguyên cấu trúc Trung:
  Sai : "Vương Dược hơi đau đầu rất nhanh phát hiện bản thân đang ở một nơi xa lạ"
  Đúng: "Vương Dược đang hơi đau đầu thì nhanh chóng phát hiện mình đang ở một nơi xa lạ"

CÁC LUẬT KHÁC:
1. LỜI KỂ ngôi ba dùng "hắn" (nam), "nàng" (nữ), "y". CẤM: tôi, mình, cậu, bạn, anh ấy, cô ấy, anh ta, cô ta.
2. LỜI THOẠI: nhân vật tự xưng "ta", gọi đối phương "ngươi". Mọi thể loại, không ngoại lệ.
3. Nguồn KHÔNG có chủ ngữ thì bản dịch cũng ĐỪNG thêm chủ ngữ.
4. 他 → "hắn", 她 → "nàng". Không đảo giới.
5. Mỗi câu nguồn ra ĐÚNG một dòng dịch. Không gộp, không tách, không bỏ sót.
6. Không để lọt chữ Hán/Hàn/Nhật.
7. Nháy cong “ ”, không dùng nháy thẳng.

CHỈ trả về JSON array các chuỗi, không giải thích. Ví dụ: ["câu 1","câu 2"]

CÁC CÂU CẦN DỊCH:
"""


def split_sentences(text: str, lo: int = 8, hi: int = 120) -> list[str]:
    """Chương → câu, cắt theo `。！？”` — ĐÚNG cách production chia câu."""
    body = re.sub(r"\s+", "", text or "")
    return [s.strip() for s in _SENT.split(body) if lo <= len(s.strip()) <= hi]


def _readings(zh: str, table: dict) -> set[str]:
    out: set[str] = set()
    for ch in zh:
        for r in table.get(ch) or ():
            out.add(r.lower())
    return out


def aligned_rate(pairs, table) -> float:
    """Tỉ lệ câu KHÔNG bị lệch vị trí. Đo bằng so sánh TƯƠNG ĐỐI với câu hàng xóm.

    Bản đầu đếm "bản dịch có chứa ≥2 âm Hán-Việt của chính câu nguồn không". Cách đó **phạt
    đúng cái hành vi đúng**: chương huyền huyễn kiểu Tây có `卡罗尔`/`蕾娜`/`内森` là tên Tây
    phiên âm sang chữ Hán, dịch đúng phải ra Carol/Rena/Nathan chứ không phải Tạp La Nhĩ —
    nên không chia sẻ âm nào với nguồn. Đo 02/09: cả hai model đều bị chặn ở đúng 75% suốt 10
    lô liền của một chương như vậy, trong khi bản dịch không hề sai.

    Lỗi cần bắt là **LỆCH VỊ TRÍ** (dòng i thực ra là bản dịch của câu i±k), không phải "dịch
    thoát". Nên chấm tương đối: dòng i chỉ tính là lệch khi nó khớp với câu HÀNG XÓM **hơn
    hẳn** khớp với câu của chính nó. Bản dịch thoát nghĩa thì điểm thấp đều ở mọi vị trí ⇒
    không bị kết tội; bản bị trượt thì điểm ở hàng xóm vọt lên ⇒ lộ ngay.
    """
    srcs = [zh for zh, _ in pairs]
    reads = [_readings(zh, table) for zh in srcs]
    good = judged = 0
    for i, (_, vi) in enumerate(pairs):
        if not vi or len(reads[i]) < 3:
            continue
        words = {w.lower() for w in _WORD.findall(vi)}
        judged_now = True                       # noqa: F841 - giữ mạch đọc
        if not words:
            # Không một chữ Latin nào ⇒ bản CHÉP NGUYÊN NGUỒN. Phải tính là hỏng: phép so
            # tương đối bên dưới sẽ cho own=0 và best_other=0 ⇒ `0 >= 0` ⇒ hoá ra "đạt".
            # Bản thước đầu bắt được ca này, bản viết lại làm mất — và self-check cũng bỏ
            # luôn đối chứng đó nên không ai thấy. Đo 02/09: DeepSeek chính hãng tắt suy
            # luận thì chép nguyên 45/45 dòng tiếng Trung mà `aligned_rate` chấm 100%.
            judged += 1
            continue
        own = len(reads[i] & words)
        best_other = max((len(reads[j] & words)
                          for j in (i - 2, i - 1, i + 1, i + 2)
                          if 0 <= j < len(pairs) and len(reads[j]) >= 3), default=0)
        judged += 1
        if own >= best_other:
            good += 1
    return good / judged if judged else 1.0


class OutOfMoney(RuntimeError):
    """Ví cạn. Chạy tiếp chỉ tổ đốt thời gian: mọi lượt sau đều 402, mà cổng lại trả 429 khi
    ví GẦN cạn — nên không dừng thì cả trăm chương bị đánh 'không cứu được' rồi bỏ luôn.
    Đây chính là cách 409 chương biến mất hôm 01/09."""


STOP = threading.Event()


def call(base: str, key: str, model: str, sentences: list[str], timeout: int,
         reasoning_effort: str = "") -> str:
    """`reasoning_effort` là cách DUY NHẤT gọi được DeepSeek chính hãng. Đừng tắt suy luận.

    Đo 02/09 trên lô 45 câu, gọi thẳng api.deepseek.com. Bản `flash` KHÔNG dùng được —
    9 biến thể, hai kiểu hỏng, không có vùng ở giữa:

    | cấu hình (flash) | kết quả |
    |---|---|
    | `thinking: disabled` (± temp 1,0/1,3, ± system msg) | **chép nguyên văn Trung** |
    | `reasoning_effort` none / minimal / low | **chép nguyên văn Trung** |
    | suy luận BẬT, trần 16k / 32k / effort high | 254-276s, `fin=length`, **content rỗng** |

    Tắt suy luận thì nó không tự khởi động được việc dịch; bật thì nghĩ hết 32.000 token
    mà chưa viết nổi một dòng. Nâng trần chỉ đốt thêm tiền — 16k và 32k cùng cụt.

    Con chạy được là **`deepseek-v4-pro` + `reasoning_effort: minimal`**: 43s, 2.620 token ra,
    khớp 100% · Hán 0% · phiên âm 37,8% · convert 1,86/1k — trúng đúng mốc người dịch (1,86).

    ⚠ Cổng bán lại vilao chạy `flash` ngon lành (khớp 96%) vì đã có lớp cấu hình riêng ở giữa.
    Cùng tên model, hành vi khác hẳn — nên tham số này chỉ gửi khi được yêu cầu, cổng khác
    có thể trả 400 vì trường lạ.
    """
    payload = {
        "model": model, "stream": True, "max_tokens": 32000,
        "messages": [{"role": "user",
                      "content": RULES + json.dumps(sentences, ensure_ascii=False)}],
    }
    if reasoning_effort:
        payload["reasoning_effort"] = reasoning_effort
    body = json.dumps(payload).encode()
    req = urllib.request.Request(base.rstrip("/") + "/chat/completions", data=body, headers={
        "Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    parts: list[str] = []
    try:
        resp_cm = urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:200]
        if exc.code == 402 or "nsufficient" in detail:
            raise OutOfMoney(detail) from exc
        raise
    with resp_cm as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            try:
                event = json.loads(payload)
            except json.JSONDecodeError:
                continue
            for choice in event.get("choices") or []:
                parts.append((choice.get("delta") or {}).get("content") or "")
    return "".join(parts)


def parse_rows(text: str, want: int) -> list[str] | None:
    match = re.search(r"\[.*\]", text, re.S)
    if not match:
        return None
    try:
        rows = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None
    if not isinstance(rows, list) or len(rows) != want:
        return None
    return [str(x) for x in rows]


def translate_batch(sentences: list[str], cfg, table, depth: int = 0) -> list[str] | None:
    """Trả list cùng độ dài, hoặc None. Rớt thì đổi model, cuối cùng mới CHIA ĐÔI.

    Chia đôi chứ không vá từng dòng: vá lẻ là cách chắc chắn nhất để lệch dòng.
    """
    for model in cfg.models:
        for attempt in range(cfg.retries):
            if STOP.is_set():
                return None
            try:
                text = call(cfg.base_url, cfg.key, model, sentences, cfg.timeout,
                            cfg.reasoning_effort)
            except OutOfMoney as exc:
                if not STOP.is_set():
                    print(f"      HẾT TIỀN — dừng toàn bộ: {exc}", flush=True)
                STOP.set()
                return None
            except urllib.error.HTTPError as exc:
                # In MÃ chứ không chỉ tên lớp: 02/09 cả một lượt chạy hiện "lỗi: HTTPError"
                # suốt mà không ai biết đó là 503 nghẽn máy chủ (đáng chờ) hay 400 sai tham
                # số (chờ vô ích). 429/503 là nghẽn tạm — lùi lâu, đừng bỏ chương.
                wait = 20 * (attempt + 1) if exc.code in (429, 500, 502, 503) else 5
                print(f"      {model} HTTP {exc.code} — chờ {wait}s", flush=True)
                time.sleep(wait)
                continue
            except Exception as exc:                   # noqa: BLE001
                print(f"      {model} lỗi: {type(exc).__name__}: {exc}"[:90], flush=True)
                time.sleep(5 * (attempt + 1))
                continue
            rows = parse_rows(text, len(sentences))
            if rows is None:
                print(f"      {model} parse/đếm hỏng", flush=True)
                continue
            han = sum(1 for r in rows if _HAN.search(r)) / len(rows)
            rate = aligned_rate(list(zip(sentences, rows)), table)
            if han > cfg.max_han:
                print(f"      {model} chép nguồn (Hán {han:.0%})", flush=True)
                continue
            if rate < cfg.min_align:
                print(f"      {model} lệch (khớp {rate:.0%})", flush=True)
                continue
            return rows
    if depth < cfg.max_split and len(sentences) > 4:
        mid = len(sentences) // 2
        print(f"      chia đôi {len(sentences)} → {mid}+{len(sentences)-mid}", flush=True)
        left = translate_batch(sentences[:mid], cfg, table, depth + 1)
        right = translate_batch(sentences[mid:], cfg, table, depth + 1)
        if left is not None and right is not None:
            return left + right
    return None


# Thể loại kaihe gần như KHÔNG có (đo 01/09, lần/10k chữ): võ hiệp 0,1 · khoa huyễn 0,0 ·
# kỳ huyễn 0,1 · huyền huyễn 1,7. Đây là chỗ crawl bù được, 61 truyện / 1.194 chương.
GENRES = {
    "huyen huyen": "斗气|魔法|武魂|神格|魔兽|斗罗|异界|魔法师",
    "vo hiep": "江湖|武林|内功|剑法|门派|侠客|轻功",
    "khoa huyen": "星际|机甲|星球|飞船|联邦|虫族|基因|太空",
    "ky huyen": "精灵|矮人|龙骑|骑士团|城堡|公爵|魔王|勇者",
    "tien hiep": "修炼|元婴|金丹|筑基|灵气|真气|法宝",
    "game": "副本|玩家|技能|装备|公会|升级|经验值",
    "do thi": "公司|手机|警察|医院|老板|总裁|汽车|电话",
    "huyen nghi": "诡异|恐怖|尸体|鬼魂|凶手|命案|灵异|诅咒",
    "lich su": "皇上|朝廷|陛下|太子|将军|王爷|娘娘|丞相",
}
GAP_GENRES = ("huyen huyen", "vo hiep", "khoa huyen", "ky huyen")


def pick_novels(path: Path, genres: tuple[str, ...]) -> set[int]:
    """Truyện có thể loại TRỘI NHẤT nằm trong `genres`, đếm theo mật độ từ khoá trên cả truyện.

    Gán nhãn cho cả TRUYỆN chứ không từng chương: một chương lẻ có thể không chứa từ khoá nào
    của thể loại chính, gán theo chương sẽ vụn và sai.
    """
    pats = {k: re.compile(v) for k, v in GENRES.items()}
    hits: dict[int, dict[str, int]] = {}
    for line in path.open(encoding="utf-8"):
        if not line.strip():
            continue
        row = json.loads(line)
        bag = hits.setdefault(row["novel_id"], dict.fromkeys(GENRES, 0))
        zh = row.get("zh") or ""
        for name, pat in pats.items():
            bag[name] += len(pat.findall(zh))
    out = set()
    for novel_id, bag in hits.items():
        best, score = max(bag.items(), key=lambda kv: kv[1])
        if score > 0 and best in genres:
            out.add(novel_id)
    return out


def load_chapters(path: Path, limit: int | None, novels: set[int] | None) -> list[dict]:
    out: list[dict] = []
    for line in path.open(encoding="utf-8"):
        if not line.strip():
            continue
        row = json.loads(line)
        if novels is not None and row.get("novel_id") not in novels:
            continue
        out.append(row)
        if limit and len(out) >= limit:
            break
    return out


def build(args) -> dict:
    from novelworker.translator import hanviet

    table = hanviet._load()
    args.key = Path(args.key_file).read_text(encoding="utf-8").strip()
    args.models = [m.strip() for m in args.models.split(",") if m.strip()]

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    done: set[tuple] = set()
    if out_path.exists() and args.resume:
        for line in out_path.open(encoding="utf-8"):
            if line.strip():
                row = json.loads(line)
                done.add((row["novel_id"], row["chapter_index"]))
        print(f"Chạy tiếp: đã có {len(done)} chương", flush=True)

    novels = None
    if args.gap_genres:
        novels = pick_novels(Path(args.chapters_file), GAP_GENRES)
        print(f"Lọc {len(novels)} truyện thuộc 4 thể loại kaihe thiếu", flush=True)
    chapters = [c for c in load_chapters(Path(args.chapters_file), args.chapters or None, novels)
                if (c.get("novel_id"), c.get("chapter_index")) not in done]
    # `--reverse` để chạy THÊM một tiến trình nữa mà không đụng hàng: bản xuôi và bản ngược
    # gặp nhau ở giữa. `--resume` chỉ đọc file lúc khởi động nên hai bản chạy cùng lúc trên
    # cùng thứ tự sẽ dịch trùng y hệt — tốn tiền và đẻ dòng lặp. Ghi ra file RIÊNG rồi gộp,
    # khử trùng theo (novel_id, chapter_index); phần chồng lấn chỉ ở khúc giữa.
    # `--shard i/n` chia sạch hơn `--reverse`: mỗi tiến trình nhận đúng một lớp đồng dư, không
    # chồng lấn chút nào. `--reverse` chỉ tách được HAI hướng và vẫn đụng nhau ở khúc giữa.
    if args.shard:
        i, n = (int(x) for x in args.shard.split("/"))
        chapters = [c for k, c in enumerate(chapters) if k % n == i]
    if args.reverse:
        chapters.reverse()
    print(f"{len(chapters)} chương vào hàng đợi · {args.workers} luồng"
          f"{' · NGƯỢC' if args.reverse else ''}"
          f"{' · shard ' + args.shard if args.shard else ''}", flush=True)
    if STOP.is_set():
        STOP.clear()
    stats = {"chapters": 0, "skipped": len(done), "sentences": 0, "failed_batches": 0}

    # Chạy tuần tự thì cổng rảnh gần như hoàn toàn: đo 02/09 được 7,4 phút/chương ⇒ 1.254
    # chương mất ~155 giờ. Mà cổng cho 5.000 lượt/phút, nên nút thắt là do MÌNH chỉ dùng một
    # luồng. Một chương = một đơn vị việc (đủ nhỏ để chia đều, đủ lớn để khỏi tranh khoá).
    lock = threading.Lock()
    handle = out_path.open("a", encoding="utf-8")

    def work(chapter: dict) -> None:
        if STOP.is_set():
            return
        key = (chapter.get("novel_id"), chapter.get("chapter_index"))
        sentences = split_sentences(chapter.get("zh", ""))
        if not sentences:
            return
        rows: list[str] = []
        for i in range(0, len(sentences), args.batch):
            got = translate_batch(sentences[i:i + args.batch], args, table)
            if got is None:
                with lock:
                    if STOP.is_set():
                        return
                    stats["failed_batches"] += 1
                    print(f"    BỎ chương {key} (một lô không cứu được)", flush=True)
                return
            rows.extend(got)
        # Ghi dưới lock và flush ngay: đứt ngang vẫn resume được, và không xen dòng giữa luồng.
        with lock:
            for n, (zh, vi) in enumerate(zip(sentences, rows), 1):
                handle.write(json.dumps(
                    {"novel_id": key[0], "chapter_index": key[1], "n": n, "zh": zh, "vi": vi},
                    ensure_ascii=False) + "\n")
            handle.flush()
            stats["chapters"] += 1
            stats["sentences"] += len(rows)
            if stats["chapters"] % 10 == 0:
                print(f"  {stats['chapters']}/{len(chapters)} chương · "
                      f"{stats['sentences']:,} câu", flush=True)

    try:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            list(pool.map(work, chapters))
    finally:
        handle.close()
    Path(str(out_path) + ".manifest.json").write_text(
        json.dumps({**stats, "models": args.models, "batch": args.batch,
                    "min_align": args.min_align, "base_url": args.base_url},
                   ensure_ascii=False, indent=2), encoding="utf-8")
    return stats


def _self_check() -> None:
    from novelworker.translator import hanviet

    table = hanviet._load()
    assert split_sentences("甲乙丙丁戊己庚辛。壬癸子丑寅卯辰巳。") == [
        "甲乙丙丁戊己庚辛。", "壬癸子丑寅卯辰巳。"]

    zh1, zh2 = "南宫正雄大笑三声", "叶紫芸转身离去"
    vi1, vi2 = "Nam Cung Chính Hùng cười lớn ba tiếng", "Diệp Tử Vân xoay người rời đi"
    assert aligned_rate([(zh1, vi1), (zh2, vi2)], table) == 1.0, "khớp đúng mà báo lệch"
    # ĐỐI CHỨNG ÂM: đảo hai bản dịch cho nhau ⇒ phải phát hiện
    assert aligned_rate([(zh1, vi2), (zh2, vi1)], table) == 0.0, "không bắt được lệch vị trí"
    # Dịch THOÁT (tên Tây phiên âm sang chữ Hán) KHÔNG được coi là lệch — đây là ca
    # làm hỏng bản thước đầu tiên.
    free = [("卡罗尔大吼一声", "Carol hét lớn một tiếng"),
            ("蕾娜双腿一夹马腹", "Rena kẹp chân vào bụng ngựa")]
    assert aligned_rate(free, table) == 1.0, "phạt oan bản dịch tên Tây"
    # ĐỐI CHỨNG ÂM (đã mất một lần khi viết lại thước, làm lọt ca chép nguồn):
    echoed = [(zh1, zh1), (zh2, zh2)]
    assert aligned_rate(echoed, table) == 0.0, "không bắt được bản chép nguyên nguồn"
    # câu quá ngắn (ít âm tra được) thì bỏ qua, không phán bừa
    assert aligned_rate([("好。", "Được.")], table) == 1.0, "phán bừa trên câu quá ngắn"

    # pick_novels: truyện toàn từ khoá võ hiệp phải lọt, truyện tiên hiệp thì không
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / "c.jsonl"
        f.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in [
            {"novel_id": 1, "chapter_index": 1, "zh": "江湖武林内功剑法门派"},
            {"novel_id": 2, "chapter_index": 1, "zh": "修炼元婴金丹筑基灵气"},
        ]), encoding="utf-8")
        assert pick_novels(f, GAP_GENRES) == {1}, pick_novels(f, GAP_GENRES)

    assert parse_rows('["a","b"]', 2) == ["a", "b"]
    assert parse_rows('["a"]', 2) is None, "lệch số dòng mà vẫn nhận"
    assert parse_rows("hỏng", 2) is None
    print("self-check OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--chapters-file", type=Path,
                    default=Path.home() / "hachimi-work/scratch/zh_raw_v7.jsonl")
    ap.add_argument("--out", type=Path,
                    default=Path.home() / "hachimi-work/scratch/crawl_vi.jsonl")
    ap.add_argument("--chapters", type=int, default=45, help="số chương lấy (0 = hết)")
    ap.add_argument("--reasoning-effort", default="",
                    help="minimal|low|high — BẮT BUỘC 'minimal' với api.deepseek.com + pro; "
                         "để trống với cổng bán lại")
    ap.add_argument("--shard", help="i/n — chỉ lấy chương có chỉ số ≡ i (mod n); chia cho "
                                    "nhiều tiến trình chạy song song, không chồng lấn")
    ap.add_argument("--reverse", action="store_true",
                    help="duyệt chương từ cuối lên — để chạy song song một tiến trình thứ hai")
    ap.add_argument("--workers", type=int, default=8,
                    help="số luồng song song; cổng cho 5.000 lượt/phút nên tuần tự là phí")
    ap.add_argument("--gap-genres", action="store_true",
                    help="chỉ lấy truyện thuộc 4 thể loại kaihe gần như không có")
    ap.add_argument("--batch", type=int, default=45, help="số câu mỗi lượt gọi")
    ap.add_argument("--base-url", default=DEFAULT_BASE)
    ap.add_argument("--key-file", type=Path, default=DEFAULT_KEY)
    ap.add_argument("--models", default=DEFAULT_MODELS, help="chuỗi dự phòng, ngăn bằng dấu phẩy")
    ap.add_argument("--min-align", type=float, default=0.85,
                    help="tỉ lệ khớp nội dung tối thiểu; dưới ngưỡng là gọi lại CẢ LÔ")
    ap.add_argument("--max-han", type=float, default=0.10,
                    help="tỉ lệ dòng còn chữ Hán tối đa (bắt lỗi chép nguyên nguồn)")
    ap.add_argument("--retries", type=int, default=4)
    ap.add_argument("--max-split", type=int, default=2)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--no-resume", dest="resume", action="store_false")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)

    if args.self_check:
        _self_check()
        return
    print(json.dumps(build(args), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
