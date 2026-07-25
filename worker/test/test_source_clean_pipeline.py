"""Self-check: crawler làm sạch nguồn trước khi lưu content_zh."""
from novelworker.crawler import sync


class _Query:
    def select(self, *_args, **_kwargs):
        return self

    def eq(self, *_args, **_kwargs):
        return self

    def is_(self, *_args, **_kwargs):
        return self

    def order(self, *_args, **_kwargs):
        return self

    def limit(self, *_args, **_kwargs):
        return self

    def execute(self):
        return type("Result", (), {"data": [{
            "id": 9, "source_chapter_id": "32/1", "chapter_index": 1,
        }]})()


class _Adapter:
    def fetch_chapter(self, _chapter_id):
        return "“回房间吧“，她说道！/\n( )\n埃尔顿*希里。"


def main() -> None:
    saved = []
    originals = sync.db.sb, sync.db.heartbeat, sync.db.save_chapter_raw, sync.time.sleep
    try:
        sync.db.sb = lambda: type("SB", (), {"table": lambda self, _name: _Query()})()
        sync.db.heartbeat = lambda *_args, **_kwargs: None
        sync.db.save_chapter_raw = lambda chapter_id, content: saved.append((chapter_id, content))
        sync.time.sleep = lambda _seconds: None
        sync.ensure_chapters_fetched(_Adapter(), 32)
    finally:
        sync.db.sb, sync.db.heartbeat, sync.db.save_chapter_raw, sync.time.sleep = originals

    assert saved == [(9, "“回房间吧”，她说道！\n埃尔顿希里。")], saved
    print("source clean pipeline OK")


if __name__ == "__main__":
    main()
