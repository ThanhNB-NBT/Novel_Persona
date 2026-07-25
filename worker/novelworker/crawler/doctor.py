"""Chẩn đoán nguồn crawl hỏng bằng LLM — ĐỀ XUẤT selector, KHÔNG tự sửa production.

Vì sao tồn tại: mỗi lần nguồn đổi HTML là adapter câm (4 lần trong 1 ngày 2026-07-25:
Referer thiếu → 403, `</H1>` HOA, mục lục xếp theo data-num, div lồng nhau). Mò tay
mỗi lần mất hàng giờ. Việc này LLM làm tốt: nhìn khung HTML rồi chỉ ra thẻ chứa nội dung.

Ranh giới AN TOÀN — đây là lý do dùng LLM ở đây chấp nhận được, còn dùng để bóc từng
chương thì không:
  * LLM chỉ thấy KHUNG HTML (thẻ + thuộc tính, ĐÃ xoá sạch chữ) → không thể bịa chữ
    vào nội dung truyện, vì nó không hề sinh ra nội dung.
  * LLM đề xuất SELECTOR; code tự chạy selector đó rồi tự kiểm bằng máy (đủ dài, đủ
    tỷ lệ chữ Hán, không dính rác điều hướng). Đề xuất trượt kiểm → vứt.
  * Kết quả IN RA cho người xem, không ghi thẳng vào bảng sources. Người chốt.

Dùng:  python -m novelworker.crawler.doctor <url-trang-chuong> [--apply-to <ten-nguon>]
"""
from __future__ import annotations

import argparse
import json
import logging
import re
from html import unescape

log = logging.getLogger(__name__)

# Rác điều hướng/quảng cáo: selector nào lôi về thứ này là bóc trượt ra ngoài thân chương.
_NAV_JUNK = ("上一章", "下一章", "返回目录", "加入书签", "推荐本书", "手机阅读",
             "loadAdv", "上一页", "下一页", "章节目录")
_HAN = re.compile(r"[一-鿿]")
# Ngưỡng để một khối được coi là "thân chương thật" chứ không phải menu/sidebar.
_MIN_CHARS = 200
_MIN_HAN_RATIO = 0.5
_MIN_LINES = 3


def html_skeleton(html: str, max_chars: int = 6000) -> str:
    """Khung HTML: giữ thẻ + thuộc tính, XOÁ HẾT chữ. Vừa là biện pháp an toàn (LLM
    không thấy nội dung nên không thể chế nội dung), vừa để prompt đủ nhỏ."""
    s = re.sub(r"<script.*?</script>|<style.*?</style>", "", html, flags=re.S | re.I)
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    # thay chữ giữa 2 thẻ bằng dấu hiệu độ dài → LLM biết khối nào nhiều chữ
    def mark(m: re.Match) -> str:
        n = len(m.group(1).strip())
        return f">[{n} ký tự]<" if n > 20 else "><"
    s = re.sub(r">([^<]*)<", mark, s)
    s = re.sub(r"\s+", " ", s).strip()
    return s[:max_chars]


def extract_by(html: str, kind: str, value: str) -> str:
    """Bóc text theo selector thô (id/class/tag). Cố ý dùng regex như mọi adapter khác
    — không kéo thêm bs4/lxml chỉ để chạy công cụ chẩn đoán chạy vài lần một năm."""
    if kind == "id":
        pat = r'<[a-z]+[^>]*\bid="' + re.escape(value) + r'"[^>]*>'
    elif kind == "class":
        pat = r'<[a-z]+[^>]*\bclass="[^"]*\b' + re.escape(value) + r'\b[^"]*"[^>]*>'
    elif kind == "tag":
        pat = r"<" + re.escape(value) + r"[^>]*>"
    else:
        raise ValueError(f"kind lạ: {kind}")
    m = re.search(pat, html, re.I)
    if not m:
        return ""
    # Cắt tới thẻ đóng cân bằng: khối nội dung hay lồng div con (quảng cáo, txtinfo)
    # nên </div> đầu tiên KHÔNG phải điểm dừng đúng.
    tag = re.match(r"<([a-z]+)", m.group(0), re.I).group(1)
    depth, pos = 1, m.end()
    token = re.compile(rf"</?{tag}\b", re.I)
    while depth and (t := token.search(html, pos)):
        depth += -1 if t.group(0).startswith("</") else 1
        pos = t.end()
    seg = html[m.end():pos]
    seg = re.sub(r"<script.*?</script>", "", seg, flags=re.S | re.I)
    seg = re.sub(r"</p\s*>|<br\s*/?>", "\n", seg, flags=re.I)
    seg = re.sub(r"<[^>]+>", "", seg)
    lines = [ln.strip() for ln in unescape(seg).replace("\xa0", " ").split("\n")]
    return "\n".join(ln for ln in lines if ln).strip()


