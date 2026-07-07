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

from .base import ChapterNotReady, ChapterRef, NovelMeta, SourceAdapter

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
        """TOÀN BỘ bảng xếp hạng tổng lượt đọc → [(source_novel_id, rank)] (rank nhỏ
        = hot). shuhaige `/allvisit/` phân trang (~20 trang × 30 truyện, xếp theo 总点击);
        mỗi dòng `<span class="s2..."><a href="/{id}/">`. Rank = thứ tự xuất hiện toàn cục.
        Nguồn KHÔNG công bố con số lượt đọc — chỉ có thứ hạng. Site khác đổi qua
        config['ranking_path'] / config['ranking_pages']."""
        base = self.config.get("ranking_path", "/allvisit/")
        pages = int(self.config.get("ranking_pages", 20))
        pat = re.compile(r'<span class="s2[^"]*"><a href="/(\d+)/"')
        best: dict[str, int] = {}
        order = 0
        for p in range(1, pages + 1):
            path = base if p == 1 else f"{base}{p}.html"
            try:
                html = self._get(path)
            except Exception:
                log.warning("Không lấy được bảng xếp hạng %s (%s)", path, self.name)
                break  # trang sau cũng sẽ fail — giữ những gì đã có
            found = pat.findall(html)
            if not found:
                break  # hết trang thật / nguồn đổi cấu trúc
            for sid in found:
                if sid not in best:  # giữ lần xuất hiện ĐẦU = hạng cao nhất
                    best[sid] = order
                    order += 1
            if len(best) >= limit:
                break
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
        cover = self._meta(html, "og:image")
        if cover and cover.startswith("//"):  # xbiquge để og:image thiếu scheme
            cover = f"https:{cover}"
        return NovelMeta(
            source_novel_id=source_novel_id,
            source_url=f"{self.base_url}{self._novel_url(source_novel_id)}",
            title_zh=title,
            author_zh=self._meta(html, "og:novel:author"),
            cover_url=cover,
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

    def _extract_content(self, html: str) -> str | None:
        """Bóc text thô trong div nội dung; None nếu trang không có div đó.
        id có thể không phải attr đầu (<div class="x" id="content">) → cho phép attr trước."""
        cid = re.escape(self._content_id)
        m = re.search(r'<div[^>]*\bid=["\']' + cid + r'["\'][^>]*>(.*?)</div>', html, re.S)
        if not m:
            return None
        # <br> (shuhaige) hoặc <p>…</p> (vài clone) đều là ranh giới đoạn → đổi thành
        # xuống dòng trước khi strip tag, tránh dính đoạn thành khối chữ liền.
        raw = re.sub(r"</p\s*>|<br\s*/?>", "\n", m.group(1), flags=re.I)
        return re.sub(r"<[^>]+>", "", raw)

    @staticmethod
    def _is_pagination_junk(line: str) -> bool:
        """Dòng nhắc phân trang nhồi cuối mỗi trang chương ("这章没有结束，请点击下一页
        继续阅读！"…) — meta của site, không phải văn truyện."""
        return "点击下一页" in line or ("下一页" in line and "继续阅读" in line)

    def fetch_chapter(self, source_chapter_id: str) -> str:
        # source_chapter_id = "book_id/chapter_id" (xem fetch_chapter_list)
        book_id, _, chapter_id = source_chapter_id.rpartition("/")
        first_path = self._chapter_url(book_id, chapter_id)
        stem, dot, ext = first_path.rpartition(".")
        # Chương DÀI bị site chia nhiều trang: 123.html, 123_2.html, … — chỉ tải trang 1
        # là chương nào cũng cụt đuôi (bug "mất liền mạch" 2026-07). Tải nối tiếp khi
        # trang hiện tại còn link sang trang kế ("{cid}_{n+1}."); trần 30 trang phòng loop.
        pages: list[str] = []
        page = 1
        while True:
            path = first_path if page == 1 else (
                f"{stem}_{page}.{ext}" if dot else f"{first_path}_{page}")
            html = self._get(path)
            raw = self._extract_content(html)
            if raw is None:
                if page > 1:
                    break  # trang sau lỗi/đổi khuôn — giữ phần đã tải được
                # Chương mới nhất: mục lục đã liệt kê nhưng trang chưa sinh → site redirect
                # về trang truyện (nhận diện qua div#list của mục lục). Lỗi TẠM, không phải
                # đổi cấu trúc — kiểm chứng shuhaige 2026-07.
                if re.search(r'<div[^>]*\bid=["\']list["\']', html):
                    raise ChapterNotReady(
                        f"Chương {source_chapter_id} ({self.name}) chưa có trang trên nguồn")
                raise ValueError(f"Không thấy nội dung chương {source_chapter_id} ({self.name}) — đổi cấu trúc?")
            pages.append(raw)
            if page >= 30 or not re.search(
                    re.escape(chapter_id) + r"_" + str(page + 1) + r"\.", html):
                break
            page += 1
        markers = [k.lower() for k in self._ad_markers]
        lines = [ln.strip() for ln in unescape("\n".join(pages)).split("\n")]
        lines = [ln for ln in lines
                 if ln and not self._is_pagination_junk(ln)
                 and not any(k in ln.lower() for k in markers)]
        text = "\n".join(lines).strip()
        if len(text) < 50:
            raise ValueError(f"Chương {source_chapter_id} quá ngắn ({len(text)} ký tự)")
        return text


class XinBiqugeAdapter(BiqugeAdapter):
    """Khuôn 新笔趣阁 ("书友最值得收藏的免费小说阅读网"): xbiquge.com.cn, uuxs.org,
    xslou.net… Probe thật 2026-07-07, lệch biquge gốc đúng 3 chỗ:

    - book_id 2 tầng "107/107771", URL /book/{book_id}/ → set qua config
      novel_path/chapter_path trong bảng sources, KHÔNG hardcode ở đây.
    - Mục lục PHÂN TRANG /book/{id}/index_{p}.html (trang truyện chỉ ~110 link
      cuối) → lặp trang tới khi không còn chương mới.
    - Nội dung trong <article class="font_max">; mỗi trang chương nhét dòng rác
      "第(1/3)页" ở đầu + cuối.

    Ranking /top/ chỉ 30 truyện hot + /full/ 30 truyện hoàn thành — ít mà chất,
    hợp discover_min_chapters. Gộp trang chương {cid}_2.html dùng lại của cha.
    """

    def fetch_ranking(self, limit: int = 100) -> list[tuple[str, int]]:
        best: dict[str, int] = {}
        order = 0
        for path in self.config.get("ranking_paths", ["/top/", "/full/"]):
            try:
                html = self._get(path)
            except Exception:
                log.warning("Không lấy được ranking %s (%s)", path, self.name)
                continue
            for bid in re.findall(r'href="/book/(\d+/\d+)/"', html):
                if bid not in best:
                    best[bid] = order
                    order += 1
        return sorted(best.items(), key=lambda kv: kv[1])[:limit]

    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        meta = super().fetch_novel_meta(source_novel_id)
        # og:title của khuôn này = "Tên truyện最新章节" → cắt đuôi SEO
        meta.title_zh = re.sub(r"最新章节$", "", meta.title_zh).strip()
        return meta

    def fetch_chapter_list(self, source_novel_id: str) -> list[ChapterRef]:
        # Trang 1 = trang truyện, trang p ≥ 2 = index_{p}.html; các trang xếp 1→N.
        # MỌI trang đều lặp block 最新章节 (div.book_list) TRƯỚC list đầy đủ
        # (div.book_list2) → chỉ parse từ book_list2 trở đi, khỏi loạn thứ tự.
        # Trang quá cuối được site trả về = trang 1 → không có chương mới → dừng.
        pattern = re.compile(
            r'<a href="[^"]*?/' + re.escape(source_novel_id) + r'/(\d+)\.html"[^>]*>([^<]+)</a>')
        base_path = self._novel_url(source_novel_id)
        seen: dict[str, str] = {}   # cid -> title, dict giữ thứ tự xuất hiện
        for p in range(1, 301):  # trần 300 trang ≈ 30k chương, phòng loop
            html = self._get(base_path if p == 1 else f"{base_path}index_{p}.html")
            body = html.split("book_list2", 1)[-1]  # thiếu marker → dùng cả trang
            fresh = 0
            for m in pattern.finditer(body):
                cid = m.group(1)
                if cid not in seen:
                    seen[cid] = unescape(m.group(2)).strip()
                    fresh += 1
            if not fresh:
                break
        refs = [
            ChapterRef(index=i + 1, source_chapter_id=f"{source_novel_id}/{cid}", title_zh=title)
            for i, (cid, title) in enumerate(seen.items())
        ]
        if not refs:
            raise ValueError(f"Không lấy được mục lục {self.name} cho {source_novel_id}")
        return refs

    def _extract_content(self, html: str) -> str | None:
        m = re.search(
            r'<article[^>]*class="[^"]*font_max[^"]*"[^>]*>(.*?)</article>', html, re.S)
        if not m:
            return None
        raw = re.sub(r"</p\s*>|<br\s*/?>", "\n", m.group(1), flags=re.I)
        return re.sub(r"<[^>]+>", "", raw)

    @staticmethod
    def _is_pagination_junk(line: str) -> bool:
        return (BiqugeAdapter._is_pagination_junk(line)
                or re.fullmatch(r"第\s*\(\d+/\d+\)\s*页", line) is not None)

