#!/usr/bin/env python3
"""Gọi một cổng API tương thích Anthropic (`/v1/messages`) để dịch — CÁCH LY.

Vì sao tách hẳn khỏi `novelworker`: cổng bán lại nhìn thấy nguyên văn mọi thứ gửi lên.
Script này chỉ đọc đúng file dữ liệu được chỉ định và file khoá; nó KHÔNG import config
của worker, KHÔNG đọc `.env`, KHÔNG đụng `~/.claude/settings.json`. Đổi nhà cung cấp =
sửa `--base-url`, không sửa gì khác.

Khoá đọc theo thứ tự: --key-file > $GATEWAY_API_KEY > ~/hachimi-work/secrets/gateway.key
Đừng truyền khoá qua tham số dòng lệnh — nó nằm lại trong lịch sử shell và `ps`.

Mỗi request ghi một dòng vào log JSONL: model xin, model cổng trả về, độ trễ, usage,
token/s. Cổng rẻ có thể ĐỔI MODEL giữa chừng mà không báo; log này là cách duy nhất
nhìn thấy chuyện đó.

    # thử kết nối
    python gateway_client.py --ping
    # chạy bài kiểm 60 câu
    python gateway_client.py --probe --label nghimmo-opus5
    # dịch lô jsonl (thơ / văn xuôi), tiếp tục được sau khi dừng
    python gateway_client.py --batch-in ~/hachimi-work/scratch/prose_batch \
        --field zh --chunk 40
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

DEFAULT_BASE = "https://api.nghimmo.com"
DEFAULT_MODEL = "nghi/claude-opus-5"
DEFAULT_KEY_FILE = Path.home() / "hachimi-work/secrets/gateway.key"
SCRATCH = Path.home() / "hachimi-work/scratch"
LOG_PATH = SCRATCH / "gateway_calls.jsonl"

_log_lock = threading.Lock()
_spent = 0          # token đã tiêu (in + out), cộng dồn cả những lần chạy trước
_budget = 0         # 0 = không giới hạn


_moc_request: list[float] = []   # mốc thời gian các request gần đây, để giữ trần req/phút


def _cho_den_luot(cfg) -> None:
    """Trần req/phút của cổng. Tự phanh còn hơn ăn 429 rồi backoff mù."""
    rpm = getattr(cfg, "rpm", 0)
    if not rpm:
        return
    while True:
        with _log_lock:
            now = time.monotonic()
            _moc_request[:] = [t for t in _moc_request if now - t < 60]
            if len(_moc_request) < rpm:
                _moc_request.append(now)
                return
            nghi = 60 - (now - _moc_request[0]) + 0.05
        time.sleep(max(0.05, nghi))


class BudgetHet(Exception):
    """Hết ngân sách — dừng SẠCH chứ không để job chạy tiếp rồi lỗi 402 hàng loạt."""


def doc_da_tieu() -> int:
    """Cộng lại từ log: gói token là của cả đời khoá, không phải của một lần chạy."""
    if not LOG_PATH.exists():
        return 0
    total = 0
    for line in LOG_PATH.read_text(encoding="utf-8").splitlines():
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        total += (rec.get("in_tok") or 0) + (rec.get("out_tok") or 0)
    return total

RULES = """===== LUẬT DỊCH (bắt buộc) =====

VĂN PHONG: tiểu thuyết tiên hiệp/huyền huyễn, giọng cổ phong.

1. XƯNG HÔ TRONG LỜI KỂ (ngôi ba): dùng "hắn" (nam), "nàng" (nữ), "y".
   TUYỆT ĐỐI CẤM: tôi, mình, cậu, bạn, anh ấy, cô ấy, anh ta, cô ta, ông ta, bà ta.

2. XƯNG HÔ TRONG LỜI THOẠI: nhân vật tự xưng "ta", gọi đối phương "ngươi".
   Áp dụng cho MỌI thể loại, kể cả tình cảm — không dùng anh/em.

3. TÊN RIÊNG: phiên âm Hán-Việt TRỌN CỤM, viết hoa từng chữ.
   南宫正雄  -> Nam Cung Chính Hùng     (KHÔNG phải "Nông Cung Chính Hùng")
   黄礼严    -> Hoàng Lễ Nghiêm
   九阳神功  -> Cửu Dương Thần Công
   Không dịch nghĩa tên riêng. Không dùng pinyin. Không giữ nguyên chữ Hán.

