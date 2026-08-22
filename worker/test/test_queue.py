"""Test hàng đợi cốt lõi: requeue_stale_jobs (reaper), finish_job, defer_job.

Đây là lớp resilience quan trọng nhất của worker nhưng trước đây chỉ được kiểm
chứng bằng cách chạy thật trên Supabase. Viết test đã lộ 1 bug thật: reaper đọc
.data sau update returning="minimal" — PostgREST trả body rỗng nên dead/stale
luôn [], phần đồng bộ chương chưa bao giờ chạy.
"""
import os
import sys
from types import SimpleNamespace

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker import db


class _Q:
    """Chuỗi PostgREST giả: ghi lại lệnh + payload để assert.

    select trả data theo hàng đợi per-table (select_data[table] = [trang1, trang2…]);
    update/in_ gộp thành (table, payload, ids) trong sb.updates — khớp cách code
    thật dùng .update(...).in_("id", [...]) để gom nhóm.
    """

    def __init__(self, sb, table):
        self._sb, self._table = sb, table
        self._payload = None
        self._single = False
        self._is_select = False

    def _rec(self, method, *args):
        self._sb.calls.append((method, self._table, args))
        return self

    def select(self, cols, *a, **k):
        self._is_select = True
        return self._rec("select", cols)

    def update(self, payload, *a, **k):
        self._payload = payload
        return self

    def delete(self, *a, **k):
        return self._rec("delete")

    def eq(self, c, v):
        return self._rec("eq", c, v)

    def lt(self, c, v):
        return self._rec("lt", c, v)

    def gte(self, c, v):
        return self._rec("gte", c, v)

    def in_(self, c, vs):
        if self._payload is not None:
            self._sb.updates.append((self._table, self._payload, tuple(vs)))
            self._payload = None
        return self._rec("in_", c, tuple(vs))

    def order(self, *a, **k):
        return self

    def range(self, *a, **k):
        return self

    def single(self):
        self._single = True
        return self

    def execute(self):
        if self._payload is not None:
            self._sb.updates.append((self._table, self._payload, None))
            self._payload = None
            return SimpleNamespace(data=[])  # returning=minimal: body rỗng
        if not self._is_select:
            return SimpleNamespace(data=[])  # delete/rpc không trả data cần đọc
        pages = self._sb.select_data.get(self._table) or []
        data = pages.pop(0) if pages else []
        if self._single:
            data = data[0] if isinstance(data, list) and data else None
        return SimpleNamespace(data=data)


class _FakeSB:
    def __init__(self, select_data=None):
        self.calls = []                # (method, table, args) mọi thao tác
        self.updates = []              # (table, payload, ids|None)
        self.select_data = select_data or {}

    def table(self, name):
        return _Q(self, name)

    def rpc(self, name, params=None):
        self.calls.append(("rpc", name, params))
        return _Q(self, f"rpc:{name}")

    def updates_for(self, table):
        return [u for u in self.updates if u[0] == table]


# ---------- requeue_stale_jobs ----------

def test_reaper_splits_dead_and_stale(monkeypatch):
    fake = _FakeSB(select_data={"translation_jobs": [[
        {"id": 1, "chapter_id": 101, "attempts": 3, "max_attempts": 3},   # hết lượt → failed
        {"id": 2, "chapter_id": 102, "attempts": 0, "max_attempts": 3},   # còn lượt → pending
        {"id": 3, "chapter_id": None, "attempts": 9, "max_attempts": 10}, # metadata, còn lượt
    ]]})
    monkeypatch.setattr(db, "sb", lambda: fake)
    n = db.requeue_stale_jobs(max_minutes=30)
    assert n == 3

    jobs = fake.updates_for("translation_jobs")
    assert sorted(u[1]["status"] for u in jobs) == ["failed", "pending"]
    # failed gom id 1; pending gom id 2 và 3 (metadata không có chương nên chỉ vào nhóm pending)
    by_status = {u[1]["status"]: u[2] for u in jobs}
    assert by_status["failed"] == (1,)
    assert set(by_status["pending"]) == {2, 3}

    ch = fake.updates_for("chapters")
    by_status = {u[1]["translation_status"]: set(u[2] or ()) for u in ch}
    assert by_status.get("failed") == {101}
    assert by_status.get("queued") == {102}


