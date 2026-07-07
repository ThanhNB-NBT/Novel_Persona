"""Self-check khuôn xinbiquge (xbiquge.com.cn/uuxs): mục lục phân trang index_{p},
content article.font_max, junk 第(1/N)页, ranking /top/ + /full/."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.biquge import XinBiqugeAdapter
from novelworker.crawler.registry import TEMPLATE_REGISTRY

CFG = {"novel_path": "/book/{book_id}/", "chapter_path": "/book/{book_id}/{chapter_id}.html"}


def adapter() -> XinBiqugeAdapter:
    return XinBiqugeAdapter(base_url="https://www.xbiquge.com.cn", config=dict(CFG),
                            source_row={"name": "xsbique"})


def main() -> None:
    assert TEMPLATE_REGISTRY["xinbiquge"] is XinBiqugeAdapter
    a = adapter()
    # book_id 2 tầng "nhóm/id" đi xuyên format URL + rpartition trong fetch_chapter
    assert a._novel_url("107/107771") == "/book/107/107771/"
    assert a._chapter_url("107/107771", "491040") == "/book/107/107771/491040.html"

    # Mục lục phân trang: MỌI trang lặp block 最新章节 (book_list) trước list đầy đủ
    # (book_list2) → block phải bị bỏ, chỉ lấy sau book_list2. Trang quá cuối site
    # trả về = trang 1 → không chương mới → dừng.
    latest_block = '<div class="book_list"><a href="/book/107/107771/30.html">第三章最新</a></div>'
    page1 = (
        latest_block + '<div class="book_list book_list2">'
        '<a href="/book/107/107771/10.html">第一章</a>'
        '<a href="/book/107/107771/20.html">第二章</a></div>'
    )
    pages = {
        "/book/107/107771/": page1,
        "/book/107/107771/index_2.html": (
            latest_block + '<div class="book_list book_list2">'
            '<a href="/book/107/107771/30.html">第三章</a></div>'
        ),
        "/book/107/107771/index_3.html": page1,  # quá cuối → site trả trang 1
    }
    calls: list[str] = []

    def fake_get(p):
        calls.append(p)
        return pages[p]  # gọi tới trang 4 là KeyError → test fail

    a._get = fake_get
    refs = a.fetch_chapter_list("107/107771")
    assert [(r.index, r.source_chapter_id) for r in refs] == [
        (1, "107/107771/10"), (2, "107/107771/20"), (3, "107/107771/30")], refs
    assert refs[2].title_zh == "第三章"  # tựa từ list đầy đủ, không phải block mới-nhất
    assert calls[-1].endswith("index_3.html")  # dừng khi trang không thêm gì mới

    # og:title dính đuôi SEO "最新章节" → phải cắt
    a._get = lambda p: '<meta property="og:title" content="恨姐症最新章节">'
    assert a.fetch_novel_meta("107/107771").title_zh == "恨姐症"

    # chương: article.font_max, junk 第(1/3)页 đầu/cuối, gộp trang {cid}_2.html
    body1 = "夜色很静，" + "字" * 50
    body2 = "第二页正文。" + "书" * 50
    chap_pages = {
        "/book/107/107771/491040.html": (
            '<article class="content font_max"><p>&nbsp;&nbsp;第(1/2)页</p>'
            f"<p>{body1}</p><p>第(1/2)页</p></article>"
            '<a href="/book/107/107771/491040_2.html">下一页</a>'
        ),
        "/book/107/107771/491040_2.html": (
            f'<article class="font_max"><p>第(2/2)页</p><p>{body2}</p></article>'
        ),
    }
    a._get = lambda p: chap_pages[p]
    txt = a.fetch_chapter("107/107771/491040")
    assert txt == f"{body1}\n{body2}", repr(txt)

    # ranking: /top/ trước /full/, dedupe, giữ thứ tự
    rank_pages = {
        "/top/": '<a href="/book/1/11/">A</a><a href="/book/2/22/">B</a>',
        "/full/": '<a href="/book/2/22/">B dup</a><a href="/book/3/33/">C</a>',
    }
    a._get = lambda p: rank_pages[p]
    assert a.fetch_ranking() == [("1/11", 0), ("2/22", 1), ("3/33", 2)]
    assert a.fetch_ranking(limit=2) == [("1/11", 0), ("2/22", 1)]


if __name__ == "__main__":
    main()
    print("OK — xinbiquge adapter test pass")
