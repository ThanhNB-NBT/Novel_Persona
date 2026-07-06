"""Self-check khuôn biquge: parse metadata/mục lục/chương từ HTML canned (không mạng)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.biquge import BiqugeAdapter
from novelworker.crawler.registry import TEMPLATE_REGISTRY


def _adapter(config=None):
    a = BiqugeAdapter(base_url="https://www.shuhaige.net", config=config or {},
                      source_row={"name": "shuhaige"})
    return a


def main() -> None:
    assert TEMPLATE_REGISTRY["biquge"] is BiqugeAdapter

    a = _adapter()
    # URL build từ config mặc định + override
    assert a._novel_url("59979") == "/59979/"
    assert a._chapter_url("59979", "123") == "/59979/123.html"
    b = _adapter({"novel_path": "/book/{book_id}/", "chapter_path": "/book/{book_id}/{chapter_id}"})
    assert b._novel_url("7") == "/book/7/" and b._chapter_url("7", "9") == "/book/7/9"

    # metadata: title/author/status/category/intro
    html_novel = (
        '<meta property="og:title" content="测试小说">'
        '<meta property="og:novel:author" content="某作者">'
        '<meta property="og:novel:status" content="已完结">'
        '<meta property="og:novel:category" content="玄幻">'
        '<meta property="og:novel:update_time" content="2026-07-01 12:30">'
        '<div id="intro">这是简介。</div>'
        # block "mới nhất" ở đầu (thứ tự đảo) + mục lục đầy đủ phía dưới
        '<a href="/59979/2.html">第二章</a>'
        '<a href="/59979/1.html">第一章</a>'
        '<a href="/59979/2.html">第二章 continued</a>'
    )
    a._get = lambda p: html_novel
    m = a.fetch_novel_meta("59979")
    assert m.title_zh == "测试小说" and m.author_zh == "某作者"
    assert m.status == "completed" and m.genres_zh == ["玄幻"]
    assert m.description_zh == "这是简介。"
    assert m.last_chapter_at is not None and m.last_chapter_at.year == 2026

    # mục lục: dedupe theo cid GIỮ lần cuối, sắp 1→N; source_chapter_id = "book/cid"
    refs = a.fetch_chapter_list("59979")
    assert [(r.index, r.source_chapter_id) for r in refs] == [(1, "59979/1"), (2, "59979/2")]
    assert refs[1].title_zh == "第二章 continued"  # bản xuất hiện cuối thắng

    # chương: br→\n, lọc dòng footer (笔趣阁/请记住本站/手机版), giữ câu văn thật
    p1, p2 = "第一段" + "字" * 30, "第二段" + "文" * 30
    a._get = lambda p: (
        f'<div id="content">{p1}。<br/>{p2}。<br>'
        '请记住本站笔趣阁 www.shuhaige.net<br>手机版</div>'
    )
    txt = a.fetch_chapter("59979/1")
    assert txt == f"{p1}。\n{p2}。", repr(txt)

    # content_id override
    c = _adapter({"content_id": "chaptercontent"})
    c._get = lambda p: '<div id="chaptercontent">' + "内容" * 30 + "</div>"
    assert len(c.fetch_chapter("1/2")) >= 50


if __name__ == "__main__":
    main()
    print("OK — biquge adapter test pass")
