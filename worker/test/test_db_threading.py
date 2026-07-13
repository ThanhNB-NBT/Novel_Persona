import os
import threading

os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")


def test_supabase_client_is_thread_local(monkeypatch):
    from novelworker import db

    created = []

    def fake_create_client(*_args):
        client = object()
        created.append(client)
        return client

    monkeypatch.setattr(db, "create_client", fake_create_client)
    monkeypatch.setattr(db, "_thread_clients", threading.local())

    main_first = db.sb()
    assert db.sb() is main_first

    from_other_thread = []
    thread = threading.Thread(target=lambda: from_other_thread.append(db.sb()))
    thread.start()
    thread.join()

    assert len(created) == 2
    assert from_other_thread[0] is not main_first


def test_transient_db_error_classifier():
    from novelworker import db

    RemoteProtocolError = type(
        "RemoteProtocolError", (RuntimeError,), {"__module__": "httpx"}
    )
    assert db.is_transient_error(RemoteProtocolError("ConnectionTerminated"))
    assert db.is_transient_error(RuntimeError("Cloudflare gateway timeout"))
    assert not db.is_transient_error(RuntimeError("không sửa hết ký tự Hán sót"))
