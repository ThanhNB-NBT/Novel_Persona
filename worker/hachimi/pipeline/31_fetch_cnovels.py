"""Tải CHỌN LỌC nguyên tác Trung từ `chi-vi/CNovels` — 10,7 GB thay vì 120 GB.

Xem `docs/train-scratch-v7.md` mục 19. Tóm tắt: 5 zip trên HuggingFace tổng 120 GB, nhưng ta
chỉ cần những truyện **đã ghép được với bản dịch tiếng Việt** (kho epub trên đĩa hoặc emtichu).
Zip cho phép đọc mục lục rồi rút từng file bằng HTTP range, nên khỏi tải cả kho.

    python 31_fetch_cnovels.py --match cn_match.json --out ~/hachimi-work/cnovels
    python 31_fetch_cnovels.py --list-only          # chỉ dựng mục lục, in dung lượng cần tải
    python 31_fetch_cnovels.py --self-check

Không thêm dependency: `requests` đã theo `huggingface_hub`, `zlib` là stdlib.

Ba chỗ dễ sai, đã trả giá:
1. **Zip >4 GB nên phải đọc ZIP64** — EOCD thường ghi 0xFFFFFFFF, phải lần theo
   `PK\\x06\\x07` để lấy offset thật.
2. **Mỗi kho đặt tên file một kiểu.** 12z/zxcs dùng `《tên》（…）作者：tác giả.txt`, còn
   84sk/jjjjxsw/qisuwang dùng `tên.txt` trơn. Lượt đầu chỉ viết regex cho kiểu thứ nhất là
   bỏ sót 76.700 truyện.
3. **Local header có độ dài extra field khác central directory** → không tính trước được chỗ
   dữ liệu bắt đầu; lấy dư 1 KB rồi tự cắt (xem `fetch_one`).
4. **Nút thắt là ĐỘ TRỄ mỗi request, không phải băng thông.** Đo 30/08: băng thông thô tới HF
   8,15 MB/s mà bản tuần tự chỉ đạt 1,85 MB/s — mỗi truyện tốn ~3,5 giây, trong đó truyền thật
   chỉ 0,4 giây. Chữa bằng ba việc: gộp còn một request/file, bám chuyển hướng CDN một lần cho
   cả kho, và tải song song (`--workers`).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
import unicodedata
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))   # worker/ — nơi có novelworker

REPO = "chi-vi/CNovels"
ZIPS = ["12z.cn.zip", "zxcs.zip.zip", "84sk.com.zip", "jjjjxsw.com.zip", "qisuwang.cc.zip"]
BRACKET = re.compile(r"《(.+?)》.*?作者[：:](.+?)$")


def zh_title(entry: str) -> tuple[str, str | None] | None:
    """Tên file trong zip → (tên truyện Trung, tác giả hoặc None)."""
    stem = entry.rsplit("/", 1)[-1]
    if not stem.endswith(".txt"):
        return None
    stem = stem[:-4]
    match = BRACKET.search(stem)
    if match:
        return match.group(1).strip(), match.group(2).strip()
    return (stem.strip(), None) if stem.strip() else None


def norm(text: str | None) -> str:
    text = unicodedata.normalize("NFC", text or "").lower()
    return re.sub(r"[^0-9a-zà-ỹ]+", " ", text).strip()


def _headers() -> dict:
    token = Path(os.path.expanduser("~/.cache/huggingface/token")).read_text().strip()
    return {"Authorization": f"Bearer {token}"}


def _range(session, url: str, start: int, end: int) -> bytes:
    response = session.get(url, headers={"Range": f"bytes={start}-{end}"}, timeout=300)
    response.raise_for_status()
    return response.content


def central_directory(session, url: str) -> list[dict]:
    """Mục lục zip từ xa: [{name, offset, csize, method}]."""
    size = int(session.head(url, allow_redirects=True, timeout=60).headers["Content-Length"])
    tail = _range(session, url, max(0, size - 200_000), size - 1)
    at = tail.rfind(b"PK\x05\x06")
    if at < 0:
        raise SystemExit("không thấy EOCD — file không phải zip?")
    cd_size, cd_offset = struct.unpack("<II", tail[at + 12:at + 20])
    if cd_offset == 0xFFFFFFFF or cd_size == 0xFFFFFFFF:      # ZIP64
        loc = tail.rfind(b"PK\x06\x07")
        z64_offset = struct.unpack("<Q", tail[loc + 8:loc + 16])[0]
        z64 = _range(session, url, z64_offset, z64_offset + 55)
        cd_size, cd_offset = struct.unpack("<QQ", z64[40:56])
    blob = _range(session, url, cd_offset, cd_offset + cd_size - 1)
    entries, at = [], 0
    while at + 46 <= len(blob) and blob[at:at + 4] == b"PK\x01\x02":
        method, = struct.unpack("<H", blob[at + 10:at + 12])
        csize, usize = struct.unpack("<II", blob[at + 20:at + 28])
        name_len, extra_len, comment_len = struct.unpack("<HHH", blob[at + 28:at + 34])
        local, = struct.unpack("<I", blob[at + 42:at + 46])
        name = blob[at + 46:at + 46 + name_len].decode("utf-8", "replace")
        extra = blob[at + 46 + name_len:at + 46 + name_len + extra_len]
        csize, local = _zip64_fix(extra, csize, usize, local)
        entries.append({"name": name, "offset": local, "csize": csize, "method": method})
        at += 46 + name_len + extra_len + comment_len
    return entries


def _zip64_fix(extra: bytes, csize: int, usize: int, local: int) -> tuple[int, int]:
    """Lấy csize/offset THẬT từ trường phụ ZIP64 khi central directory ghi 0xFFFFFFFF.

    Đây là lỗi đã làm hỏng 1.260/1.477 file lượt đầu: `12z.cn.zip` nặng 17,7 GB nên hầu hết
    file nằm quá mốc 4 GB, offset 32-bit không chứa nổi ⇒ ghi 0xFFFFFFFF, giá trị thật nằm
    trong trường phụ id 0x0001. Các giá trị trong đó xuất hiện THEO THỨ TỰ usize → csize →
    offset, và **chỉ có mặt khi trường tương ứng bị tràn** — nên phải kiểm từng cái.
    """
    if 0xFFFFFFFF not in (csize, usize, local):
        return csize, local
    at = 0
    while at + 4 <= len(extra):
        field_id, field_len = struct.unpack("<HH", extra[at:at + 4])
        body = extra[at + 4:at + 4 + field_len]
        if field_id == 0x0001:
            pos = 0
            if usize == 0xFFFFFFFF and pos + 8 <= len(body):
                pos += 8
            if csize == 0xFFFFFFFF and pos + 8 <= len(body):
                csize, = struct.unpack("<Q", body[pos:pos + 8])
                pos += 8
            if local == 0xFFFFFFFF and pos + 8 <= len(body):
                local, = struct.unpack("<Q", body[pos:pos + 8])
            break
        at += 4 + field_len
    return csize, local


HEADER_SLACK = 1024      # thừa đủ cho tên file + extra field của local header


def fetch_one(session, url: str, entry: dict) -> bytes:
    """Rút một file khỏi zip từ xa bằng MỘT request.

    Local header có độ dài extra field khác central directory nên không tính trước được chỗ
    dữ liệu bắt đầu. Cách cũ là gọi thêm một request chỉ để đọc 30 byte header — mà đo được
    mỗi request tốn ~1,5 giây chi phí (chuyển hướng HF → CDN + bắt tay TLS), tức **chi phí gấp
    4 lần thời gian truyền dữ liệu thật**. Nên lấy dư `HEADER_SLACK` byte ở đầu rồi tự cắt:
    tốn thêm 1 KB, tiết kiệm nửa số request.
    """
    blob = _range(session, url, entry["offset"],
                  entry["offset"] + 30 + HEADER_SLACK + entry["csize"] - 1)
    if blob[:4] != b"PK\x03\x04":
        raise RuntimeError(f"local header hỏng ở {entry['name']}")
    name_len, extra_len = struct.unpack("<HH", blob[26:30])
    start = 30 + name_len + extra_len
    raw = blob[start:start + entry["csize"]]
    if len(raw) != entry["csize"]:
        raise RuntimeError(f"thiếu dữ liệu ở {entry['name']} — tăng HEADER_SLACK")
    if entry["method"] == 0:
        return raw
    return zlib.decompress(raw, -zlib.MAX_WBITS)


def _resolve(session, url: str) -> str:
    """Bám theo chuyển hướng HF → CDN MỘT lần rồi dùng thẳng URL cuối.

    Mỗi request tới `huggingface.co/.../resolve/...` đều bị chuyển hướng sang CDN. Để
    `requests` tự bám mỗi lần là mỗi file gánh thêm một vòng round-trip + bắt tay TLS. Đo được:
    băng thông thô 8,15 MB/s nhưng script chỉ đạt 1,85 MB/s.
    """
    response = session.head(url, allow_redirects=True, timeout=60)
    response.raise_for_status()
    return response.url


def _session():
    import requests

    session = requests.Session()
    session.headers.update(_headers())
    adapter = requests.adapters.HTTPAdapter(pool_connections=32, pool_maxsize=32)
    session.mount("https://", adapter)
    return session


def run(args) -> None:
    from concurrent.futures import ThreadPoolExecutor
    from threading import Lock
    from threading import local as thread_local

    wanted = {row["hv"] for row in json.loads(Path(args.match).read_text(encoding="utf-8"))}
    print(f"Cần {len(wanted):,} truyện (khớp tên Hán-Việt)", flush=True)
    from novelworker.translator.hanviet import han_viet

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    main_session = _session()
    tls = thread_local()

    def worker_session():
        # requests.Session KHÔNG an toàn đa luồng — mỗi luồng giữ session riêng.
        if not hasattr(tls, "s"):
            tls.s = _session()
        return tls.s

    total_bytes = got = skipped = failed = 0
    seen: set[str] = set()
    lock = Lock()

    for name in ZIPS:
        url = f"https://huggingface.co/datasets/{REPO}/resolve/main/{name}"
        entries = central_directory(main_session, url)
        picks = []
        for entry in entries:
            parsed = zh_title(entry["name"])
            if not parsed:
                continue
            key = norm(han_viet(parsed[0]) or "")
            if key and key in wanted and key not in seen:
                picks.append((key, entry))
                seen.add(key)
        print(f"{name}: {len(entries):,} entry · cần lấy {len(picks):,} "
              f"({sum(e['csize'] for _, e in picks)/1e9:.2f} GB nén)", flush=True)
        total_bytes += sum(e["csize"] for _, e in picks)
        if args.list_only:
            continue

        direct = _resolve(main_session, url)
        todo = [(k, e, out / f"{k.replace(' ', '_')[:120]}.txt") for k, e in picks]
        todo = [t for t in todo if not t[2].exists()]
        skipped += len(picks) - len(todo)

        def grab(item, direct=direct):        # bind ngay, khong bat bien vong lap
            _key, entry, target = item
            try:
                data = fetch_one(worker_session(), direct, entry)
            except Exception as error:                     # noqa: BLE001 - bỏ 1 truyện, chạy tiếp
                return entry["name"], error
            target.write_bytes(data)
            return None

        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            for result in pool.map(grab, todo):
                with lock:
                    if result is None:
                        got += 1
                        if got % 200 == 0:
                            print(f"  đã tải {got:,} truyện", flush=True)
                    else:
                        failed += 1
                        print(f"  hỏng {result[0]}: {type(result[1]).__name__}", flush=True)

    print(f"\nTổng cần {total_bytes/1e9:.2f} GB · tải mới {got:,} · có sẵn {skipped:,} · hỏng {failed}")
    print(f"→ {out}")


def _self_check() -> None:
    assert zh_title("12z.cn/《1255再铸鼎》（校对版全本）作者：修改两次.txt") == ("1255再铸鼎", "修改两次")
    assert zh_title("84sk.com/(修真)女主掉了金手指.txt") == ("(修真)女主掉了金手指", None)
    assert zh_title("qisuwang/（快穿）炮灰的人生.txt") == ("（快穿）炮灰的人生", None)
    assert zh_title("12z.cn/") is None and zh_title("a/cover.jpg") is None
    assert norm("Yêu Thần Ký") == "yêu thần ký"
    assert norm("  Nhất Thế  Chi-Tôn! ") == "nhất thế chi tôn"

    # ZIP64: offset tràn 32-bit thì phải lấy từ trường phụ id 0x0001 (lỗi đã hỏng 1.260 file).
    import struct as _s
    body = _s.pack("<QQ", 123456789, 5_000_000_000)          # usize, offset (csize khong tran)
    extra = _s.pack("<HH", 0x0001, len(body)) + body
    assert _zip64_fix(extra, 4096, 0xFFFFFFFF, 0xFFFFFFFF) == (4096, 5_000_000_000)
    # ca csize lan offset deu tran -> doc ca ba so theo dung thu tu
    body3 = _s.pack("<QQQ", 111, 222, 333)
    extra3 = _s.pack("<HH", 0x0001, len(body3)) + body3
    assert _zip64_fix(extra3, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF) == (222, 333)
    # khong tran thi giu nguyen, khong dung toi truong phu
    assert _zip64_fix(b"", 4096, 8192, 999) == (4096, 999)
    print("31_fetch_cnovels OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--match", type=Path,
                    default=Path.home() / "hachimi-work/scratch/cn_match.json")
    ap.add_argument("--out", type=Path, default=Path.home() / "hachimi-work/cnovels")
    ap.add_argument("--workers", type=int, default=12,
                    help="số luồng tải song song — nút thắt là độ trễ mỗi request, không phải băng thông")
    ap.add_argument("--list-only", action="store_true")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
        return
    run(args)


if __name__ == "__main__":
    main()
