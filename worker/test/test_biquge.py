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

    # Shuhaige hoàn thành: "结局" ở đầu xếp giảm dần, "正文" phía sau xếp tăng dần.
    # Phải ghép正文 trước rồi đảo结局, không được biến chương cuối thành chương 1.
    a._get = lambda p: (
        '<div id="list"><dl><dt>《测试小说》的结局</dt>'
        '<dd><a href="/59979/4.html">第4章</a></dd>'
        '<dd><a href="/59979/3.html">第3章</a></dd>'
        '<dt><b>《测试小说》正文</b></dt>'
        '<dd><a href="/59979/1.html">第1章</a></dd>'
        '<dd><a href="/59979/2.html">第2章</a></dd>'
        '</dl></div>'
    )
    refs = a.fetch_chapter_list("59979")
    assert [r.source_chapter_id for r in refs] == [
        "59979/1", "59979/2", "59979/3", "59979/4",
    ]

    # chương: br→\n, lọc dòng footer (笔趣阁/请记住本站/手机版), giữ câu văn thật
    p1, p2 = "第一段" + "字" * 30, "第二段" + "文" * 30
    a._get = lambda p: (
        f'<div id="content">{p1}。<br/>{p2}。<br>'
        '请记住本站笔趣阁 www.shuhaige.net<br>手机版</div>'
    )
    txt = a.fetch_chapter("59979/1")
    assert txt == f"{p1}。\n{p2}。", repr(txt)

    # chương ngắn không còn raise — trả nguyên văn, translator sẽ ghi chú "nguồn thiếu"
    a._get = lambda p: '<div id="content">短。</div>'
    assert a.fetch_chapter("59979/1") == "短。"

    # content_id override
    c = _adapter({"content_id": "chaptercontent"})
    c._get = lambda p: '<div id="chaptercontent">' + "内容" * 30 + "</div>"
    assert len(c.fetch_chapter("1/2")) >= 50

    # Pool hoàn thành Shuhaige chia đều category thay vì để mục đầu chiếm quota.
    done = _adapter({"completed_paths": ["/quanben/XuanHuan/", "/quanben/XianXia/"]})
    done._get = lambda path: {
        "/quanben/XuanHuan/": '<a href="/11/">玄幻一</a><a href="/12/">玄幻二</a>',
        "/quanben/XianXia/": '<a href="/61/">仙侠一</a><a href="/62/">仙侠二</a>',
    }.get(path, "")
    completed = done.fetch_completed(limit=2)
    assert [(x.source_novel_id, x.status) for x in completed] == [
        ("11", "completed"), ("61", "completed")]

    # Tổng đề cử dùng khuôn span.s2; TOP tổng hợp dùng link số trực tiếp và phải dedupe.
    pools = _adapter()
    pools._get = lambda path: {
        "/allvote/": '<span class="s2"><a href="/21/">Đề cử một</a></span>',
        "/allvote/2.html": '<span class="s2"><a href="/22/">Đề cử sâu</a></span>',
        "/top.html": ('<li><a href="/31/">Top một</a></li>'
                      '<li><a href="/31/">Top một trùng</a></li>'
                      '<li><a href="/32/">Top hai</a></li>'),
    }.get(path, "")
    assert [x.source_novel_id for x in pools.fetch_recommended(10)] == ["21", "22"]
    assert [x.source_novel_id for x in pools.fetch_recommended(10, page=2)] == ["22"]
    assert [x.source_novel_id for x in pools.fetch_top(10)] == ["31", "32"]
    assert pools.fetch_top(10, page=2) == []

    # chương bị site CHIA TRANG (123.html, 123_2.html…): tải nối hết các trang,
    # lọc dòng nhắc "点击下一页" — bug chương cụt đuôi "mất liền mạch" 2026-07
    d = _adapter()
    pg1 = ('<div id="content">trang một' + "字" * 30 +
           '<br>这章没有结束，请点击下一页继续阅读！</div><a href="/59979/123_2.html">下一页</a>')
    pg2 = '<div id="content">trang hai' + "文" * 30 + '</div>'
    fetched = []
    def fake_get(p):
        fetched.append(p)
        return pg2 if "_2" in p else pg1
    d._get = fake_get
    txt = d.fetch_chapter("59979/123")
    assert fetched == ["/59979/123.html", "/59979/123_2.html"], fetched
    assert "trang một" in txt and "trang hai" in txt
    assert "下一页" not in txt  # dòng nhắc phân trang phải bị lọc

    # --- Nguồn mới 2026-08: mục lục PHÂN TRANG riêng (qiushubang /index/{id}/{page}/).
    # Mỗi trang lặp khối "mới nhất" trước khối danh sách đầy đủ → toc_split cắt lấy
    # phần SAU lần xuất hiện CUỐI; trang không thêm gì → dừng.
    q = _adapter({
        "novel_path": "/index/{book_id}/",
        "chapter_path": "/read/{book_id}/{chapter_id}.html",
        "toc_page_path": "/index/{book_id}/{page}/",
        "toc_split": '<div class="section-box">',
        "toc_max_pages": 10,
    })
    def page_html(newest, full):
        return ('<div class="section-box"><ul><li><a href="/read/77/'
                + newest + '.html">Mới nhất</a></li></ul></div>'
                '<div class="section-box"><ul>'
                + "".join(f'<li><a href="/read/77/{c}.html">Ch.{c}</a></li>' for c in full)
                + "</ul></div>")
    toc_pages = {
        "/index/77/": page_html("900", ["1", "2"]),
        "/index/77/2/": page_html("900", ["3", "4"]),
        "/index/77/3/": page_html("900", ["4"]),  # hết chương mới → dừng
    }
    calls = []
    def toc_get(p):
        calls.append(p)
        return toc_pages[p]
    q._get = toc_get
    refs = q.fetch_chapter_list("77")
    assert [r.source_chapter_id for r in refs] == [
        "77/1", "77/2", "77/3", "77/4"], refs
    assert len(calls) == 3, calls  # trang 4 không được gọi (dừng khi hết fresh)

    # --- junk_re: watermark xáo trộn nhồi GIỮA câu (qiushubang) phải biến mất,
    # còn văn thường KHÔNG bị đụng tới. Bộ regex khớp migration 104.
    _SEP = "[^\\s一-龥，。！？…、；：“”‘’（）《》—]"
    w = _adapter({"junk_re": [
        f"[一-龥](?:{_SEP}{{1,4}}[一-龥]){{3,}}",
        "[^\\s一-龥，。！？…、；：“”‘’（）《》—0-9a-zA-Z]{2,}",
        f"(?:[^\\w\\s一-龥，。！？…、；：“”‘’（）《》—]\\w{{1,3}}){{4,}}"
        f"[^\\w\\s一-龥，。！？…、；：“”‘’（）《》—]?",
        f"{_SEP}{{1,4}}首{_SEP}{{1,4}}发{_SEP}{{0,4}}",
    ]})
    w._get = lambda p: (
        '<div id="content">她爬了几百阶。,天`禧^晓′税￠罔·\\追?罪/辛/蟑·结.<br>'
        '她睁开眼。*x-i,n_x¨s¨c+m,s^.￠c\\o<br>'
        '房间不大。~搜¨搜.小^说*网+ ~首,发/<br>'
        '她干脆坐下休息。</div>')
    out = w.fetch_chapter("77/1")
    assert out == ("她爬了几百阶。\n她睁开眼。\n房间不大。\n她干脆坐下休息。"), repr(out)

    # --- Discovery guard: nguồn khác shuhaige KHÔNG khai latest_path/ranking_path
    # → pool tắt ([]), không 404 route mặc định của shuhaige mỗi chu kỳ.
    g = _adapter()
    g.name = "khac"
    def boom(_p):  # nếu vẫn fetch thì test fail ngay
        raise AssertionError("không được gọi _get")
    g._get = boom
    assert g.fetch_latest(10) == [] and g.fetch_ranking(10) == []
    # khai đường dẫn riêng thì lại fetch bình thường:
    h = _adapter({"latest_path": "/moi/", "latest_pages": 1,
                  "ranking_path": "/xep-hang/", "ranking_pages": 1})
    h.name = "khac"
    seen = []
    h._get = lambda p: (seen.append(p) or "") or {
        "/moi/": '<span class="s2"><a href="/41/">Sách mới</a></span>',
        "/xep-hang/": '<span class="s2"><a href="/42/">Hot</a></span>',
    }.get(p, "")
    assert [x.source_novel_id for x in h.fetch_latest(10)] == ["41"]
    assert h.fetch_ranking(10) == [("42", 0)]
    assert seen == ["/moi/", "/xep-hang/"], seen


if __name__ == "__main__":
    main()
    print("OK — biquge adapter test pass")
