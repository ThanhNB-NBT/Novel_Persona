"""Self-check Faloo: metadata, discovery, lọc VIP và đọc chương miễn phí."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.faloo import FalooAdapter
from novelworker.crawler.registry import TEMPLATE_REGISTRY
from novelworker.crawler.sync import _skip_by_source_policy
from novelworker.config import settings


def main() -> None:
    assert TEMPLATE_REGISTRY["faloo"] is FalooAdapter
    adapter = FalooAdapter("https://wap.faloo.com", {"encoding": "gb18030"}, {"name": "faloo"})

    adapter._get = lambda _: (
        '<a href="//wap.faloo.com/new_123.html"><b>Kiếm Tiên</b></a>'
        '<a href="//wap.faloo.com/new_123.html">trùng</a>'
        '<a href="//wap.faloo.com/new_123_1.html">chương, không phải truyện</a>'
    )
    latest = adapter.fetch_latest()
    assert [(item.source_novel_id, item.title_zh) for item in latest] == [("123", "Kiếm Tiên")]

    meta_html = (
        '<div class="book_info"><img src="//img.test/cover.jpg"></div>'
        '<h1>Kiếm Tiên</h1><h2>作者</h2>：<a>Tác Giả</a>'
        '<h2>大类</h2>：<a>玄幻</a><h2>小类</h2>：<a>东方</a>'
        '<h2>状态：完成</h2><div id="info2"><p>Mô tả đầy đủ</p></div>本书已更88章'
    )
    catalog_html = (
        '<li><a href="//wap.faloo.com/123_1.html">Chương 1</a></li>'
        '<li><a href="//wap.faloo.com/123_2.html"><span class="v_0">V</span>VIP</a></li>'
        '<li><a href="//wap.faloo.com/123_3.html">Chương 3</a></li>'
    )
    adapter._get = lambda path: catalog_html if "booklist" in path else meta_html
    meta = adapter.fetch_novel_meta("123")
    assert (meta.title_zh, meta.author_zh, meta.status, meta.chapter_count) == (
        "Kiếm Tiên", "Tác Giả", "completed", 2)
    assert meta.cover_url == "https://img.test/cover.jpg" and meta.genres_zh == ["玄幻", "东方"]

    old_threshold = settings.faloo_free_chapter_threshold
    settings.faloo_free_chapter_threshold = 2
    try:
        assert _skip_by_source_policy(adapter, meta) is True  # đúng ngưỡng vẫn loại
        meta.chapter_count = 3
        assert _skip_by_source_policy(adapter, meta) is False
    finally:
        settings.faloo_free_chapter_threshold = old_threshold

    adapter._get = lambda _: (
        '<li><a href="//wap.faloo.com/123_1.html">Chương 1 vip trong tựa</a></li>'
        '<li><a href="//wap.faloo.com/123_2.html"><span class="v_0">V</span>Chương VIP</a></li>'
        '<li><a href="//wap.faloo.com/123_3.html">Chương 3</a></li>'
    )
    refs = adapter.fetch_chapter_list("123")
    assert [ref.source_chapter_id for ref in refs] == ["123/1", "123/3"]

    body = "Nội dung công khai. " + "chữ " * 20
    adapter._get = lambda _: f'<div class="nodeContent">{body}<br>飞卢小说网提醒：rác</div><div class="nodeEnd">end</div>'
    assert adapter.fetch_chapter("123/1") == body.strip()
    adapter._get = lambda _: '<div class="nodeContent">请登录后订阅</div><div class="nodeEnd">end</div>'
    try:
        adapter.fetch_chapter("123/2")
        raise AssertionError("VIP phải bị chặn")
    except ValueError as error:
        assert "VIP" in str(error)


if __name__ == "__main__":
    main()
    print("OK — Faloo free-only adapter")
