"""Mô tả truyện: bỏ rác nguồn trước khi đưa vào prompt metadata."""
from types import SimpleNamespace

from novelworker.crawler import sync
from novelworker.translator import worker
from novelworker.translator.worker import strip_desc_junk as strip


def test_bo_khoi_tieu_de_tac_gia_gioi_thieu():
    raw = "《《虚无至尊道》》作者:忘情至尊,简介:三世轮回的独孤风，剑祖。"
    assert strip(raw) == "三世轮回的独孤风，剑祖。"


def test_bo_loi_keu_goi_va_link():
    assert strip("本书又名《大佬》 剧情很好 求收藏求推荐 https://x.com/a") == "剧情很好"


def test_cat_duoi_danh_sach_truyen_goi_y():
    # 2.616/5.388 mô tả trong kho có đuôi "小说推荐：..." — dịch cả đống đó chỉ tổ rác.
    raw = "林浩拥有五行灵根，最终成为绝世仙帝。...《五行仙帝》小说推荐：烟雨楼、凡人修仙记、开局一张混沌符"
    assert strip(raw) == "林浩拥有五行灵根，最终成为绝世仙帝。"


def test_giu_nguyen_mo_ta_sach():
    raw = "女主网游。让我作间谍？凭啥？"
    assert strip(raw) == raw


def test_chi_xep_chuong_mau_sau_khi_metadata_dich_xong(monkeypatch):
    events = []
    novel = {
        "id": 7, "title_zh": "测试", "description_zh": "", "genres": [],
        "meta_translated": False, "title_vi": None, "author_vi": None,
        "description_vi": None,
    }

    class Query:
        def select(self, *args, **kwargs):
            return self

        def eq(self, *args, **kwargs):
            return self

        def single(self):
            return self

        def update(self, payload, **kwargs):
            events.append(("update", payload))
            return self

        def execute(self):
            return SimpleNamespace(data=novel)

    class Llm:
        def complete(self, *args, **kwargs):
            return SimpleNamespace(text=(
                '{"title_vi":"Truyện Thử","author_vi":"Tác Giả",'
                '"description_vi":"Mô tả.","genres_vi":[]}'))

    monkeypatch.setattr(worker.db, "sb", lambda: SimpleNamespace(table=lambda _: Query()))
    monkeypatch.setattr(worker.db, "get_glossary", lambda _: ([], []))
    monkeypatch.setattr(worker.db, "utc_now", lambda: "now")
    monkeypatch.setattr(
        sync, "queue_sample_chapters",
        lambda novel_id, count, priority: events.append(
            ("samples", novel_id, count, priority)),
    )

    worker.handle_metadata({"novel_id": 7}, Llm())

    assert events[0][0] == "samples"
    assert events[1][0] == "update"
    assert events[1][1]["meta_translated"] is True
