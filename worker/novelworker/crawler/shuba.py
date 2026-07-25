"""Adapter KHUÔN 69书吧 (shuba, 69shuba.com): trang GBK, metadata og:novel:* đầy đủ.

Khác các khuôn cũ đủ để tách class (probe thật 2026-07-25):
  * 3 URL nằm ở 3 nhánh KHÁC nhau: trang truyện /book/{id}.htm, mục lục /book/{id}/,
    chương /txt/{id}/{cid}. source_chapter_id = "{book_id}/{cid}".
  * Mục lục xếp GIẢM DẦN, số thứ tự nằm ở thuộc tính `data-num` chứ không theo vị trí
    trong HTML → sắp lại theo data-num tăng dần thay vì theo thứ tự xuất hiện.
  * Metadata lấy trọn từ og:novel:* (author/category/status/update_time) — không phải
    bới <title> như dingdian/piaotia.
  * Trang chương: div.txtnav lồng nhiều div con (txtinfo/txtright/contentadv/bottom-ad)
    nên KHÔNG cắt bằng </div> non-greedy được; cắt theo mốc cuối bottom-ad/page1 rồi
    bóc các block phụ. Nguồn chèn <div class="contentadv"> ngay GIỮA thân chương.

Encoding gbk khai qua sources.config.encoding (base._get tự decode).
Đổi cấu trúc nguồn → chỉnh regex ở đây, không đụng base.
"""
from __future__ import annotations

import logging
import re
import time
from html import unescape
from itertools import zip_longest

from .base import ChapterRef, NovelMeta, SourceAdapter

log = logging.getLogger(__name__)

_DEFAULT_AD_MARKERS = ["69书吧", "69shu", "cdnshu", "请记住", "手机阅读", "本书首发", "(本章完)"]

# /novels/class/{c}.htm — chỉ các mục hợp gu app: 1 玄幻魔法, 2 修真武侠, 5 游戏竞技,
# 6 科幻空间, 7 悬疑惊悚, 11 穿越时空. Bỏ 言情/都市/官场/青春校园/历史军事/同人.
# Trang mục KHÔNG phân trang (top ~100 mỗi mục) → page > 1 trả rỗng.
_DEFAULT_DISCOVER_PATHS = tuple(f"/novels/class/{c}.htm" for c in (1, 2, 5, 6, 7, 11))

_STATUS_MAP = {"连载": "ongoing", "完结": "completed", "完本": "completed"}
# Mốc kết thúc thân chương, thử theo thứ tự (nguồn đổi skin thì còn mốc dự phòng).
_END_MARKERS = ('<div class="bottom-ad"', '<div class="page1"', '<div class="page"')


