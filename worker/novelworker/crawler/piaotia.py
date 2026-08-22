"""Adapter KHUÔN 飘天文学 (piaotia / ptwxz, piaotia.com): trang GBK cũ kiểu tĩnh.

Khác dingdian ở 3 điểm nên tách khuôn riêng:
  * ID truyện là CẶP {a}/{bid} (thư mục con), không phải 1 slug — bookinfo ở
    /bookinfo/{a}/{bid}.html, mục lục ở /html/{a}/{bid}/, chương ở
    /html/{a}/{bid}/{cid}.html. source_chapter_id = "{a}/{bid}/{cid}".
  * Encoding gbk (khai qua sources.config.encoding, base._get tự decode).
  * Trang chương KHÔNG có div nội dung sạch: chữ nằm thô ngay sau </h1>, nên
    fetch_chapter thử div#content trước rồi mới cắt phần sau </h1>.

Nguồn hay chèn dòng quảng cáo (飘天文学 / 手机阅读 / tên miền) — lọc theo ad markers
giống các khuôn khác. Đổi cấu trúc nguồn → chỉnh regex ở đây, không đụng base.
"""
from __future__ import annotations

import logging
import re
from html import unescape

from .base import ChapterRef, NovelMeta, SourceAdapter, parse_cn_number

log = logging.getLogger(__name__)

_DEFAULT_AD_MARKERS = ["飘天文学", "piaotia", "ptwxz", "手机阅读", "请记住", "本书首发", "txt下载"]