4. LƯỢC CHỦ NGỮ: nếu dòng nguồn KHÔNG có chủ ngữ (không có 他/她/我/你),
   thì bản dịch cũng ĐỪNG tự thêm chủ ngữ.
   开口说道：“你来了。”  ->  Mở miệng nói: "Ngươi đến rồi."

5. GIỚI TÍNH: nguồn ghi 他 thì dịch "hắn", 她 thì dịch "nàng". Không đảo.

6. VĂN PHẢI TRÔI CHẢY, không dịch máy móc từng chữ theo kiểu "convert".

7. Không bỏ sót ý, không thêm ý không có trong nguồn.

===== HẾT LUẬT ====="""

TASK = """Dịch {count} câu tiếng Trung dưới đây sang tiếng Việt.

TRẢ VỀ: đúng {count} dòng, mỗi dòng dạng `<số>. <bản dịch>`.
Không kèm nguyên văn tiếng Trung, không tiêu đề, không lời bình, không đánh dấu markdown.

{rules}

===== NGUỒN =====
{body}"""


def read_key(explicit: Path | None) -> str:
    for path in (explicit, DEFAULT_KEY_FILE):
        if path and path.is_file():
            return path.read_text(encoding="utf-8").strip()
    env = os.environ.get("GATEWAY_API_KEY", "").strip()
    if env:
        return env
    raise SystemExit(f"Không tìm thấy khoá: {DEFAULT_KEY_FILE} hoặc $GATEWAY_API_KEY")


def log_call(rec: dict) -> None:
    with _log_lock, LOG_PATH.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")


def call(cfg, prompt: str, tag: str) -> str:
    """Một request tới /v1/messages. Trả về text; ghi log nhận dạng model + tốc độ."""
    global _spent
    _cho_den_luot(cfg)
    payload = {
        "model": cfg.model,
        "max_tokens": cfg.max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    url = cfg.base_url.rstrip("/") + "/v1/messages"
    last = ""
    if _budget:
        with _log_lock:
            if _spent >= _budget:
                raise BudgetHet(f"đã tiêu {_spent:,}/{_budget:,} token")
    for attempt in range(cfg.retries + 1):
        req = urllib.request.Request(url, data=body, method="POST", headers={
            "x-api-key": cfg.api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        })
        started = time.monotonic()
        try:
            with urllib.request.urlopen(req, timeout=cfg.timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:300]
            last = f"HTTP {exc.code}: {detail}"
            log_call({"tag": tag, "attempt": attempt, "error": last,
                      "sec": round(time.monotonic() - started, 2)})
            if exc.code in (408, 409, 429) or exc.code >= 500:
                time.sleep(min(30, 2 ** attempt))
                continue
            raise SystemExit(f"[{tag}] {last}")
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last = f"{type(exc).__name__}: {exc}"
            log_call({"tag": tag, "attempt": attempt, "error": last,
                      "sec": round(time.monotonic() - started, 2)})
            if isinstance(exc, TimeoutError | urllib.error.URLError):
                # Timeout = lô QUÁ TO, không phải trục trặc nhất thời. Thử lại cùng cỡ
                # là timeout tiếp, tốn thêm nguyên một chu kỳ. Trả rỗng để tầng trên
                # chia đôi — nhỏ hơn thì chạy kịp.
                break
            time.sleep(min(30, 2 ** attempt))
            continue

        sec = time.monotonic() - started
        usage = data.get("usage") or {}
        out_tok = usage.get("output_tokens") or 0
        with _log_lock:
            _spent += (usage.get("input_tokens") or 0) + out_tok
        log_call({
            "tag": tag,
            "model_xin": cfg.model,
            "model_tra_ve": data.get("model"),
            "stop_reason": data.get("stop_reason"),
            "sec": round(sec, 2),
            "in_tok": usage.get("input_tokens"),
            "out_tok": out_tok,
            "tok_s": round(out_tok / sec, 1) if sec > 0 else None,
            # cổng cắt ở ~600s và trả về rỗng mà không báo lỗi — đánh dấu để đếm được
            "nghi_bi_cat": sec > 500 and out_tok < 50,
        })
        parts = [b.get("text", "") for b in data.get("content", []) if b.get("type") == "text"]
        return "".join(parts)
    # Hết lượt thử thì TRẢ RỖNG, đừng SystemExit: trong thread nó làm sập cả job và
    # mất mọi lô đang dở. Rỗng để tầng trên chia đôi lô rồi thử lại — nhỏ hơn thì qua.
    log_call({"tag": tag, "bo_cuoc": True, "ly_do": last[:200]})
    print(f"    {tag}: bỏ sau {cfg.retries + 1} lượt — {last[:80]}", file=sys.stderr)
    return ""


def _mot_luot(cfg, items: list[tuple[int, str]], tag: str) -> dict[int, str]:
    body = "\n".join(f"{n}. {zh}" for n, zh in items)
    text = call(cfg, TASK.format(count=len(items), rules=RULES, body=body), tag)
    out: dict[int, str] = {}
    want = {n for n, _ in items}
    for line in text.split("\n"):
        m = re.match(r"^\s*(\d+)[.):]\s*(.+?)\s*$", line)
        if m and int(m.group(1)) in want:  # bỏ số lạc, đừng nhận nhầm số của câu khác
            out[int(m.group(1))] = m.group(2).strip()
    return out


SAN_LO = 8   # dưới ngưỡng này thì thôi, chia nhỏ nữa chỉ tốn phụ phí 7,3k mỗi request


def translate_lines(cfg, items: list[tuple[int, str]], tag: str, sau: int = 0) -> dict[int, str]:
    """items = [(n, zh)]. Trả về {n: vi}.

    Cổng có TRẦN CỨNG ~600 giây/request: quá giờ nó trả về rỗng, `stop_reason: null`,
    KHÔNG báo lỗi — và input vẫn bị tính tiền. Nên lô trả về quá ít thì phải CHIA ĐÔI
    rồi thử lại, chứ xin lại nguyên lô cũ là cắt tiếp lần nữa, tốn gấp đôi.
    """
    out = _mot_luot(cfg, items, tag)
    thieu = [(n, zh) for n, zh in items if n not in out]
    if not thieu:
        return out
    if len(thieu) > len(items) // 2 and len(items) > SAN_LO and sau < 3:
        giua = len(items) // 2
        print(f"    {tag}: chỉ được {len(out)}/{len(items)} — nghi bị cắt, chia đôi",
              file=sys.stderr)
        out = {}
        for i, nua in enumerate((items[:giua], items[giua:])):
            out.update(translate_lines(cfg, nua, f"{tag}/{i}", sau + 1))
        return out
    print(f"    {tag}: thiếu {len(thieu)} dòng, xin lại", file=sys.stderr)
    out.update(_mot_luot(cfg, thieu, f"{tag}~va"))
    return out


# ── chế độ chạy ──────────────────────────────────────────────────────────────

def do_ping(cfg) -> None:
    text = call(cfg, "Dịch sang tiếng Việt, chỉ trả về bản dịch: 南宫正雄走了进来。", "ping")
    print(f"trả về : {text.strip()!r}")
    print("(đúng phải là 'Nam Cung Chính Hùng đi vào.' — sai tên riêng là dấu hiệu model yếu)")
    print(f"log    : {LOG_PATH}")


def do_probe(cfg, args) -> None:
    src = SCRATCH / "llm_probe_src.jsonl"
    rows = [json.loads(l) for l in src.read_text(encoding="utf-8").splitlines() if l.strip()]
    items = [(r["n"], r["zh"]) for r in rows]
    got: dict[int, str] = {}
    for i in range(0, len(items), args.chunk):
        part = items[i:i + args.chunk]
        got.update(translate_lines(cfg, part, f"probe[{part[0][0]}-{part[-1][0]}]"))
        print(f"  {len(got)}/{len(items)} dòng", file=sys.stderr)
    reply = SCRATCH / f"llm_probe_reply_{args.label}.txt"
    reply.write_text("".join(f"{n}. {got[n]}\n" for n in sorted(got)), encoding="utf-8")
    print(f"ghi {len(got)}/{len(items)} dòng → {reply}")
    print(f"chấm : hachimi/.venv/bin/python hachimi/eval/llm_probe.py "
          f"--score {reply} --label {args.label}")


def do_batch(cfg, args) -> None:
    """Dịch thư mục in_XXX.jsonl → out_XXX.jsonl. Đã có out_ thì bỏ qua (chạy tiếp được)."""
    d = args.batch_in
    todo = [p for p in sorted(d.glob("in_*.jsonl"))
            if not (d / p.name.replace("in_", "out_", 1)).exists()]
    print(f"{len(todo)} lô cần chạy trong {d}")

    def one(path: Path) -> str:
        rows = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
        items = [(r["n"], r[args.field]) for r in rows]
        out = d / path.name.replace("in_", "out_", 1)
        tmp = out.with_suffix(".part")

        def ghi_tam() -> None:
            tmp.write_text("".join(json.dumps({"n": n, "vi": got[n]}, ensure_ascii=False) + "\n"
                                   for n in sorted(got)), encoding="utf-8")

        # Lô dở của lần chạy trước: nhặt lại, đừng trả tiền dịch hai lần cho cùng một câu.
        got: dict[int, str] = {}
        if tmp.exists():
            for line in tmp.read_text(encoding="utf-8").splitlines():
                if line.strip():
                    r = json.loads(line)
                    got[r["n"]] = r["vi"]
        con_lai = [it for it in items if it[0] not in got]
        try:
            for i in range(0, len(con_lai), args.chunk):
                part = con_lai[i:i + args.chunk]
                got.update(translate_lines(cfg, part, f"{path.name}[{part[0][0]}]"))
                ghi_tam()   # ghi sau MỖI chunk: bị giết giữa chừng vẫn giữ được phần đã trả tiền
        except BudgetHet as exc:
            if got:
                ghi_tam()
            return f"{path.name} → DỪNG dở {len(got)}/{len(items)} (hết gói: {exc})"
        ghi_tam()
        tmp.rename(out)  # đổi tên chỉ khi trọn lô: out_ luôn nghĩa là XONG
        phu = len(got) / max(1, len(items))
        log_call({"tag": "LO_XONG", "lo": path.name, "duoc": len(got), "can": len(items),
                  "do_phu": round(phu, 3), "da_tieu": _spent})
        canh = "  ⚠ KHUYẾT" if phu < 0.97 else ""
        return (f"{path.name} → {len(got)}/{len(items)}{canh}"
                f"   [đã tiêu {_spent/1e6:.2f}M]")

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for line in pool.map(one, todo):
            print(line, flush=True)
    print(f"\nDỪNG · đã tiêu {_spent:,} token"
          + (f" / gói {_budget:,}" if _budget else "")
          + f"\nLô khuyết (<97%) tra bằng: grep LO_XONG {LOG_PATH} | grep -v '\"do_phu\": 1.0'")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base-url", default=DEFAULT_BASE)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--key-file", type=Path)
    ap.add_argument("--max-tokens", type=int, default=0,
                    help="0 = tự tính theo chunk (đo được ~98 token/câu Việt)")
    # Cổng có trần cứng ~600s: quá giờ nó trả rỗng NHƯNG VẪN TÍNH input. Tự bỏ ở 330s
    # rẻ hơn: bỏ sớm thì chia đôi lô rồi dịch lại, còn để chạm 600s là mất ~7-12k token.
    ap.add_argument("--timeout", type=int, default=480)
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--chunk", type=int, default=30, help="số câu mỗi request")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--rpm", type=int, default=20, help="trần request/phút của cổng")
    ap.add_argument("--budget", type=float, default=0, metavar="TRIỆU",
                    help="dừng khi tiêu đủ N triệu token (cộng dồn từ log)")
    ap.add_argument("--label", default="gateway")
    ap.add_argument("--ping", action="store_true")
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--batch-in", type=Path, metavar="DIR")
    ap.add_argument("--field", default="zh")
    args = ap.parse_args(argv)
    args.api_key = read_key(args.key_file)
    if not args.max_tokens:
        # ~98 token cho mỗi câu tiếng Việt (đo thật), cộng 25% biên + 1000 phòng hờ
        args.max_tokens = int(args.chunk * 98 * 1.25) + 1000
    global _budget, _spent
    if args.budget:
        _budget = int(args.budget * 1e6)
        _spent = doc_da_tieu()
        print(f"gói {_budget:,} token · đã tiêu trước đó {_spent:,} "
              f"· còn {_budget - _spent:,}")
        if _spent >= _budget:
            raise SystemExit("Gói đã hết — không chạy.")

    if args.ping:
        do_ping(args)
    elif args.probe:
        do_probe(args, args)
    elif args.batch_in:
        do_batch(args, args)
    else:
        ap.error("chọn một trong --ping / --probe / --batch-in")


if __name__ == "__main__":
    main()
