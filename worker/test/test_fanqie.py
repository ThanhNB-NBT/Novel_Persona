"""Self-check khuôn fanqie: parse metadata/mục lục/chương từ state JSON canned."""
import json
import os
import sys

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


if __name__ == "__main__":
    main()
    print("OK — fanqie adapter test pass")
