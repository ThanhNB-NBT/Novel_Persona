"""Self-check khuôn dingdian (ddxs): meta từ <title>, mục lục trang riêng, content div.articlebody."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.dingdian import DingdianAdapter
from novelworker.crawler.registry import TEMPLATE_REGISTRY


def main() -> None:
    assert TEMPLATE_REGISTRY["dingdian"] is DingdianAdapter
    a = DingdianAdapter(base_url="https://www.dingdian-xiaoshuo.com", config={},
                        source_row={"name": "ddxs"})
    assert a._novel_url("niwen_2") == "/n/niwen_2/"
    assert a._list_url("niwen_2") == "/n/niwen_2/xiaoshuo.html"
    assert a._chapter_url("niwen_2", "9296") == "/n/niwen_2/9296.html"

    # meta: <title>《Tên》Tác giả; description escape 2 lần
    novel_html = (
        "<title>《逆问》小洛儿 - 顶点小说网</title>"
        '<meta name="description" content="《逆问》作者:小洛儿,简介:不求名&amp;lt;br /&amp;gt;只求飞升">'
        '<img src="https://img.x/upload/book_images/38/37418.jpg">'
    )
    a._get = lambda p: novel_html
    m = a.fetch_novel_meta("niwen_2")
    assert m.title_zh == "逆问" and m.author_zh == "小洛儿"
    assert m.cover_url and "book_images" in m.cover_url
    assert m.description_zh == "不求名\n只求飞升", repr(m.description_zh)  # br → \n, hết &lt;

    # mục lục: block "mới nhất" (đảo) ở trên + list đầy đủ dưới; dedupe GIỮ lần cuối
    # (lần trong list đầy đủ) → thứ tự 1→N đúng.
    list_html = (
        # block latest (mới nhất trước)
        '<a href="/n/niwen_2/9297.html" itemprop="url"><span itemprop="name">第二章 (latest)</span></a>'
        # list đầy đủ
        '<a href="/n/niwen_2/9296.html" itemprop="url"><span itemprop="name">第一章 千道宗</span></a>'
        '<a href="/n/niwen_2/9297.html" itemprop="url"><span itemprop="name">第二章 无情子</span></a>'
    )
    a._get = lambda p: list_html
    refs = a.fetch_chapter_list("niwen_2")
    assert [(r.index, r.source_chapter_id) for r in refs] == [(1, "niwen_2/9296"), (2, "niwen_2/9297")]
    assert refs[1].title_zh == "第二章 无情子"  # bản trong list đầy đủ (lần cuối) thắng

    a._get = lambda p: (
        '<a href="/n/niwen_2/1.html">第一章</a>'
        '<a href="/n/niwen_2/2.html">完本感言</a>')
    a.fetch_chapter_list("niwen_2")
    assert a.last_toc_status == "completed"

    # chương: content div.articlebody, br→\n, lọc footer 顶点/host
    body = "夜色，很静。" + "字" * 60
    a._get = lambda p: (
        f'<div class="articlebody">{body}<br/>顶点小说网 请记住<br>手机版</div>'
    )
    txt = a.fetch_chapter("niwen_2/9296")
    assert txt == body, repr(txt)

    # content_class override
    b = DingdianAdapter(base_url="https://x.com", config={"content_class": "content"},
                        source_row={"name": "x"})
    b._get = lambda p: '<div class="read content box">' + "内容" * 30 + "</div>"
    assert len(b.fetch_chapter("s/1")) >= 50

    # fetch_latest: phân trang category, dedupe slug, dừng khi trang rỗng, cắt theo limit
    pages = {
        "/category/1.html": '<a href="/n/aaa/">绝世神通</a><a href="/n/bbb/">武噬蛮荒</a>',
        "/category/1_2.html": '<a href="/n/bbb/">武噬蛮荒 dup</a><a href="/n/ccc/">将倾</a>',
        "/category/1_3.html": "<p>hết</p>",  # không còn slug mới → dừng
    }

    def fake_get(p):
        if p not in pages:
            raise Exception("404")
        return pages[p]

    d = DingdianAdapter(base_url="https://x.com",
                        config={"discover_paths": ["/category/1.html"]},
                        source_row={"name": "ddxs"})
    d._get = fake_get
    res = d.fetch_latest(limit=10)
    assert [m.source_novel_id for m in res] == ["aaa", "bbb", "ccc"], [m.source_novel_id for m in res]
    assert res[0].source_url == "https://x.com/n/aaa/"
    assert len(d.fetch_latest(limit=2)) == 2  # limit cắt đúng

    # Mặc định phải chạm mọi category được phép, không còn khóa cứng category 1.
    touched = []
    d = DingdianAdapter(base_url="https://x.com", config={}, source_row={"name": "ddxs"})
    d._get = lambda path: touched.append(path) or "<p>hết</p>"
    assert d.fetch_latest(limit=10) == []
    assert touched == [f"/category/{i}.html" for i in (1, 3, 4, 7, 8, 9, 10)]

    # Pool nhỏ vẫn phải chia đều category, không để mục đầu nuốt hết quota.
    d = DingdianAdapter(base_url="https://x.com",
                        config={"discover_paths": ["/category/1.html", "/category/3.html"]},
                        source_row={"name": "ddxs"})
    d._get = lambda path: {
        "/category/1.html": '<a href="/n/a1/">玄幻一</a><a href="/n/a2/">玄幻二</a>',
        "/category/3.html": '<a href="/n/b1/">仙侠一</a><a href="/n/b2/">仙侠二</a>',
    }.get(path, "")
    assert [x.source_novel_id for x in d.fetch_latest(limit=2)] == ["a1", "b1"]
    d._get = lambda path: {
        "/category/1_2.html": '<a href="/n/a3/">玄幻深层</a>',
        "/category/3_2.html": '<a href="/n/b3/">仙侠深层</a>',
    }.get(path, "")
    assert [x.source_novel_id for x in d.fetch_latest(limit=10, page=2)] == ["a3", "b3"]


if __name__ == "__main__":
    main()
    print("OK — dingdian adapter test pass")
