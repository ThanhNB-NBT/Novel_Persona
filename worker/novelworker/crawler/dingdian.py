"""Adapter KHUÔN 顶点小说 (dingdian): ddxs (dingdian-xiaoshuo.com) & clone cùng khuôn.

Khác biquge đủ để tách class (design doc §3.1 "thêm khuôn mới khi HTML thật sự khác"):
- book_id = SLUG chữ (vd `niwen_2`), không phải số.
- Metadata KHÔNG có og:* → lấy từ `<title>《Tên》Tác giả` + `<meta name=description>`.
- Mục lục ở trang RIÊNG `/n/{slug}/xiaoshuo.html` (không phải trang truyện) — list đầy đủ,
  anchor `<a href=".../{cid}.html" itemprop=url><span itemprop=name>第N章 …</span></a>`, thứ tự 1→N.
- Nội dung chương trong `<div class="articlebody">`, plain text + <br>. Không phân trang.

Kiểm chứng chạy thật dingdian-xiaoshuo.com 2026-07. config override: novel_path/list_path/
chapter_path/content_class/ad_markers/encoding.
"""
from __future__ import annotations

import logging
import re
import time
from html import unescape

from .base import ChapterRef, NovelMeta, SourceAdapter

log = logging.getLogger(__name__)

_DEFAULT_AD_MARKERS = ["顶点小说", "dingdian", "请记住", "手机版"]


