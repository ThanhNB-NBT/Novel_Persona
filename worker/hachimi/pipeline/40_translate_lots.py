"""Dịch các lô `in_XXXX.jsonl` của gap_batch qua cổng OpenAI-compatible, ghi `out_XXXX.jsonl`.

Khác `38_translate_gateway.py`: con kia lấy chương thẳng từ file nguồn và tự cắt câu; con này
ăn đúng bộ lô đã xuất sẵn nên dùng chung được `39_export_gemini_lots.py gather` và
`score_lots.py`, và chạy xen kẽ được với đường subagent mà không giẫm chân.

BA BẪY CỦA CỔNG 1endpoint (đo 03/09, mất một buổi mới ra):
  1. `stream: true` BẮT BUỘC — không stream thì Cloudflare cắt ở ~125s với 524.
  2. Phải giả User-Agent trình duyệt — UA `python-urllib` bị Cloudflare trả 403 code 1010.
  3. Định dạng phải CÓ ĐÁNH SỐ `n`. Với mảng chuỗi thuần, cả ba model đều rớt dòng
     (43/45, 44/45, 44/45) — rớt một dòng là hỏng cả lô vì không biết rớt dòng nào.
     Đổi sang {"n":..,"vi":..} thì deepseek-v4-pro và gpt-5.6-luna đều ra đủ 45/45.

Đo trên lô 45 câu, cùng văn bản, cùng thước:
    gpt-5.6-luna       khớp 100% · Hán 0% · convert 0,88 · phiên âm 32,3% · 31s  · ~$0,72 cả job
    deepseek-v4-pro    khớp 100% · Hán 0% · convert 1,82 · phiên âm 34,9% · 162s · ~$1,67 cả job
    deepseek-v4-flash  đốt 16k token suy luận, không ra chữ — đừng dùng
    (mốc người dịch: convert 1,86 · phiên âm 38,5%)
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

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

_HAN = re.compile(r"[一-鿿]")
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36")

RULES = """Dịch các câu tiếng Trung sau sang tiếng Việt, văn phong tiểu thuyết huyền huyễn /
võ hiệp / khoa huyễn / kỳ huyễn, giọng cổ phong.

ĐỊNH DẠNG VÀO: mỗi dòng là {"n": số, "zh": "câu Trung"}.
ĐỊNH DẠNG RA: CHỈ một JSON array, mỗi phần tử {"n": <giữ NGUYÊN số của câu nguồn>, "vi": "bản dịch"}.
Phải đủ MỌI số n đã cho, không bỏ sót, không đổi số, không gộp, không tách. Không giải thích gì thêm.

LUẬT DỊCH:
1. LỜI KỂ ngôi ba dùng "hắn" (nam), "nàng" (nữ), "y".
   CẤM: tôi, mình, cậu, bạn, anh ấy, cô ấy, anh ta, cô ta, ông ta, bà ta.
2. LỜI THOẠI: tự xưng "ta", gọi đối phương "ngươi". Mọi thể loại, kể cả tình cảm.
   我 trong thoại LUÔN là "ta", không bao giờ "tôi". 我们 là "chúng ta".
3. TÊN RIÊNG (người, môn phái, công pháp, bảo vật, địa danh): phiên âm Hán-Việt TRỌN CỤM,
   viết hoa từng chữ. 南宫正雄 -> Nam Cung Chính Hùng. 九阳神功 -> Cửu Dương Thần Công.
   飘柳十三式 -> Phiêu Liễu Thập Tam Thức. 奔雷刀法 -> Bôn Lôi Đao Pháp.
   Không dịch nghĩa tên riêng, không pinyin, không giữ chữ Hán.
   Tên gốc phương Tây phiên qua chữ Hán thì trả về dạng Tây: 卡罗尔 -> Carol, 蕾娜 -> Rena.
