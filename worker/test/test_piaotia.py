"""Self-check khuôn piaotia (ptwxz): ID cặp {a}/{bid}, content thô sau </h1>, GBK qua config."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.piaotia import PiaotiaAdapter
from novelworker.crawler.registry import TEMPLATE_REGISTRY


def main() -> None:
    assert TEMPLATE_REGISTRY["piaotia"] is PiaotiaAdapter
    a = PiaotiaAdapter(base_url="https://www.piaotia.com",
                       config={"encoding": "gbk"}, source_row={"name": "ptwxz"})
    # ID truyện là CẶP {a}/{bid} → 3 URL ghép đúng thư mục con
    assert a._novel_url("1/2") == "/bookinfo/1/2.html"
    assert a._list_url("1/2") == "/html/1/2/"
    assert a._chapter_url("1/2", "9") == "/html/1/2/9.html"

    # meta: tên từ <h1>, tác giả 作者：, bìa /files/article/image/
    novel_html = (
        "<h1>逆天邪神</h1>"
        "<div>作者：火星引力</div>"
        '<img src="https://www.piaotia.com/files/article/image/1/2/2s.jpg">'
    )
    a._get = lambda p: novel_html
    m = a.fetch_novel_meta("1/2")
    assert m.title_zh == "逆天邪神" and m.author_zh == "火星引力", (m.title_zh, m.author_zh)
    assert m.cover_url and "files/article/image" in m.cover_url
    assert m.source_url == "https://www.piaotia.com/bookinfo/1/2.html"

    # tên fallback từ <title> khi thiếu <h1> (cắt token đầu theo 最新章节/_/-)
    a._get = lambda p: "<title>武动乾坤最新章节_天蚕土豆</title>"
    assert a.fetch_novel_meta("1/2").title_zh == "武动乾坤"

    # mục lục: neo số.html tương đối; dedupe GIỮ lần cuối; thứ tự 1→N
    list_html = (
        '<a href="9297.html">第二章 (cũ)</a>'
        '<a href="9296.html">第一章 觉醒</a>'
        '<a href="9297.html">第二章 战起</a>'
    )
    a._get = lambda p: list_html
    refs = a.fetch_chapter_list("1/2")
    assert [(r.index, r.source_chapter_id) for r in refs] == [(1, "1/2/9296"), (2, "1/2/9297")]
    assert refs[1].title_zh == "第二章 战起"  # bản lần cuối thắng

    # mục lục rỗng → raise (báo đổi cấu trúc)
    a._get = lambda p: "<p>trống</p>"
    try:
        a.fetch_chapter_list("1/2")
        assert False, "phải raise khi mục lục rỗng"
    except ValueError:
        pass

    # chương: content thô ngay sau </h1>, br→\n, lọc dòng quảng cáo (host/piaotia/飘天文学)
    body = "剑气纵横三万里。" + "字" * 60
    a._get = lambda p: (
        f"</h1>{body}<br/>飘天文学 www.piaotia.com<br>手机阅读<div>footer</div>"
    )
    txt = a.fetch_chapter("1/2/9296")
    assert txt == body, repr(txt)

    # chương lấy từ div#content khi trang có sẵn
    a._get = lambda p: '<div id="content">' + "内容" * 40 + "</div>"
    assert len(a.fetch_chapter("1/2/9296")) >= 60

    # fetch_latest: quét trang chủ, dedupe book_id cặp, cắt theo limit, page>1 rỗng
    home = (
        '<a href="/bookinfo/1/2.html">逆天邪神</a>'
        '<a href="/bookinfo/3/4.html">武动乾坤</a>'
        '<a href="/bookinfo/1/2.html">逆天邪神 dup</a>'
    )
    a._get = lambda p: home
    res = a.fetch_latest(limit=10)
    assert [x.source_novel_id for x in res] == ["1/2", "3/4"], [x.source_novel_id for x in res]
    assert res[0].source_url == "https://www.piaotia.com/bookinfo/1/2.html"
    assert len(a.fetch_latest(limit=1)) == 1  # limit cắt đúng
    assert a.fetch_latest(page=2) == []  # trang > 1 không quét lặp


if __name__ == "__main__":
    main()
    print("OK — piaotia adapter test pass")