def test_reaper_respects_max_attempts_per_job(monkeypatch):
    # attempts=3 nhưng max_attempts=5 → CÒN lượt, phải requeue chứ không failed
    fake = _FakeSB(select_data={"translation_jobs": [[
        {"id": 7, "chapter_id": 70, "attempts": 3, "max_attempts": 5},
    ]]})
    monkeypatch.setattr(db, "sb", lambda: fake)
    assert db.requeue_stale_jobs() == 1
    jobs = fake.updates_for("translation_jobs")
    assert len(jobs) == 1 and jobs[0][1]["status"] == "pending"


def test_reaper_empty_queue_is_noop(monkeypatch):
    fake = _FakeSB()
    monkeypatch.setattr(db, "sb", lambda: fake)
    assert db.requeue_stale_jobs() == 0
    assert not fake.updates


# ---------- finish_job ----------

def _job_row(**over):
    row = {"attempts": 1, "max_attempts": 3, "chapter_id": 55,
           "type": "chapter", "novel_id": 9}
    row.update(over)
    return row


def test_finish_ok_marks_done(monkeypatch):
    fake = _FakeSB()
    monkeypatch.setattr(db, "sb", lambda: fake)
    db.finish_job(11, ok=True)
    jobs = fake.updates_for("translation_jobs")
    assert len(jobs) == 1 and jobs[0][1]["status"] == "done"
    assert jobs[0][1]["error"] is None and jobs[0][1]["locked_by"] is None
    assert not fake.updates_for("chapters")


def test_finish_fail_with_retry_left_queues_chapter(monkeypatch):
    fake = _FakeSB(select_data={"translation_jobs": [[_job_row(attempts=1)]]})
    monkeypatch.setattr(db, "sb", lambda: fake)
    db.finish_job(11, ok=False, error="boom")
    assert fake.updates_for("translation_jobs")[-1][1]["status"] == "pending"
    assert fake.updates_for("chapters")[0][1] == {"translation_status": "queued"}


def test_finish_fail_exhausted_fails_chapter(monkeypatch):
    fake = _FakeSB(select_data={"translation_jobs": [[_job_row(attempts=3)]]})
    monkeypatch.setattr(db, "sb", lambda: fake)
    db.finish_job(11, ok=False, error="boom")
    assert fake.updates_for("translation_jobs")[-1][1]["status"] == "failed"
    assert fake.updates_for("chapters")[0][1] == {"translation_status": "failed"}


def test_finish_metadata_exhausted_releases_waiting_chapters(monkeypatch):
    # job metadata HẾT LƯỢT → các job CHƯƠNG đang chờ metadata phải được thả:
    # chương mẫu về 'none', xoá job chương pending (nếu không sẽ kẹt vĩnh viễn).
    fake = _FakeSB(select_data={"translation_jobs": [
        [_job_row(chapter_id=None, type="metadata",
                  attempts=3, max_attempts=3)],   # finish_job đọc job
        [{"id": 5, "chapter_id": 500}],           # job chương đang chờ meta
    ]})
    monkeypatch.setattr(db, "sb", lambda: fake)
    db.finish_job(11, ok=False, error="meta chết")

    ch = fake.updates_for("chapters")
    assert {"translation_status": "none"} in [u[1] for u in ch]
    deletes = [c for c in fake.calls if c[0] == "delete" and c[1] == "translation_jobs"]
    assert deletes


def test_finish_chapterless_fail_does_not_touch_chapters(monkeypatch):
    fake = _FakeSB(select_data={"translation_jobs": [
        [_job_row(chapter_id=None, type="chapter")],
    ]})
    monkeypatch.setattr(db, "sb", lambda: fake)
    db.finish_job(11, ok=False, error="boom")
    assert not fake.updates_for("chapters")


# ---------- defer_job ----------

def test_defer_job_calls_rpc_with_trimmed_error(monkeypatch):
    fake = _FakeSB()
    monkeypatch.setattr(db, "sb", lambda: fake)
    db.defer_job(33, "w-1", error="x" * 5000)
    rpcs = [c for c in fake.calls if c[0] == "rpc"]
    assert len(rpcs) == 1 and rpcs[0][1] == "defer_translation_job"
    p = rpcs[0][2]
    assert p["p_job_id"] == 33 and p["p_worker_id"] == "w-1"
    assert len(p["p_error"]) == 2000 and p["p_restore_attempt"] is True
