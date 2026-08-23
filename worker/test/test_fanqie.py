"""Self-check khuôn fanqie: parse metadata/mục lục/chương từ state JSON canned."""
import json
import os
import sys
from html import unescape

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.base import EmptyChapterList
from novelworker.crawler.fanqie import FanqieAdapter
from novelworker.crawler.registry import TEMPLATE_REGISTRY


def _adapter(config=None):
    return FanqieAdapter(base_url="https://fanqienovel.com",
                         config=config or {}, source_row={"name": "fanqie"})


BOOK_STATE = {
    "page": {
        "bookName": "十日终焉", "author": "杀虫队队员",
        "abstract": "24年番茄年度巅峰榜TOP1",
        "thumbUrl": "https://p3-novel-sign.example/novel-pic/abc~tplv-resize:225:300.image",
        "categoryV2": '[{"Name": "悬疑脑洞"}, {"Name": "环环相扣"}]',
        "wordNumber": 3201288, "chapterTotal": 3, "readCount": 12345,
        "creationStatus": 0, "lastPublishTime": "1761919823",
        "lastChapterItemId": "333",
        # itemIds xếp MỚI-NHẤT-TRƯỚC → phải bị đảo thành 1→N
        "itemIds": ["333", "222", "111"],
    },
}

# trang reader: content = HTML <p> xen PUA; bảng thật trong fanqie_charset.json
_PUA = {"我们": "\ue521\ue55a", "给": "\ue4d1", "了": "\ue436"}
READER_HTML = (
    "<html><script>window.__INITIAL_STATE__=" + json.dumps({
        "reader": {"content": "<p>\\u5211\\u554a</p>"
                              "<p>我们给老大姐办了简单的葬礼。</p>"
                              "<p>扫码下载番茄小说APP免费读</p>"},
    }, ensure_ascii=False) + ";</script></html>"
)


def main() -> None:
    assert TEMPLATE_REGISTRY["fanqie"] is FanqieAdapter
    a = _adapter()

    # metadata từ state
    a._fetch_state = lambda path: BOOK_STATE
    m = a.fetch_novel_meta("7143038691944959011")
    assert m.title_zh == "十日终焉" and m.author_zh == "杀虫队队员"
    assert m.genres_zh == ["悬疑脑洞", "环环相扣"]
    assert m.chapter_count == 3 and m.word_count == 3201288
    # creationStatus=0 = 完结; lastPublishTime unix → last_chapter_at
    assert m.status == "completed"
    assert m.last_chapter_at is not None and m.last_chapter_at.year == 2025
    # host CDN p3 hỏng → phải được ép về p9 để cache_cover tải được bìa
    assert m.cover_url.startswith("https://p9-novel-sign.example/"), m.cover_url

    # mục lục: đảo mới-nhất-trước → 1→N
    refs = a.fetch_chapter_list("7143038691944959011")
    assert [r.source_chapter_id for r in refs] == ["111", "222", "333"], refs
    assert refs[0].index == 1

    # chương: decode PUA bằng bảng thật + lọc dòng quảng cáo (kèm phần sau nó)
    def fake_get(_path):
        return READER_HTML

    a._get = fake_get
    txt = a.fetch_chapter("111")
    assert "我们给老大姐办了简单的葬礼。" in txt, repr(txt)
    assert "扫码下载" not in txt and "免费读" not in txt
    # PUA không còn sót trong kết quả
    assert not any(0xE000 <= ord(c) <= 0xF8FF for c in txt)

    # --- fetch_latest: feed mới-cập-nhật toàn nền tảng (API, phân trang)
    feed = json.dumps({"data": {"data": [
        {"bookId": "801", "bookName": "Sách mới 1", "author": "Tác giả A",
         "category": "玄幻", "updateTime": "1787491632",
         "title": "Chương 9"},
        {"bookId": "801", "bookName": "Sách mới 1", "updateTime": "1787491632",
         "title": "Chương 10"},                                # trùng book → dedupe
        {"bookId": "", "bookName": "Không id"},                # bỏ
    ]}}, ensure_ascii=False)
    a4 = _adapter()
    a4._get = lambda p: (feed if "recent/update" in p and "page_index=0" in p
                         else feed)  # mọi trang trả cùng feed cho mục đích test
    latest = a4.fetch_latest(30, page=1)
    assert [m.source_novel_id for m in latest] == ["801"], latest
    m1 = latest[0]
    assert m1.author_zh == "Tác giả A" and m1.genres_zh == ["玄幻"]
    assert m1.last_chapter_at is not None

    # font đổi URL → cảnh báo 1 lần (không crash)
    a2 = _adapter()
    a2._known_font_url = "https://old.example/aaa.woff2"
    warned = []
    import novelworker.crawler.fanqie as fq
    orig = fq.log.warning
    fq.log.warning = lambda *args, **kw: warned.append(args)
    try:
        html_font = ("<html><script>window.__INITIAL_STATE__={};</script>"
                     'url(https://new.example/bbb.woff2)</html>')
        a2._check_font(html_font)
        a2._check_font(html_font)  # lần 2 không warn nữa
    finally:
        fq.log.warning = orig
    assert len(warned) == 1

    # --- ranking: API JSON (tên sạch) trước, HTML server-render (PUA) bù sau
    api_json = json.dumps({"data": {"list": [
        {"bookId": "90003", "bookName": "API sách"},
        {"bookId": "90002", "bookName": "十日终焉"},
    ]}}, ensure_ascii=False)
    rank_html = (
        '<a href="/page/90002">十日终焉</a>'
        '<a href="/page/90001">\ue521\ue55a</a>'                  # 我们 (PUA phẳng như thật)
        '<a href="/page/90003"></a>'                              # rỗng → bỏ
        '<a href="/page/90004">HTML sách</a>')
    def rank_get(p):
        if p.startswith("/api/rank/list"):
            return api_json
        assert p in ("/rank/1", "/rank/0", "/rank/2", "/")
        return rank_get.html

    # thay thế escape thành ký tự PUA thật 1 lần lúc init
    rank_get.html = (rank_html.replace("\\ue521", "\ue521")
                              .replace("\\ue55a", "\ue55a"))
    a3 = _adapter()
    a3._get = rank_get
    ranked = a3.fetch_ranking(10)
    ids = [bid for bid, _rank in ranked]
    # API cho 90003/90002; HTML bù 90001 (PUA decode) + 90004; 90002 trùng giữ lần đầu
    assert ids == ["90003", "90002", "90001", "90004"], ranked
    # tên của 90001 đã decode từ PUA thành "我们"
    raw_title = unescape("\ue521\ue55a")
    assert raw_title.translate(a3._translate) == "我们"


if __name__ == "__main__":
    main()
    print("OK — fanqie adapter test pass")
