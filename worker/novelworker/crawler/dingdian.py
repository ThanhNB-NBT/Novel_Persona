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
from itertools import zip_longest

from .base import ChapterRef, NovelMeta, SourceAdapter

log = logging.getLogger(__name__)

_DEFAULT_AD_MARKERS = ["顶点小说", "dingdian", "请记住", "手机版"]

# Các mục đúng thị hiếu chung của app: 玄幻, 仙侠, 武侠, 网游, 奇幻, 科幻, 悬疑.
# Đô thị/ngôn tình/lịch sử không đưa vào pool; bộ lọc chung vẫn kiểm tra metadata lần cuối.
_DEFAULT_DISCOVER_PATHS = tuple(f"/category/{i}.html" for i in (1, 3, 4, 7, 8, 9, 10))
_COMPLETED_TITLE = re.compile(r"(?:正文|全文)?(?:完结|完本)|大结局|完结感言|完本感言|终章")


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

    def fetch_latest(self, limit: int = 30, page: int | None = None) -> list[NovelMeta]:
        """Quét trang liệt kê (category) → danh sách slug + tên (nhẹ). Metadata đầy đủ
        (tác giả/bìa/mô tả) do discover_latest gọi fetch_novel_meta cho truyện MỚI.

        Trang category `/category/{c}.html` phân trang `_2/_3…`; quét luân phiên mọi
        category được phép để một mục đông truyện không chiếm hết pool ứng viên.
        config `discover_paths` có thể override danh sách mặc định."""
        paths = self.config.get("discover_paths") or _DEFAULT_DISCOVER_PATHS
        out: list[NovelMeta] = []
        seen: set[str] = set()
        active = set(paths)
        current_page = page or 1
        while active and len(out) < limit:
            batches: list[list[NovelMeta]] = []
            for base_path in paths:
                if base_path not in active:
                    continue
                path = (base_path if current_page == 1 else
                        re.sub(r"\.html$", f"_{current_page}.html", base_path))
                try:
                    html = self._get(path)
                except Exception:
                    active.discard(base_path)
                    continue
                found = re.findall(r'/n/([a-z0-9_]+)/"[^>]*>([^<]{2,40})<', html)
                if not found:
                    active.discard(base_path)
                    continue
                batch: list[NovelMeta] = []
                for slug, title in found:
                    if slug in seen:
                        continue
                    seen.add(slug)
                    batch.append(NovelMeta(
                        source_novel_id=slug,
                        source_url=f"{self.base_url}{self._novel_url(slug)}",
                        title_zh=unescape(title).strip(),
                    ))
                batches.append(batch)
                time.sleep(0.5)  # lịch sự với nguồn
            for group in zip_longest(*batches):
                out.extend(item for item in group if item is not None)
                if len(out) >= limit:
                    return out[:limit]
            if page:
                break
            current_page += 1
        return out[:limit]

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
        # Trạng thái này thuộc riêng lần tải TOC hiện tại; không để một truyện
        # hoàn thành làm "dính" trạng thái sang truyện kế tiếp của cùng adapter.
        self.last_toc_status = None
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
        # DDXS không có trang/trường trạng thái riêng; tiêu đề cuối là tín hiệu duy nhất.
        self.last_toc_status = (
            "completed" if any(_COMPLETED_TITLE.search(r.title_zh or "") for r in refs[-5:])
            else None)
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

