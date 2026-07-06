"""Adapter KHUÔN biquge (笔趣阁 & clone: shuhaige, biqulao, xsbique, ddxs, uuxs, quanben5…).

Cả họ biquge chung 1 khuôn HTML tĩnh: trang truyện /{book}/ có meta og:* + danh
sách <dd><a> mục lục; chương ở /{book}/{cid}.html trong div#content, plain text +
<br>. Không Cloudflare, không font-obfuscation. → 1 class, mỗi site = 1 dòng
`sources` (base_url + config override phần lệch), KHÔNG viết class mới.

`config` (jsonb) override mặc định khi site lệch:
    novel_path   : "/{book_id}/"                 trang truyện + mục lục
    chapter_path : "/{book_id}/{chapter_id}.html" trang 1 chương
    content_id   : "content"                       id div nội dung chương
    ad_markers   : []                              chuỗi phụ cần lọc ở cuối chương
    encoding     : "utf-8"

Kiểm chứng chạy thật với shuhaige.net 2026-07. Site khác cần test trước khi bật
(selector có thể lệch nhẹ → thêm vào config).
"""
from __future__ import annotations

import logging
import re
from datetime import datetime
from html import unescape

from .base import ChapterRef, NovelMeta, SourceAdapter

log = logging.getLogger(__name__)

# Rác điều hướng/quảng cáo hay gặp ở cuối chương mọi clone biquge.
# Chỉ chuỗi đặc trưng footer — KHÔNG dùng ".com/www." (nuốt nhầm câu văn có nhắc URL).
_DEFAULT_AD_MARKERS = ["请记住本站", "手机版", "笔趣阁"]