class DingdianAdapter(SourceAdapter):
    def _novel_url(self, slug: str) -> str:
        return self.config.get("novel_path", "/n/{book_id}/").format(book_id=slug)

    def _list_url(self, slug: str) -> str:
        return self.config.get("list_path", "/n/{book_id}/xiaoshuo.html").format(book_id=slug)

    def _chapter_url(self, slug: str, cid: str) -> str:
        return self.config.get(
            "chapter_path", "/n/{book_id}/{chapter_id}.html").format(book_id=slug, chapter_id=cid)

    @property
    def _content_class(self) -> str:
        return self.config.get("content_class", "articlebody")

    @property
    def _ad_markers(self) -> list[str]:
        host = re.sub(r"^https?://(www\.)?", "", self.base_url).split("/")[0]
        return [host, host.split(".")[0], *(self.config.get("ad_markers") or _DEFAULT_AD_MARKERS)]

    # ---------- SourceAdapter ----------

    def fetch_latest(self, limit: int = 30) -> list[NovelMeta]:
        """Quét trang liệt kê (category) → danh sách slug + tên (nhẹ). Metadata đầy đủ
        (tác giả/bìa/mô tả) do discover_latest gọi fetch_novel_meta cho truyện MỚI.

        Trang category `/category/{c}.html` phân trang `_2/_3…`; gom tới `limit` slug.
        config `discover_paths` đổi danh sách trang gốc (mặc định category 1)."""
        paths = self.config.get("discover_paths") or ["/category/1.html"]
        out: list[NovelMeta] = []
        seen: set[str] = set()
        for base_path in paths:
            page = 1
            while len(out) < limit:
                path = base_path if page == 1 else re.sub(r"\.html$", f"_{page}.html", base_path)
                try:
                    html = self._get(path)
                except Exception:
                    break  # hết trang / lỗi mạng → sang path kế
                found = re.findall(r'/n/([a-z0-9_]+)/"[^>]*>([^<]{2,40})<', html)
                found = [(s, t) for s, t in found if s not in seen]
                if not found:
                    break  # trang không còn truyện mới → dừng phân trang
                for slug, title in found:
                    seen.add(slug)
                    out.append(NovelMeta(
                        source_novel_id=slug,
                        source_url=f"{self.base_url}{self._novel_url(slug)}",
                        title_zh=unescape(title).strip(),
                    ))
                    if len(out) >= limit:
                        break
                page += 1
                time.sleep(0.5)  # lịch sự với nguồn
        return out

    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        html = self._get(self._novel_url(source_novel_id))
        # <title>《逆问》小洛儿 - 顶点小说网
        mt = re.search(r"<title>《([^》]+)》\s*([^\s<-]+)", html)
        if not mt:
            raise ValueError(f"Không parse được truyện {source_novel_id} ({self.name}) — đổi cấu trúc?")
        title, author = mt.group(1).strip(), mt.group(2).strip()
        # <meta name="description" content="《X》作者:A,简介:...">; nội dung bị escape 2 lần
        # (&amp;lt;br /&amp;gt;) → unescape 2 lượt rồi bỏ tag còn lại.
        desc = None
        md = re.search(r'name="description"[^>]*content="(.*?)"', html, re.S)
        if md:
            d = unescape(unescape(md.group(1)))
            d = re.sub(r"^《[^》]+》作者:[^,]+,简介:", "", d)
            d = re.sub(r"<br\s*/?>", "\n", d, flags=re.I)
            desc = re.sub(r"<[^>]+>", "", d).strip() or None
        # bìa: img trong thư mục book_images (không có og:image)
        mc = re.search(r'<img[^>]+src="([^"]*book_images[^"]+)"', html)
        return NovelMeta(
            source_novel_id=source_novel_id,
            source_url=f"{self.base_url}{self._novel_url(source_novel_id)}",
            title_zh=title,
            author_zh=author,
            cover_url=mc.group(1) if mc else None,
            description_zh=desc,
            genres_zh=[],
            status="ongoing",  # ddxs không lộ trạng thái ở trang truyện
        )

    def fetch_chapter_list(self, source_novel_id: str) -> list[ChapterRef]:
        html = self._get(self._list_url(source_novel_id))
        pattern = re.compile(
            r'<a href="[^"]*?/' + re.escape(source_novel_id)
            + r'/(\d+)\.html"[^>]*>(?:<span[^>]*>)?([^<]+)')
        # list đã đúng thứ tự 1→N; dedupe GIỮ lần cuối phòng có block lặp.
        last: dict[str, tuple[int, str]] = {}
        for order, m in enumerate(pattern.finditer(html)):
            last[m.group(1)] = (order, unescape(m.group(2)).strip())
        ordered = sorted(last.items(), key=lambda kv: kv[1][0])
        refs = [
            ChapterRef(index=i + 1, source_chapter_id=f"{source_novel_id}/{cid}", title_zh=title)
            for i, (cid, (_, title)) in enumerate(ordered)
        ]
        if not refs:
            raise ValueError(f"Không lấy được mục lục {self.name} cho {source_novel_id}")
        return refs

    def fetch_chapter(self, source_chapter_id: str) -> str:
        slug, _, cid = source_chapter_id.rpartition("/")
        html = self._get(self._chapter_url(slug, cid))
        cls = re.escape(self._content_class)
        m = re.search(r'<div[^>]*\bclass="[^"]*' + cls + r'[^"]*"[^>]*>(.*?)</div>', html, re.S)
        if not m:
            raise ValueError(f"Không thấy nội dung chương {source_chapter_id} ({self.name}) — đổi cấu trúc?")
        # ddxs gói mỗi đoạn trong <p>…</p> (không dùng <br>) → đổi cả </p> thành xuống
        # dòng, nếu không strip tag làm dính hết đoạn thành 1 khối chữ liền.
        raw = re.sub(r"</p\s*>|<br\s*/?>", "\n", m.group(1), flags=re.I)
        raw = re.sub(r"<[^>]+>", "", raw)
        markers = [k.lower() for k in self._ad_markers]
        lines = [ln.strip() for ln in unescape(raw).split("\n")]
        lines = [ln for ln in lines if ln and not any(k in ln.lower() for k in markers)]
        text = "\n".join(lines).strip()
        if len(text) < 50:
            raise ValueError(f"Chương {source_chapter_id} quá ngắn ({len(text)} ký tự)")
        return text

