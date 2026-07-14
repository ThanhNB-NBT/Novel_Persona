"""P2a: mỗi nguồn 1 luồng. Test nhánh cadence của _source_tick — discovery chỉ chạy
khi tới chu kỳ (due), còn tải chương người đọc chạy mỗi tick."""
import os
import sys
from types import SimpleNamespace

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker import main as m


class _FakeQuery:
    """Chuỗi PostgREST giả: gọi hay lấy attr (.eq, .not_, .is_…) đều trả chính nó;
    execute() trả rỗng. Đủ để _source_tick chạy qua các query mà không đụng mạng."""
    def __call__(self, *a, **k):
        return self

    def __getattr__(self, name):
        if name == "execute":
            return lambda *a, **k: SimpleNamespace(data=[], count=0)
        return self


def _stub(monkeypatch):
    calls = {"ensure": 0, "discover": 0}
    monkeypatch.setattr(m.db, "sb", lambda: _FakeQuery())
    monkeypatch.setattr(m.sync, "ensure_chapters_fetched",
                        lambda *a, **k: calls.__setitem__("ensure", calls["ensure"] + 1))
    for fn in ("discover_ranking", "discover_pool", "process_discovery_candidates",
               "sync_followed_novels", "refresh_canonical_updates", "sync_chapter_list"):
        monkeypatch.setattr(m.sync, fn,
                            lambda *a, _n=fn, **k: calls.__setitem__("discover", calls["discover"] + 1)
                            if _n != "sync_chapter_list" else (0, 0))
    return calls


def _adapter():
    return SimpleNamespace(name="src", source_row={"id": 7})


def test_source_tick_not_due_skips_discovery(monkeypatch):
    calls = _stub(monkeypatch)
    pending = [{"source_id": 7, "id": 100}]
    m._source_tick(_adapter(), pending, due=False, max_new=5, refresh_n=10)
    assert calls["ensure"] == 1      # vẫn tải chương người đọc
    assert calls["discover"] == 0    # nhưng KHÔNG discovery khi chưa tới chu kỳ


def test_source_tick_due_runs_discovery(monkeypatch):
    calls = _stub(monkeypatch)
    m._source_tick(_adapter(), [], due=True, max_new=5, refresh_n=10)
    assert calls["discover"] > 0     # tới chu kỳ → có discovery/refresh


def test_source_tick_skips_other_source(monkeypatch):
    calls = _stub(monkeypatch)
    pending = [{"source_id": 999, "id": 100}]   # nguồn khác → không đụng
    m._source_tick(_adapter(), pending, due=False, max_new=5, refresh_n=10)
    assert calls["ensure"] == 0