class BiqugeAdapter(SourceAdapter):
    @property
    def _content_id(self) -> str:
        return self.config.get("content_id", "content")

    @property
    def _ad_markers(self) -> list[str]:
        # host nguồn (shuhaige/…) + marker mặc định + override từ config.
        host = re.sub(r"^https?://(www\.)?", "", self.base_url).split("/")[0]
        base = self.config.get("ad_markers") or _DEFAULT_AD_MARKERS
        return [host, host.split(".")[0], *base]

    def _novel_url(self, book_id: str) -> str:
        return self.config.get("novel_path", "/{book_id}/").format(book_id=book_id)

    def _chapter_url(self, book_id: str, chapter_id: str) -> str:
        return self.config.get(
            "chapter_path", "/{book_id}/{chapter_id}.html"
        ).format(book_id=book_id, chapter_id=chapter_id)

    @staticmethod
    def _meta(html: str, prop: str) -> str | None:
        m = re.search(r'<meta property="' + re.escape(prop) + r'"[^>]*content="([^"]*)"', html)
        return unescape(m.group(1)).strip() if m else None

    # ---------- SourceAdapter ----------

    def fetch_latest(self, limit: int = 30) -> list[NovelMeta]:
        # Discovery của biquge đi qua fetch_ranking (bảng xếp hạng), không phải fetch_latest.
        return []

    def fetch_ranking(self, limit: int = 100) -> list[tuple[str, int]]:
        """Bảng xếp hạng nguồn → [(source_novel_id, rank)] (rank nhỏ = hot). shuhaige
        `/top.html` (总点击...): mỗi mục là `<span class="num">N.</span><a href="/{id}/">`.
        Rank = thứ tự XUẤT HIỆN đầu trang (mục 总点击 đứng đầu → hạng thấp nhất). Site khác
        đổi qua config['ranking_path']."""
        path = self.config.get("ranking_path", "/top.html")
        try:
            html = self._get(path)
        except Exception:
            log.warning("Không lấy được bảng xếp hạng %s (%s)", path, self.name)
            return []
        pat = re.compile(r'<span class="num">\d+\.</span><a href="/(\d+)/"')
        best: dict[str, int] = {}
        for order, m in enumerate(pat.finditer(html)):
            sid = m.group(1)
            if sid not in best:  # giữ lần xuất hiện ĐẦU = hạng cao nhất
                best[sid] = order
        return sorted(best.items(), key=lambda kv: kv[1])[:limit]

    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        html = self._get(self._novel_url(source_novel_id))
        title = self._meta(html, "og:title")
        if not title:
            raise ValueError(f"Không parse được truyện {source_novel_id} ({self.name}) — đổi cấu trúc?")
        status = "completed" if (self._meta(html, "og:novel:status") or "").startswith(
            ("完", "已完")) else "ongoing"
        cat = self._meta(html, "og:novel:category")
        # og:description thường là boilerplate quảng cáo站 → ưu tiên div#intro (tóm tắt thật)
        m = re.search(r'<div id="intro"[^>]*>(.*?)</div>', html, re.S)
        if m:
            desc = re.sub(r"<[^>]+>", "", m.group(1)).strip()
            desc = re.sub(r"\.{2,}《.*?》\s*$", "", desc).strip()  # bỏ đuôi "...《Tên》"
        else:
            desc = self._meta(html, "og:description")
        last_at = None
        raw_time = self._meta(html, "og:novel:update_time")
        if raw_time:
            try:
                last_at = datetime.strptime(raw_time.strip(), "%Y-%m-%d %H:%M")
            except ValueError:
                pass
        return NovelMeta(
            source_novel_id=source_novel_id,
            source_url=f"{self.base_url}{self._novel_url(source_novel_id)}",
            title_zh=title,
            author_zh=self._meta(html, "og:novel:author"),
            cover_url=self._meta(html, "og:image"),
            description_zh=desc,
            genres_zh=[cat] if cat else [],
            status=status,
            last_chapter_at=last_at,
        )

    def fetch_chapter_list(self, source_novel_id: str) -> list[ChapterRef]:
        html = self._get(self._novel_url(source_novel_id))
        # Trang có block "最新章节" (mục mới nhất) trùng mục lục đầy đủ phía dưới.
        # Dedupe theo chapter_id GIỮ lần xuất hiện cuối (block đầy đủ, đúng thứ tự 1→N).
        pattern = re.compile(
            r'<a href="[^"]*?/' + re.escape(source_novel_id) + r'/(\d+)\.html"[^>]*>([^<]+)</a>')
        last: dict[str, tuple[int, str]] = {}
        for order, m in enumerate(pattern.finditer(html)):
            cid, title = m.group(1), unescape(m.group(2)).strip()
            last[cid] = (order, title)
        ordered = sorted(last.items(), key=lambda kv: kv[1][0])
        # URL chương cần cả book_id → nhúng vào source_chapter_id dạng "book/cid".
        refs = [
            ChapterRef(index=i + 1, source_chapter_id=f"{source_novel_id}/{cid}", title_zh=title)
            for i, (cid, (_, title)) in enumerate(ordered)
        ]
        if not refs:
            raise ValueError(f"Không lấy được mục lục {self.name} cho {source_novel_id}")
        return refs

    def fetch_chapter(self, source_chapter_id: str) -> str:
        # source_chapter_id = "book_id/chapter_id" (xem fetch_chapter_list)
        book_id, _, chapter_id = source_chapter_id.rpartition("/")
        html = self._get(self._chapter_url(book_id, chapter_id))
        # id có thể không phải attr đầu (<div class="x" id="content">) → cho phép attr trước.
        cid = re.escape(self._content_id)
        m = re.search(r'<div[^>]*\bid=["\']' + cid + r'["\'][^>]*>(.*?)</div>', html, re.S)
        if not m:
            raise ValueError(f"Không thấy nội dung chương {source_chapter_id} ({self.name}) — đổi cấu trúc?")
        # <br> (shuhaige) hoặc <p>…</p> (vài clone) đều là ranh giới đoạn → đổi thành
        # xuống dòng trước khi strip tag, tránh dính đoạn thành khối chữ liền.
        raw = re.sub(r"</p\s*>|<br\s*/?>", "\n", m.group(1), flags=re.I)
        raw = re.sub(r"<[^>]+>", "", raw)
        markers = [k.lower() for k in self._ad_markers]
        lines = [ln.strip() for ln in unescape(raw).split("\n")]
        lines = [ln for ln in lines if ln and not any(k in ln.lower() for k in markers)]
        text = "\n".join(lines).strip()
        if len(text) < 50:
            raise ValueError(f"Chương {source_chapter_id} quá ngắn ({len(text)} ký tự)")
        return text