4. Nguồn KHÔNG có 他/她/我/你 thì bản dịch cũng ĐỪNG thêm chủ ngữ.
   开口说道 -> "Mở miệng nói", không phải "Hắn mở miệng nói".
5. 他 -> "hắn", 她 -> "nàng". Không đảo giới.
6. Văn trôi chảy, KHÔNG calque kiểu convert ("hắn đích cơ nhục cổ động" là sai).
   Nhưng đừng thoát quá: nguồn mấy ý dịch đủ mấy ý, không thêm chữ văn hoa, không gộp câu.
7. Không để lọt chữ Hán/Hàn/Nhật.
8. Nháy cong “ ”, không dùng nháy thẳng.
9. VĂN BẢN HỆ THỐNG (truyện có hệ thống / game). Giữ NGUYÊN VẸN cấu trúc, đừng dịch nhoè
   thành văn xuôi — đây là bảng biểu, không phải câu văn:
   * Giữ đúng ngoặc 【】 và mọi dấu ：, ／, +, -, %, dấu gạch phân cách.
   * Giữ nguyên MỌI con số và tỉ số: 56/100 giữ là 56/100, +10 giữ là +10.
   * Xuống dòng ở đâu thì giữ ở đó, đừng gộp các dòng chỉ số thành một câu.
   * Thuật ngữ cố định, dùng đúng các chữ này:
       系统 -> Hệ thống       宿主 -> Ký chủ        面板 -> bảng
       属性 -> thuộc tính     等级 -> đẳng cấp      经验 -> kinh nghiệm
       熟练度 -> độ thuần thục  任务 -> nhiệm vụ      奖励 -> phần thưởng
       技能 -> kỹ năng        装备 -> trang bị      副本 -> phó bản
       玩家 -> người chơi     升级 -> thăng cấp     解锁 -> mở khoá
   * 叮 khi là tiếng thông báo hệ thống (叮~ / 叮！ / 叮， rồi tới chữ hệ thống) thì dịch
     "Đinh". Còn 叮叮当当 là tiếng chuông hay tiếng kim loại thì dịch "keng keng", KHÁC nhau.

