"""Self-check khuôn shuba (69shuba): 3 nhánh URL, TOC data-num giảm dần, txtnav lồng div."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.registry import TEMPLATE_REGISTRY
from novelworker.crawler.shuba import ShubaAdapter


def main() -> None:
    assert TEMPLATE_REGISTRY["shuba"] is ShubaAdapter
    a = ShubaAdapter(base_url="https://www.69shuba.com",
                     config={"encoding": "gbk"}, source_row={"name": "69shuba"})
    # 3 URL nằm ở 3 nhánh khác nhau
    assert a._novel_url("90442") == "/book/90442.htm"
    assert a._list_url("90442") == "/book/90442/"
    assert a._chapter_url("90442", "41051913") == "/txt/90442/41051913"

    # meta: lấy trọn từ og:novel:*, 完结 → completed, <br> trong mô tả thành xuống dòng
    novel_html = (
        '<meta property="og:title" content="霍格沃茨的学习面板"/>'
        '<meta property="og:description" content="睁开双眼&lt;br /&gt;老家的特产随之而来。"/>'
        '<meta property="og:image" content="https://cdn.cdnshu.com/files/article/image/90/90442/90442s.jpg"/>'
        '<meta property="og:novel:category" content="玄幻魔法"/>'
        '<meta property="og:novel:author" content="林曦遇鹿"/>'
        '<meta property="og:novel:status" content="完结"/>'
        '<meta property="og:novel:book_name" content="霍格沃茨的学习面板"/>'
    )
    a._get = lambda p: novel_html
    m = a.fetch_novel_meta("90442")
    assert m.title_zh == "霍格沃茨的学习面板" and m.author_zh == "林曦遇鹿", (m.title_zh, m.author_zh)
    assert m.status == "completed" and m.genres_zh == ["玄幻魔法"], (m.status, m.genres_zh)
    assert m.cover_url and "90442s.jpg" in m.cover_url
    assert m.description_zh == "睁开双眼\n老家的特产随之而来。", repr(m.description_zh)
    assert m.source_url == "https://www.69shuba.com/book/90442.htm"

    # thiếu og:novel:status → mặc định ongoing; thiếu book_name → rơi về og:title
    a._get = lambda p: '<meta property="og:title" content="武动乾坤"/>'
    m2 = a.fetch_novel_meta("1")
    assert m2.title_zh == "武动乾坤" and m2.status == "ongoing"

    # mục lục: HTML xếp GIẢM DẦN, thứ tự thật nằm ở data-num → sắp lại 1→N
    list_html = (
        '<li data-num="3"><a href="https://www.69shuba.com/txt/90442/300">第三章 丙</a></li>'
        '<li data-num="1"><a href="https://www.69shuba.com/txt/90442/100">第一章 甲</a></li>'
        '<li data-num="2"><a href="https://www.69shuba.com/txt/90442/200">第二章 (cũ)</a></li>'
        '<li data-num="2"><a href="https://www.69shuba.com/txt/90442/200">第二章 乙</a></li>'
    )
    a._get = lambda p: list_html
    refs = a.fetch_chapter_list("90442")
    assert [(r.index, r.source_chapter_id) for r in refs] == [
        (1, "90442/100"), (2, "90442/200"), (3, "90442/300")], refs
    assert refs[1].title_zh == "第二章 乙"  # dedupe theo cid, bản lần cuối thắng

    # mục lục rỗng → raise (báo đổi cấu trúc)
    a._get = lambda p: "<p>trống</p>"
    try:
        a.fetch_chapter_list("90442")
        assert False, "phải raise khi mục lục rỗng"
    except ValueError:
        pass

    # chương: txtnav lồng div con + quảng cáo chèn GIỮA thân, cắt ở bottom-ad
    a._get = lambda p: (
        '<div class="txtnav">'
        '<h1 class="hide720">第一章 甲</h1>'
        '<div class="txtinfo hide720"><span>2026-04-26</span> <span>作者： 林曦遇鹿</span></div>'
        '<div id="txtright"><script>loadAdv(2, 0);</script></div>'
        "&emsp;&emsp;第一章 甲<br />\r\n"
        "&emsp;&emsp;剑气纵横三万里。\n<br /><br />\r\n"
        '&emsp;&emsp;<div class="contentadv"><script>loadAdv(7,3);</script></div>\r\n'
        "&emsp;&emsp;一剑光寒十九州。\n<br /><br />\r\n"
        "&emsp;&emsp;(本章完)\n<br /><br />\n"
        '<div class="bottom-ad"><script>loadAdv(3, 0);</script></div></div>'
        '<div class="page1"><a href="/txt/90442/99">上一章</a></div>'
    )
    txt = a.fetch_chapter("90442/100")
    assert txt == "剑气纵横三万里。\n一剑光寒十九州。", repr(txt)

    # thiếu txtnav → raise
    a._get = lambda p: "<div>không có gì</div>"
    try:
        a.fetch_chapter("90442/100")
        assert False, "phải raise khi thiếu txtnav"
    except ValueError:
        pass

    # fetch_latest: xen kẽ các mục, bỏ nút "点击阅读", dedupe book_id, page>1 rỗng
    pages = {
        "/novels/class/1.htm": (
            '<a href="/book/11.htm">长生武尊</a><a href="/book/11.htm">点击阅读</a>'
            '<a href="/book/12.htm">大乾武圣</a>'),
        "/novels/class/2.htm": '<a href="/book/21.htm">仙逆</a><a href="/book/11.htm">长生武尊</a>',
    }
    a.config = {"discover_paths": list(pages)}
    a._get = lambda p: pages[p]
    res = a.fetch_latest(limit=10)
    assert [x.source_novel_id for x in res] == ["11", "21", "12"], [x.source_novel_id for x in res]
    assert res[0].title_zh == "长生武尊"
    assert res[0].source_url == "https://www.69shuba.com/book/11.htm"
    assert len(a.fetch_latest(limit=2)) == 2  # limit cắt đúng
    assert a.fetch_latest(page=2) == []  # trang mục không phân trang


if __name__ == "__main__":
    main()
    print("OK — shuba adapter test pass")