def verify(text: str) -> tuple[bool, str]:
    """Kiểm bằng MÁY, không hỏi lại LLM — đây là chốt chặn khiến đề xuất sai không lọt."""
    if len(text) < _MIN_CHARS:
        return False, f"quá ngắn ({len(text)} < {_MIN_CHARS} ký tự)"
    ratio = len(_HAN.findall(text)) / len(text)
    if ratio < _MIN_HAN_RATIO:
        return False, f"tỷ lệ chữ Hán thấp ({ratio:.0%}) — có thể là menu/mã"
    if len([ln for ln in text.split("\n") if ln]) < _MIN_LINES:
        return False, "ít hơn 3 dòng — khó là thân chương"
    if hit := [j for j in _NAV_JUNK if j in text]:
        return False, f"dính rác điều hướng: {', '.join(hit[:3])}"
    return True, "đạt"


_SYSTEM = (
    "Bạn phân tích khung HTML của trang đọc tiểu thuyết Trung Quốc. "
    "Toàn bộ chữ đã bị xoá, chỉ còn thẻ và thuộc tính, kèm dấu [N ký tự] cho biết "
    "khối đó chứa bao nhiêu chữ. Nhiệm vụ: chỉ ra thẻ BỌC THÂN CHƯƠNG (khối chữ dài "
    "nhất, không phải menu/quảng cáo/điều hướng). "
    'Chỉ trả JSON: {"kind":"id|class|tag","value":"...","lydo":"..."} '
    "Không giải thích gì thêm, không bọc trong markdown."
)


def ask_llm(skeleton: str, n: int = 3) -> list[dict]:
    """Hỏi LLM lấy tối đa n đề xuất. Import muộn: chẩn đoán không nên kéo theo cả
    tầng dịch khi chỉ chạy test."""
    from ..translator.providers import build_chain

    chain = build_chain()
    out: list[dict] = []
    for i in range(n):
        hint = "" if not out else (
            f"\n\nĐã thử và TRƯỢT: {json.dumps(out, ensure_ascii=False)}. Đề xuất khác đi.")
        try:
            r = chain.complete(_SYSTEM, f"Khung HTML:\n{skeleton}{hint}",
                               temperature=0.2 + 0.2 * i, max_tokens=300)
            raw = re.sub(r"^```(?:json)?|```$", "", r.text.strip(), flags=re.M).strip()
            m = re.search(r"\{.*\}", raw, re.S)
            if m:
                out.append(json.loads(m.group(0)))
        except Exception as e:  # 1 lần hỏi trượt không nên giết cả phiên chẩn đoán
            log.warning("Hỏi LLM trượt lần %d: %s", i + 1, e)
    return out


def diagnose(html: str, candidates: list[dict] | None = None) -> dict:
    """Thử lần lượt đề xuất → trả cái ĐẦU TIÊN qua được kiểm chứng bằng máy."""
    tried = []
    for c in candidates if candidates is not None else ask_llm(html_skeleton(html)):
        kind, value = c.get("kind", ""), c.get("value", "")
        if not kind or not value:
            continue
        try:
            text = extract_by(html, kind, value)
        except ValueError:
            tried.append({**c, "ket_qua": "kind không hợp lệ"})
            continue
        ok, why = verify(text)
        tried.append({**c, "ket_qua": why, "so_ky_tu": len(text)})
        if ok:
            return {"ok": True, "kind": kind, "value": value, "text": text, "da_thu": tried}
    return {"ok": False, "da_thu": tried}


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    ap = argparse.ArgumentParser(description="Chẩn đoán selector nội dung của 1 nguồn crawl")
    ap.add_argument("url", help="URL đầy đủ của MỘT trang chương")
    ap.add_argument("--encoding", default="utf-8", help="gbk/gb18030 cho nguồn cũ")
    args = ap.parse_args()

    from curl_cffi import requests as cr
    host = re.sub(r"^(https?://[^/]+).*", r"\1", args.url)
    r = cr.get(args.url, impersonate="chrome", headers={"Referer": host + "/"}, timeout=30)
    html = r.content.decode(args.encoding, "ignore")
    print(f"Tải {args.url}: HTTP {r.status_code}, {len(html)} ký tự\n")

    res = diagnose(html)
    for t in res["da_thu"]:
        mark = "✔" if t["ket_qua"] == "đạt" else "✘"
        print(f"  {mark} {t.get('kind')}={t.get('value')!r} → {t['ket_qua']}"
              f" ({t.get('so_ky_tu', 0)} ký tự)")
    if not res["ok"]:
        print("\nKhông đề xuất nào qua được kiểm chứng — nguồn này cần xem tay.")
        return 1
    print(f"\nĐỀ XUẤT config cho bảng sources:\n"
          f'  {{"content_{res["kind"]}": "{res["value"]}"}}\n')
    print("Trích 300 ký tự đầu để bạn nhìn bằng mắt:")
    print("  " + res["text"][:300].replace("\n", "\n  "))
    print("\n(Chưa ghi gì vào DB — tự dán vào sources.config nếu thấy đúng.)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