CÁC CÂU CẦN DỊCH:
"""


class HetTien(RuntimeError):
    """Cạn credit. Chạy tiếp chỉ tổ đốt thời gian — mọi lượt sau đều hỏng, mà cổng có thể
    trả 429 khi GẦN cạn nên không dừng thì cả loạt lô bị đánh 'không cứu được' rồi bỏ."""


STOP = threading.Event()


def call(base: str, key: str, model: str, rows: list[dict], timeout: int,
         reasoning_effort: str = "") -> tuple[str, dict]:
    prompt = RULES + "\n".join(json.dumps(r, ensure_ascii=False) for r in rows)
    payload = {"model": model, "max_tokens": 32000, "stream": True,
               "stream_options": {"include_usage": True},
               "messages": [{"role": "user", "content": prompt}]}
    if reasoning_effort:
        payload["reasoning_effort"] = reasoning_effort
    req = urllib.request.Request(
        base.rstrip("/") + "/chat/completions", data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}",
                 "User-Agent": UA})
    try:
        resp_cm = urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:200]
        if exc.code in (402, 403) and ("credit" in detail.lower() or "balance" in detail.lower()):
            raise HetTien(detail) from exc
        raise urllib.error.HTTPError(exc.url, exc.code, detail, exc.headers, None) from None
    parts: list[str] = []
    usage: dict = {}
    with resp_cm as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            pay = line[5:].strip()
            if pay == "[DONE]":
                break
            try:
                ev = json.loads(pay)
            except json.JSONDecodeError:
                continue
            for ch in ev.get("choices") or []:
                parts.append((ch.get("delta") or {}).get("content") or "")
            if ev.get("usage"):
                usage = ev["usage"]
    return "".join(parts), usage


# Vớt từng phần tử khi cả mảng không parse nổi. Đo 03/09: 49 trên ~86 lượt gọi đầu trả
# "0/120" chỉ vì MỘT chỗ hỏng ở giữa làm json.loads chết cả mảng — 119 phần tử kia vẫn dùng
# được. Bỏ cả lô rồi gọi lại là cách đốt credit nhanh nhất, vì lượt hỏng vẫn bị tính tiền
# prompt. Cùng bản chất với `lot_io.py`: cấu trúc còn nguyên thì vá, đừng dịch lại.
_OBJ = re.compile(r'\{\s*"n"\s*:\s*(\d+)\s*,\s*"vi"\s*:\s*"(.*?)"\s*\}(?=\s*[,\]\n]|\s*$)',
                  re.S)


def parse_by_n(text: str) -> dict[int, str]:
    """Ghép theo `n`, KHÔNG theo vị trí — model rớt dòng thì chỉ thiếu, không trượt cả lô."""
    m = re.search(r"\[.*\]", text, re.S)
    if m:
        try:
            rows = json.loads(m.group(0))
        except json.JSONDecodeError:
            rows = None
        if isinstance(rows, list):
            got = {int(o["n"]): str(o.get("vi", "")) for o in rows
                   if isinstance(o, dict) and str(o.get("n", "")).isdigit()}
            if got:
                return got
    return {int(a): b.replace('\\"', '"').replace("\\n", "\n")
            for a, b in _OBJ.findall(text)}


def do_lot(lot: Path, cfg, table) -> str:
    out = lot.parent / lot.name.replace("in_", "out_")
    if out.exists():
        return "co san"
    src = [json.loads(x) for x in lot.open(encoding="utf-8") if x.strip()]
    want = len(src)
    for attempt in range(cfg.retries):
        if STOP.is_set():
            return "dung"
        try:
            text, usage = call(cfg.base_url, cfg.key, cfg.model, src, cfg.timeout,
                               cfg.reasoning_effort)
        except HetTien as exc:
            if not STOP.is_set():
                print(f"  HẾT CREDIT — dừng toàn bộ: {exc}", flush=True)
            STOP.set()
            return "het tien"
        except urllib.error.HTTPError as exc:
            wait = 20 * (attempt + 1) if exc.code in (429, 500, 502, 503, 524) else 5
            print(f"  {lot.name} HTTP {exc.code} — chờ {wait}s", flush=True)
            time.sleep(wait)
            continue
        except Exception as exc:                       # noqa: BLE001
            print(f"  {lot.name} {type(exc).__name__}: {exc}"[:90], flush=True)
            time.sleep(5 * (attempt + 1))
            continue
        by_n = parse_by_n(text)
        # Nới: thiếu vài câu KHÔNG bỏ cả lô. Ghép theo `n` nên câu vắng chỉ là vắng, không
        # đẩy câu nào lệch chỗ. Luật cũ đòi đủ 120/120 làm 4 lô bị bỏ và hàng chục lô phải
        # gọi lại chỉ vì thiếu một câu — mỗi lượt gọi lại là một lần trả tiền prompt.
        if len(by_n) < want and len(by_n) >= want * cfg.min_cover:
            print(f"  {lot.name} nhận thiếu {want - len(by_n)} câu "
                  f"({len(by_n)}/{want})", flush=True)
        elif len(by_n) != want:
            print(f"  {lot.name} {len(by_n)}/{want} dòng — thử lại "
                  f"(out={usage.get('completion_tokens')})", flush=True)
            if cfg.dump:
                cfg.dump.mkdir(parents=True, exist_ok=True)
                (cfg.dump / f"raw_{lot.stem}_{attempt}.txt").write_text(text, encoding="utf-8")
            continue
        keep = [i for i in range(want) if i + 1 in by_n]
        pairs = [(src[i]["zh"], by_n[i + 1]) for i in keep]
        han = sum(1 for _, v in pairs if _HAN.search(v)) / len(pairs)
        rate = cfg.aligned(pairs, table)
        if han > cfg.max_han:
            print(f"  {lot.name} chép nguồn (Hán {han:.0%})", flush=True)
            continue
        if rate < cfg.min_align:
            print(f"  {lot.name} lệch (khớp {rate:.0%})", flush=True)
            continue
        # Ghi sau khi ĐÃ qua cổng: file có mặt nghĩa là dùng được, `gather` khỏi kiểm lại.
        out.write_text("\n".join(
            json.dumps({"n": i + 1, "vi": by_n[i + 1]}, ensure_ascii=False)
            for i in keep) + "\n", encoding="utf-8")
        cfg.tally(usage)
        return f"ok khớp {rate:.0%}"
    return "RỚT"


def main(argv=None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", type=Path,
                    default=Path.home() / "hachimi-work/scratch/gap_batch")
    ap.add_argument("--model", default="gpt-5.6-luna")
    ap.add_argument("--base-url", default="https://console.1endpoint.dev/enfyra/v1")
    ap.add_argument("--key-file", type=Path,
                    default=Path.home() / "hachimi-work/secrets/1endpoint.key")
    ap.add_argument("--reasoning-effort", default="",
                    help="'minimal' cho deepseek-v4-pro; để trống cho gpt-5.6-luna")
    ap.add_argument("--lots", default="", help="dải lô, ví dụ 0-99; để trống = mọi lô chưa có")
    ap.add_argument("--lot-file", type=Path,
                    help="file mỗi dòng một mã lô, chạy THEO ĐÚNG THỨ TỰ trong file — dùng "
                         "khi credit không đủ cả bộ và muốn làm lô giá trị nhất trước")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--min-align", type=float, default=0.85)
    ap.add_argument("--max-han", type=float, default=0.10)
    ap.add_argument("--min-cover", type=float, default=0.95,
                    help="tỉ lệ câu tối thiểu mới nhận lô (mặc định 95%%)")
    ap.add_argument("--dump", type=Path, help="thư mục đổ bản thô khi parse hỏng, để soi")
    args = ap.parse_args(argv)
    args.key = args.key_file.read_text().strip()

    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "gw", Path(__file__).with_name("38_translate_gateway.py"))
    gw = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gw)
    args.aligned = gw.aligned_rate
    from novelworker.translator import hanviet
    table = hanviet._load()

    lots = sorted(args.dir.glob("in_*.jsonl"))
    if args.lots:
        lo, hi = (int(x) for x in args.lots.split("-"))
        lots = [p for p in lots if lo <= int(p.stem[3:]) <= hi]
    if args.lot_file:
        thu_tu = [x.strip() for x in args.lot_file.read_text().split() if x.strip()]
        co = {p.stem[3:]: p for p in lots}
        lots = [co[k] for k in thu_tu if k in co]
    todo = [p for p in lots if not (p.parent / p.name.replace("in_", "out_")).exists()]
    print(f"{len(todo)} lô cần dịch · model {args.model} · {args.workers} luồng", flush=True)

    lock = threading.Lock()
    stats = {"ok": 0, "rot": 0, "in": 0, "out": 0}

    def tally(usage):
        with lock:
            stats["in"] += usage.get("prompt_tokens") or 0
            stats["out"] += usage.get("completion_tokens") or 0
    args.tally = tally

    def work(lot: Path) -> None:
        if STOP.is_set():
            return
        r = do_lot(lot, args, table)
        with lock:
            if r.startswith("ok"):
                stats["ok"] += 1
            elif r == "RỚT":
                stats["rot"] += 1
            if r.startswith("ok") and stats["ok"] % 10 == 0:
                print(f"  {stats['ok']}/{len(todo)} lô · "
                      f"{stats['in']:,} vào + {stats['out']:,} ra", flush=True)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(work, todo))
    print(f"\nxong {stats['ok']} lô · rớt {stats['rot']} · "
          f"token {stats['in']:,} vào + {stats['out']:,} ra", flush=True)


if __name__ == "__main__":
    main()