class PiaotiaAdapter(SourceAdapter):
    def _novel_url(self, book_id: str) -> str:
        return self.config.get("novel_path", "/bookinfo/{book_id}.html").format(book_id=book_id)

    def _list_url(self, book_id: str) -> str:
        return self.config.get("list_path", "/html/{book_id}/").format(book_id=book_id)

    def _chapter_url(self, book_id: str, cid: str) -> str:
        return self.config.get(
            "chapter_path", "/html/{book_id}/{chapter_id}.html").format(
                book_id=book_id, chapter_id=cid)

    @property
    def _ad_markers(self) -> list[str]:
        host = re.sub(r"^https?://(www\.)?", "", self.base_url).split("/")[0]
        return [host, host.split(".")[0], *(self.config.get("ad_markers") or _DEFAULT_AD_MARKERS)]

    def fetch_latest(
        self, limit: int = 30, page: int | None = None,
    ) -> list[NovelMeta]:
        # Trang chủ piaotia liệt kê bookinfo link kèm tên truyện; không phân trang
        # kiểu số nên page > 1 trả rỗng để frontier khỏi quét lặp.
        if page and page > 1:
            return []
        home = self._get("/")
        seen: dict[str, str] = {}
        for m in re.finditer(
                r'/bookinfo/(\d+)/(\d+)\.html"[^>]*>([^<]{2,40})<', home):
            book_id = f"{m.group(1)}/{m.group(2)}"
            title = unescape(m.group(3)).strip()
            if title and book_id not in seen:
                seen[book_id] = title
        metas = [
            NovelMeta(
                source_novel_id=bid,
                source_url=f"{self.base_url}{self._novel_url(bid)}",
                title_zh=title,
            )
            for bid, title in seen.items()
        ]
        return metas[:limit]

    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        html = self._get(self._novel_url(source_novel_id))
        # Tên truyện: ưu tiên <h1>, fallback token đầu của <title> (cắt theo dấu
        # phân cách phổ biến 最新章节 / _ / - / , mà piaotia dùng).
        title = None
        mh = re.search(r"<h1[^>]*>(.*?)</h1>", html, re.S)
        if mh:
            title = re.sub(r"<[^>]+>", "", mh.group(1)).strip()
        if not title:
            mt = re.search(r"<title>(.*?)</title>", html, re.S)
            if mt:
                title = re.split(r"最新章节|_|-|,|，", unescape(mt.group(1)).strip())[0].strip()
        if not title:
            raise ValueError(f"Không parse được tên truyện {self.name} cho {source_novel_id}")
        # Bảng info của bookinfo giãn nhãn bằng &nbsp; ("类&nbsp;&nbsp;&nbsp; 别：") nên
        # \s không khớp — phải cho phép cả entity giữa các chữ.
        _gap = r"(?:&nbsp;|\s)*"
        ma = re.search(rf"作{_gap}者{_gap}[：:]{_gap}([^<\n,，]+)", html)
        if not ma:
            # trang thật không có nhãn "作者："; tác giả nằm trong <title> dạng
            # "Tên最新章节,<Tác giả>作品选-飘天文学" (kiểm chứng live 2026-07-25).
            ma = re.search(r"[,，]\s*([^,，<]+?)作品选", html)
        author = unescape(ma.group(1)).strip() if ma else None
        mc = re.search(r'<img[^>]+src="([^"]+/files/article/image/[^"]+)"', html)
        mg = re.search(rf"类{_gap}别{_gap}[：:]{_gap}([^<]+)", html)
        genres = [g] if mg and (g := unescape(mg.group(1)).strip()) else []
        ms = re.search(rf"文章状态{_gap}[：:]{_gap}([^<]+)", html)
        st = unescape(ms.group(1)).strip() if ms else ""
        # 内容简介：<br />ND<br /><br /> ... </td> — cắt tới </td> rồi bóc tag.
        desc = None
        md = re.search(r"内容简介[：:]\s*</span>(.*?)</td>", html, re.S)
        if md:
            d = re.sub(r"</p\s*>|<br\s*/?>", "\n", md.group(1), flags=re.I)
            d = re.sub(r"<[^>]+>", "", unescape(d)).replace("　", " ")
            desc = "\n".join(ln.strip() for ln in d.split("\n") if ln.strip()) or None
        # Bảng info còn: 全文长度：1741012字 · 最后更新：2023-09-02 · 收藏数 · 总推荐数.
        # Nhãn giãn bằng &nbsp; nên dùng lại _gap.
        def _labeled(label: str) -> str | None:
            pattern = _gap.join(label) + _gap + r"[：:]" + _gap + r"([^<\n]+)"
            m = re.search(pattern, html)
            return unescape(m.group(1)).strip() if m else None

        stats = {k: v for k, v in {
            "updated_at": _labeled("最后更新"),
            "favorites": parse_cn_number(_labeled("收藏数")),
            "recommends": parse_cn_number(_labeled("总推荐数")),
            "first_release": _labeled("首发状态"),
        }.items() if v}
        return NovelMeta(
            source_novel_id=source_novel_id,
            source_url=f"{self.base_url}{self._novel_url(source_novel_id)}",
            title_zh=title,
            author_zh=author,
            cover_url=mc.group(1) if mc else None,
            description_zh=desc,
            genres_zh=genres,
            status="completed" if st in ("已完成", "完本", "完结") else "ongoing",
            word_count=parse_cn_number(_labeled("全文长度")),
            stats=stats,
        )

    def fetch_chapter_list(self, source_novel_id: str) -> list[ChapterRef]:
        self.last_toc_status = None
        html = self._get(self._list_url(source_novel_id))
        # Neo chương là số.html tương đối trong thư mục truyện; fallback bắt cả
        # đường dẫn đầy đủ khi template bọc thêm host.
        anchors = re.findall(r'<a\s+href="(\d+)\.html"[^>]*>([^<]+)</a>', html)
        if not anchors:
            anchors = re.findall(
                r'<a[^>]+href="[^"]*?/(\d+)\.html"[^>]*>([^<]+)</a>', html)
        last: dict[str, tuple[int, str]] = {}
        for order, (cid, title) in enumerate(anchors):
            last[cid] = (order, unescape(title).strip())
        ordered = sorted(last.items(), key=lambda kv: kv[1][0])
        refs = [
            ChapterRef(
                index=i + 1,
                source_chapter_id=f"{source_novel_id}/{cid}",
                title_zh=title,
            )
            for i, (cid, (_, title)) in enumerate(ordered)
        ]
        if not refs:
            raise ValueError(f"Không lấy được mục lục {self.name} cho {source_novel_id}")
        return refs

    def fetch_chapter(self, source_chapter_id: str) -> str:
        book_id, _, cid = source_chapter_id.rpartition("/")
        html = self._get(self._chapter_url(book_id, cid))
        m = re.search(r'<div[^>]*id="content"[^>]*>(.*?)</div>', html, re.S)
        if m:
            seg = m.group(1)
        else:
            # piaotia thô: chữ nằm trần giữa </H1> và <div class="bottomlink">, KHÔNG có
            # thẻ bọc. Chú ý 2 điểm chỉ lộ ra khi chạy live (2026-07-25):
            #   * trang viết </H1> HOA → bắt buộc re.I
            #   * ngay sau </H1> là khối điều hướng (div.toplink + table script chọn
            #     màu nền) rồi mới tới chữ → cắt tới bottomlink rồi BÓC khối đó ra,
            #     cắt ở '<div' đầu tiên thì chỉ nhặt được chuỗi rỗng.
            mh = re.search(r"</h1>", html, re.I)
            if not mh:
                raise ValueError(
                    f"Không thấy nội dung chương {source_chapter_id} ({self.name}) — đổi cấu trúc?")
            mb = re.search(r'<div[^>]*class="bottomlink"', html, re.I)
            seg = html[mh.end():mb.start() if mb else len(html)]
            seg = re.sub(r"<script.*?</script>", "", seg, flags=re.S | re.I)
            seg = re.sub(r"<table.*?</table>", "", seg, flags=re.S | re.I)
            seg = re.sub(r'<div[^>]*class="toplink".*?</div>', "", seg, flags=re.S | re.I)
        raw = re.sub(r"</p\s*>|<br\s*/?>", "\n", seg, flags=re.I)
        raw = re.sub(r"<[^>]+>", "", raw)
        markers = [k.lower() for k in self._ad_markers]
        lines = [ln.strip() for ln in unescape(raw).replace("\xa0", " ").split("\n")]
        lines = [ln for ln in lines if ln and not any(k in ln.lower() for k in markers)]
        text = "\n".join(lines).strip()
        if not text:
            raise ValueError(f"Chương {source_chapter_id} rỗng sau khi lọc — đổi cấu trúc?")
        return text
