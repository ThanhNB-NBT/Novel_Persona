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
    adapter = FalooAdapter(
        "https://wap.faloo.com",
        {"encoding": "gb18030", "discover_paths": ["/category_2_1.html"]},
        {"name": "faloo"},
    )

    adapter._get = lambda _: (
        '<div class="show_title2"><a href="//wap.faloo.com/new_123.html"><b>Kiếm Tiên</b></a></div>'
        '<div class="show_title2"><a href="//wap.faloo.com/new_123.html">trùng</a></div>'
        '<a href="//wap.faloo.com/new_123_1.html">chương, không phải truyện</a>'
    )
    latest = adapter.fetch_latest()
    assert [(item.source_novel_id, item.title_zh) for item in latest] == [("123", "Kiếm Tiên")]

    pages = {
        "/category_2_1.html": (
            '<div class="show_title2"><a href="/new_101.html">Truyện 101</a></div>'
            '<div class="show_title2"><a href="/new_102.html">Truyện 102</a></div>'),
        "/category_2_2.html": (
            '<div class="show_title2"><a href="/new_102.html">Truyện 102 trùng</a></div>'
            '<div class="show_title2"><a href="/new_103.html">Truyện 103</a></div>'),
    }
    adapter._get = lambda path: pages.get(path, "")
    latest = adapter.fetch_latest(limit=3)
    assert [item.source_novel_id for item in latest] == ["101", "102", "103"]
    assert [item.source_novel_id for item in adapter.fetch_latest(limit=3, page=2)] == [
        "102", "103"]

    # Config production cũ category 2 phải tự mở rộng sang mọi nhóm được phép.
    touched = []
    broad = FalooAdapter(
        "https://wap.faloo.com",
        {"encoding": "gb18030", "latest_path": "/category_2_1.html"},
        {"name": "faloo"},
    )
    broad._get = lambda path: touched.append(path) or "<p>hết</p>"
    assert broad.fetch_latest(limit=10) == []
    assert touched == [f"/category_{i}_1.html" for i in (1, 6, 2, 5)]

    broad = FalooAdapter(
        "https://wap.faloo.com",
        {"discover_paths": ["/category_1_1.html", "/category_6_1.html"]},
        {"name": "faloo"},
    )
    broad._get = lambda path: {
        "/category_1_1.html": (
            '<div class="show_title2"><a href="/new_11.html">玄幻一</a></div>'
            '<div class="show_title2"><a href="/new_12.html">玄幻二</a></div>'),
        "/category_6_1.html": (
            '<div class="show_title2"><a href="/new_61.html">仙侠一</a></div>'
            '<div class="show_title2"><a href="/new_62.html">仙侠二</a></div>'),
    }.get(path, "")
    assert [x.source_novel_id for x in broad.fetch_latest(limit=2)] == ["11", "61"]

    broad._get = lambda path: (
        '<div class="show_title2"><a href="//wap.faloo.com/99.html">完本玄幻</a></div>'
        if path == "/finish_0_0_0_1.html" else "")
    completed = broad.fetch_completed(limit=1)
    assert [(x.source_novel_id, x.status) for x in completed] == [("99", "completed")]

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

    # Faloo có lúc soft-block riêng WAP trên IP VPS: HTTP 200 nhưng không có h1.
    fallback_html = (
        '<h1>Kiếm Tiên dự phòng</h1>'
        '<meta name="description" content="Mô tả desktop">'
        '<meta property="og:image" content="http://img.test/desktop.jpg">'
        '<meta name="og:novel:author" content="Tác Giả desktop">'
        '<meta name="og:novel:category" content="仙侠小说">'
    )
    paths = []
    adapter._get = lambda path: (
        catalog_html if "booklist" in path else
        fallback_html if path.startswith("https://b.faloo.com/") else
        paths.append(path) or '<title>系统提示</title>'
    )
    fallback = adapter.fetch_novel_meta("123")
    assert fallback.title_zh == "Kiếm Tiên dự phòng"
    assert fallback.author_zh == "Tác Giả desktop" and fallback.genres_zh == ["仙侠小说"]
    assert fallback.cover_url == "https://img.test/desktop.jpg"
    assert paths == ["/new_123.html"]

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

    # trang chống bot 系统提示 (HTTP 200) → SourceBlocked, không phải lỗi dữ liệu
    from novelworker.crawler.base import SourceBlocked
    adapter._get = lambda _: "<title>系统提示</title>"
    for call in (lambda: adapter.fetch_novel_meta("999"),
                 lambda: adapter.fetch_chapter_list("999"),
                 lambda: adapter.fetch_chapter("999/1")):
        try:
            call()
            raise AssertionError("trang chống bot phải raise SourceBlocked")
        except SourceBlocked:
            pass


if __name__ == "__main__":
    main()
    print("OK — Faloo free-only adapter")