class ShubaAdapter(SourceAdapter):
    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        # /txt/ trả 403 nếu thiếu Referer (kiểm chứng live 2026-07-25) — gắn 1 lần cho
        # cả session thay vì truyền header từng request.
        self._session.headers["Referer"] = f"{self.base_url}/"

    def _novel_url(self, book_id: str) -> str:
        return self.config.get("novel_path", "/book/{book_id}.htm").format(book_id=book_id)

    def _list_url(self, book_id: str) -> str:
        return self.config.get("list_path", "/book/{book_id}/").format(book_id=book_id)

    def _chapter_url(self, book_id: str, cid: str) -> str:
        return self.config.get(
            "chapter_path", "/txt/{book_id}/{chapter_id}").format(
                book_id=book_id, chapter_id=cid)

    @property
    def _ad_markers(self) -> list[str]:
        host = re.sub(r"^https?://(www\.)?", "", self.base_url).split("/")[0]
        return [host, host.split(".")[0], *(self.config.get("ad_markers") or _DEFAULT_AD_MARKERS)]

    @staticmethod
    def _og(html: str, key: str) -> str | None:
        m = re.search(
            r'<meta[^>]+(?:property|name)="' + re.escape(key) + r'"[^>]*content="([^"]*)"', html)
        return unescape(m.group(1)).strip() if m else None

    # ---------- SourceAdapter ----------

    def fetch_latest(self, limit: int = 30, page: int | None = None) -> list[NovelMeta]:
        """Quét các trang mục → (book_id, tên). Metadata đầy đủ do discover_latest gọi
        fetch_novel_meta cho truyện MỚI. Xen kẽ các mục để một mục đông truyện không
        chiếm hết pool ứng viên."""
        if page and page > 1:
            return []  # trang mục không phân trang
        paths = self.config.get("discover_paths") or _DEFAULT_DISCOVER_PATHS
        batches: list[list[tuple[str, str]]] = []
        seen: set[str] = set()
        for path in paths:
            try:
                html = self._get(path)
            except Exception:
                continue
            batch: list[tuple[str, str]] = []
            for m in re.finditer(r'/book/(\d+)\.htm"[^>]*>\s*([^<]{2,40}?)\s*<', html):
                bid, title = m.group(1), unescape(m.group(2)).strip()
                # trang mục lặp mỗi truyện 2 lần (bìa + nút "点击阅读") → giữ lần có tên thật
                if not title or bid in seen or title == "点击阅读":
                    continue
                seen.add(bid)
                batch.append((bid, title))
            if batch:
                batches.append(batch)
            time.sleep(0.5)  # lịch sự với nguồn
        out: list[NovelMeta] = []
        # zip_longest chứ không zip: mục ít truyện hơn không được cắt cụt mục còn lại
        for row in zip_longest(*batches):
            for item in row:
                if item is None:
                    continue
                bid, title = item
                out.append(NovelMeta(
                    source_novel_id=bid,
                    source_url=f"{self.base_url}{self._novel_url(bid)}",
                    title_zh=title,
                ))
                if len(out) >= limit:
                    return out
        return out[:limit]

    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        html = self._get(self._novel_url(source_novel_id))
        title = self._og(html, "og:novel:book_name") or self._og(html, "og:title")
        if not title:
            mh = re.search(r"<h1[^>]*>(.*?)</h1>", html, re.S)
            title = re.sub(r"<[^>]+>", "", mh.group(1)).strip() if mh else None
        if not title:
            raise ValueError(f"Không parse được tên truyện {self.name} cho {source_novel_id}")
        desc = self._og(html, "og:description")
        if desc:
            desc = re.sub(r"<[^>]+>", "", re.sub(r"<br\s*/?>", "\n", desc, flags=re.I)).strip()
        cat = self._og(html, "og:novel:category")
        return NovelMeta(
            source_novel_id=source_novel_id,
            source_url=f"{self.base_url}{self._novel_url(source_novel_id)}",
            title_zh=title,
            author_zh=self._og(html, "og:novel:author"),
            cover_url=self._og(html, "og:image"),
            description_zh=desc or None,
            genres_zh=[cat] if cat else [],
            status=_STATUS_MAP.get(self._og(html, "og:novel:status") or "", "ongoing"),
        )

    def fetch_chapter_list(self, source_novel_id: str) -> list[ChapterRef]:
        # Trạng thái thuộc riêng lần tải TOC này, không "dính" sang truyện kế tiếp.
        self.last_toc_status = None
        html = self._get(self._list_url(source_novel_id))
        # <li data-num="569"><a href=".../txt/{bid}/{cid}">第568章 …</a></li>, xếp GIẢM DẦN.
        pattern = re.compile(
            r'data-num="(\d+)"[^>]*>\s*<a[^>]+href="[^"]*?/txt/'
            + re.escape(source_novel_id) + r'/(\d+)"[^>]*>([^<]+)</a>')
        # dedupe theo cid, GIỮ lần cuối (phòng block lặp ở đầu trang).
        last: dict[str, tuple[int, str]] = {}
        for m in pattern.finditer(html):
            last[m.group(2)] = (int(m.group(1)), unescape(m.group(3)).strip())
        ordered = sorted(last.items(), key=lambda kv: kv[1][0])
        refs = [
            ChapterRef(index=i + 1, source_chapter_id=f"{source_novel_id}/{cid}", title_zh=title)
            for i, (cid, (_, title)) in enumerate(ordered)
        ]
        if not refs:
            raise ValueError(f"Không lấy được mục lục {self.name} cho {source_novel_id}")
        return refs

    def fetch_chapter(self, source_chapter_id: str) -> str:
        book_id, _, cid = source_chapter_id.rpartition("/")
        html = self._get(self._chapter_url(book_id, cid))
        start = html.find('class="txtnav"')
        if start < 0:
            raise ValueError(
                f"Không thấy nội dung chương {source_chapter_id} ({self.name}) — đổi cấu trúc?")
        # bỏ luôn phần đuôi thẻ mở (`class="txtnav">`), nếu không nó lọt xuống text sạch
        seg = html[html.find(">", start) + 1:]
        for mark in _END_MARKERS:
            k = seg.find(mark)
            if k > 0:
                seg = seg[:k]
                break
        # Tiêu đề h1 lặp lại ở dòng đầu thân chương → nhớ để bỏ dòng trùng phía dưới.
        mh = re.search(r"<h1[^>]*>(.*?)</h1>", seg, re.S)
        h1 = unescape(re.sub(r"<[^>]+>", "", mh.group(1))).strip() if mh else ""
        # Bóc block phụ: script quảng cáo, h1, dòng ngày/tác giả (div.txtinfo).
        seg = re.sub(r"<script.*?</script>", "", seg, flags=re.S | re.I)
        seg = re.sub(r"<h1[^>]*>.*?</h1>", "", seg, flags=re.S | re.I)
        seg = re.sub(r'<div[^>]*class="[^"]*txtinfo[^"]*"[^>]*>.*?</div>', "", seg,
                     flags=re.S | re.I)
        raw = re.sub(r"</p\s*>|<br\s*/?>", "\n", seg, flags=re.I)
        raw = re.sub(r"<[^>]+>", "", raw)
        markers = [k.lower() for k in self._ad_markers]
        lines = [ln.strip() for ln in unescape(raw).replace("\xa0", " ").split("\n")]
        lines = [ln for ln in lines if ln and not any(k in ln.lower() for k in markers)]
        if h1 and lines and lines[0] == h1:
            lines.pop(0)
        text = "\n".join(lines).strip()
        # Chương ngắn không phải lỗi (xem biquge.py) — chỉ rỗng mới raise.
        if not text:
            raise ValueError(f"Chương {source_chapter_id} rỗng sau khi lọc — đổi cấu trúc?")
        return text
