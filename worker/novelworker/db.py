"""Supabase client (service role) + các thao tác DB dùng chung."""
from __future__ import annotations

import logging
import re
import threading
import time as _time
from datetime import datetime, timedelta, timezone
from typing import Any

from supabase import Client, create_client

from .config import settings

log = logging.getLogger(__name__)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


_thread_clients = threading.local()


def sb() -> Client:
    """Mỗi worker thread giữ một HTTP client riêng.

    supabase-py/httpx không bảo đảm một HTTP/2 connection dùng chung an toàn giữa
    nhiều thread; chia client ngăn một connection reset làm chết dây chuyền các lane.
    """
    client = getattr(_thread_clients, "client", None)
    if client is None:
        client = create_client(settings.supabase_url, settings.supabase_service_role_key)
        _thread_clients.client = client
    return client


# ---------- novels / chapters ----------

def upsert_novel(row: dict[str, Any]) -> dict:
    res = (
        sb().table("novels")
        .upsert(row, on_conflict="source_id,source_novel_id")
        .execute()
    )
    return res.data[0]


def upsert_chapter_stubs(rows: list[dict]) -> None:
    """Upsert mục lục theo lô — truyện dài (shuhaige 4000+ chương) không thể
    1 request/chương. Chunk 500 để tránh payload quá lớn."""
    for i in range(0, len(rows), 500):
        sb().table("chapters").upsert(
            rows[i:i + 500], on_conflict="novel_id,chapter_index", returning="minimal"
        ).execute()


def save_chapter_raw(chapter_id: int, content_zh: str) -> None:
    sb().table("chapters").update({"content_zh": content_zh}, returning="minimal").eq("id", chapter_id).execute()


def finalize_chapter_job(
    job_id: int, worker_id: str, chapter_id: int,
    title_vi: str | None, content_vi: str, model: str,
    prompt_tokens: int, completion_tokens: int, glossary_version: int,
    summary_vi: str | None = None,
) -> None:
    """Lưu chương + đóng job trong một transaction phía PostgreSQL.

    RPC cố ý giữ `content_zh`: dịch lại không còn phải chờ crawler tải lại bản gốc.
    """
    sb().rpc("finalize_chapter_job", {
        "p_job_id": job_id,
        "p_worker_id": worker_id,
        "p_chapter_id": chapter_id,
        "p_title_vi": title_vi,
        "p_summary_vi": summary_vi,
        "p_content_vi": content_vi,
        "p_model": model,
        "p_prompt_tokens": prompt_tokens,
        "p_completion_tokens": completion_tokens,
        "p_glossary_version": glossary_version,
    }).execute()


# ---------- jobs ----------

def claim_next_job(worker_id: str, types: list[str] | None = None) -> dict | None:
    """`types` = None → mọi loại job; ["chapter"] → luồng chuyên dịch chương."""
    args: dict[str, Any] = {"worker_id": worker_id}
    if types:
        args["p_types"] = types
    res = sb().rpc("claim_next_job", args).execute()
    return res.data[0] if res.data else None


def refresh_job_lock(job_id: int, worker_id: str) -> None:
    """Gia hạn lease để reaper không lấy lại job LLM vẫn đang chạy."""
    sb().table("translation_jobs").update({"locked_at": utc_now()}, returning="minimal").eq(
        "id", job_id
    ).eq("status", "running").eq("locked_by", worker_id).execute()


def finish_job(job_id: int, ok: bool, error: str | None = None) -> None:
    if ok:
        sb().table("translation_jobs").update(
            {"status": "done", "done_at": utc_now(), "error": None,
             "locked_by": None, "locked_at": None},
            returning="minimal",
        ).eq("id", job_id).execute()
        return
    # thất bại: còn lượt thì trả về pending để retry, hết lượt thì failed
    job = sb().table("translation_jobs").select(
        "attempts,max_attempts,chapter_id,type,novel_id").eq("id", job_id).single().execute().data
    status = "pending" if job["attempts"] < job["max_attempts"] else "failed"
    sb().table("translation_jobs").update(
        {"status": status, "error": (error or "")[:2000],
         "locked_by": None, "locked_at": None},
        returning="minimal",
    ).eq("id", job_id).execute()
    if job.get("chapter_id"):
        sb().table("chapters").update(
            {"translation_status": "failed" if status == "failed" else "queued"},
            returning="minimal",
        ).eq("id", job["chapter_id"]).execute()
    elif status == "failed" and job.get("type") == "metadata":
        _release_chapters_waiting_metadata(job["novel_id"])


def _release_chapters_waiting_metadata(novel_id: int) -> None:
    """Metadata chết hẳn → thả chương mẫu đã xếp trước đó (handle_metadata xếp TRƯỚC khi
    set meta_translated). Không thả thì claim_next_job chặn mãi vì meta_translated=false:
    job pending vĩnh viễn, chapter kẹt 'queued' mà cleanup_orphan_translation_jobs cũng
    không dọn được. Dịch lại metadata sẽ xếp lại chương mẫu từ đầu."""
    jobs = (
        sb().table("translation_jobs").select("id,chapter_id")
        .eq("novel_id", novel_id).eq("type", "chapter").eq("status", "pending").execute()
    ).data or []
    if not jobs:
        return
    chapter_ids = [j["chapter_id"] for j in jobs if j.get("chapter_id")]
    if chapter_ids:
        sb().table("chapters").update(
            {"translation_status": "none"}, returning="minimal"
        ).in_("id", chapter_ids).eq("translation_status", "queued").execute()
    sb().table("translation_jobs").delete(returning="minimal").in_(
        "id", [j["id"] for j in jobs]).execute()
    log.warning("Metadata truyện %s chết hẳn — thả %d job chương đang chờ",
                novel_id, len(jobs))


def defer_job(job_id: int, worker_id: str, error: str | None = None,
              restore_attempt: bool = True) -> None:
    """Trả job tạm lỗi về queue mà không tiêu retry (RPC đồng bộ cả chapter)."""
    sb().rpc("defer_translation_job", {
        "p_job_id": job_id,
        "p_worker_id": worker_id,
        "p_error": (error or "")[:2000],
        "p_restore_attempt": restore_attempt,
    }).execute()


def is_transient_error(exc: Exception) -> bool:
    """Nhận diện lỗi mạng/DB tạm thời để không tính thành lỗi chất lượng bản dịch."""
    current: BaseException | None = exc
    seen: set[int] = set()
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        name = type(current).__name__.lower()
        module = type(current).__module__.lower()
        message = str(current).lower()
        code = str(getattr(current, "code", "")).upper()
        response = getattr(current, "response", None)
        status = getattr(response, "status_code", None)
        # 4xx (trừ 408/425/429) là lỗi vĩnh viễn: model gỡ (410), key sai (401),
        # payload hỏng (400). Chặn ở đây vì SDK openai bọc trong httpx nên nhánh
        # module.startswith("httpx") bên dưới sẽ nuốt tất và retry vô hạn.
        if isinstance(status, int) and 400 <= status < 500 and status not in (408, 425, 429):
            return False
        if (
            module.startswith(("httpx", "httpcore"))
            or any(k in name for k in ("timeout", "connection", "protocol", "network"))
            or status in (408, 425, 429)
            or isinstance(status, int) and status >= 500
            or code.startswith("08") or code in {"PGRST000", "PGRST001", "PGRST002"}
            or any(k in message for k in (
                "server disconnected", "connection terminated", "connection reset",
                "remoteprotocolerror", "read timeout", "connect timeout",
                "temporarily unavailable", "bad gateway", "gateway timeout",
                "cloudflare"))
        ):
            return True
        current = current.__cause__ or current.__context__
    return False


def insert_glossary_suggestions(rows: list[dict]) -> set[str]:
    """Ghi cả batch; unique (novel_id, term_zh) giữ cách dịch xuất hiện đầu tiên.
    Trả set term_zh thật sự được chèn — row thua race bị bỏ qua để caller lộ conflict.

    Cụm tiếng Anh dịch nghĩa bị CHẶN NGAY, không chờ dọn sau: model trích tên đổi là
    chất lượng đổi (25-26/07/2026: 47% gợi ý ra tiếng Anh), mà thứ đó không dùng được
    ở bất kỳ đâu. Tỉ lệ chặn cao = model đang hỏng → log WARNING để lộ ra ở log thay vì
    phải tự đi soi bảng glossary."""
    if not rows:
        return set()
    from .translator import hanviet  # import muộn: db dùng được khi không tải translator

    good, bad = [], []
    for r in rows:
        (bad if hanviet.english_meaning(
            r.get("term_zh"), r.get("correct_vi"), r.get("term_type")) else good).append(r)
    if bad:
        say = log.warning if len(bad) * 2 >= len(rows) else log.info
        say("Glossary: bỏ %d/%d gợi ý tiếng Anh (vd %s) — tỉ lệ cao thì soi lại model trích tên",
            len(bad), len(rows), bad[0].get("correct_vi"))
        rows = good
    if not rows:
        return set()
    res = sb().table("glossary_terms").upsert(
        rows, on_conflict="novel_id,term_zh", ignore_duplicates=True
    ).execute()
    return {r.get("term_zh") for r in (res.data or [])}


def sweep_glossary(since: str | None = None, dry: bool = False,
                   fix: bool = True, clean: bool = True) -> tuple[list[dict], list[dict]]:
    """Rà gợi ý CHƯA DUYỆT: viết bằng pinyin → sửa về Hán-Việt; cụm tiếng Anh → xoá.
    Trả (đã sửa, đã xoá).

    Cùng một hàm cho hai đường gọi, để luật chỉ tồn tại ở MỘT chỗ:
      * worker gọi mỗi chu kỳ audit với `since` = mốc lần rà trước → chỉ đọc term mới,
        egress không đáng kể, và không cần ai nhớ chạy tay;
      * lệnh `gfix`/`gclean` gọi với since=None → rà cả kho, dùng sau khi SỬA LUẬT
        (luật mới phải được áp lại lên dữ liệu cũ).
    Term đã duyệt không bao giờ bị đụng — xem docstring run_gclean."""
    from .translator import hanviet

    rows, off, step = [], 0, 1000
    while True:
        q = (sb().table("glossary_terms")
             .select("id, novel_id, term_zh, correct_vi, term_type, wrong_vi, created_by, note")
             .eq("approved", False))
        if since:
            q = q.gte("created_at", since)
        page = (q.order("id").range(off, off + step - 1).execute()).data or []
        rows += page
        if len(page) < step:
            break
        off += step
    from .translator.worker import _conflicts_with_base_term
    by_novel: dict[int, list[dict]] = {}
    for t in rows:
        by_novel.setdefault(t["novel_id"], []).append(t)

    fixed, dropped, flagged, cleared = [], [], [], []
    for t in rows:
        if t.get("created_by"):        # user thêm tay → chủ đích, không đoán thay
            continue
        zh, vi, tp = t["term_zh"], t["correct_vi"], t["term_type"]
        hv = hanviet.pinyin_written(zh, vi, tp) if fix else None
        if hv:
            fixed.append({**t, "new_vi": hv})
        elif (fix and t.get("note") != "nghi sai"
              and hanviet.pinyin_suspect(zh, vi)):
            # tên người viết bằng pinyin: không đủ căn cứ để tự đổi → 'nghi sai',
            # term rơi khỏi prompt dịch nhưng vẫn nằm ở mục chờ duyệt trong app
            flagged.append({**t, "new_vi": "(nghi sai)"})
        elif (fix and t.get("note") == "nghi sai"
              and not hanviet.transliteration_suspect(zh, vi, tp)
              and not hanviet.pinyin_suspect(zh, vi)
              # 'nghi sai' còn được gắn vì mâu thuẫn term gốc — kiểm lại kẻo gỡ nhầm
              and not _conflicts_with_base_term(by_novel.get(t["novel_id"], []), zh, vi)):
            cleared.append({**t, "new_vi": "(bỏ nghi sai)"})
        elif clean and hanviet.english_meaning(zh, vi, tp):
            dropped.append(t)
    if dry:
        return fixed + flagged + cleared, dropped
    for t in flagged:
        sb().table("glossary_terms").update(
            {"note": "nghi sai"}, returning="minimal").eq("id", t["id"]).execute()
    for t in cleared:
        sb().table("glossary_terms").update(
            {"note": None}, returning="minimal").eq("id", t["id"]).execute()
    for t in fixed:
        sb().table("glossary_terms").update(
            {"correct_vi": t["new_vi"], "wrong_vi": t.get("wrong_vi") or t["correct_vi"]},
            returning="minimal").eq("id", t["id"]).execute()
    ids = [t["id"] for t in dropped]
    for i in range(0, len(ids), 200):   # chia lô: URL của .in_() có giới hạn độ dài
        sb().table("glossary_terms").delete(returning="minimal").in_(
            "id", ids[i:i + 200]).execute()
    return fixed + flagged + cleared, dropped


def record_glossary_conflicts(novel_id: int, rows: list[dict]) -> None:
    """Ghi cách dịch mâu thuẫn đầu tiên lên row local, không đụng correct_vi/approved."""
    for row in rows:
        sb().table("glossary_terms").update({"conflict_vi": row["conflict_vi"]}) \
            .eq("novel_id", novel_id).eq("term_zh", row["term_zh"]) \
            .is_("conflict_vi", "null").neq("correct_vi", row["candidate_vi"]).execute()


def enqueue(type_: str, novel_id: int, chapter_id: int | None = None, priority: int = 100) -> None:
    try:
        sb().table("translation_jobs").insert(
            {"type": type_, "novel_id": novel_id, "chapter_id": chapter_id,
             "priority": priority},
            returning="minimal",
        ).execute()
    except Exception as e:  # unique index chặn job trùng → bỏ qua
        if "duplicate" not in str(e).lower() and "unique" not in str(e).lower():
            raise
        log.debug("job trùng, bỏ qua: %s novel=%s ch=%s", type_, novel_id, chapter_id)


def requeue_stale_jobs(max_minutes: int = 10) -> int:
    """Job 'running' quá lâu (worker chết/mất mạng giữa chừng) → trả về hàng đợi.

    Chạy định kỳ trong translator loop — không cần pg_cron.
    Job hết lượt retry (attempts >= max_attempts CỦA CHÍNH NÓ) thì đánh failed,
    không còn hardcode attempts >= 3 như trước (job max_attempts cao bị chặt oan).

    Chọn TRƯỚC rồi mới update theo id: returning="minimal" trả body rỗng nên
    bản cũ đọc .data sau update luôn được [] — phần đồng bộ chương chưa từng chạy.
    """
    cutoff = (datetime.now(timezone.utc) - timedelta(minutes=max_minutes)).isoformat()

    rows = (
        sb().table("translation_jobs")
        .select("id,chapter_id,attempts,max_attempts")
        .eq("status", "running").lt("locked_at", cutoff)
        .execute()
    ).data or []
    dead = [j for j in rows if j["attempts"] >= j["max_attempts"]]
    stale = [j for j in rows if j["attempts"] < j["max_attempts"]]

    if dead:
        sb().table("translation_jobs").update(
            {"status": "failed", "locked_by": None, "locked_at": None,
             "error": f"worker không phản hồi sau {max_minutes} phút, hết lượt retry"},
            returning="minimal",
        ).in_("id", [j["id"] for j in dead]).execute()
    if stale:
        sb().table("translation_jobs").update(
            {"status": "pending", "locked_by": None, "locked_at": None,
             "error": f"requeue: worker không phản hồi sau {max_minutes} phút"},
            returning="minimal",
        ).in_("id", [j["id"] for j in stale]).execute()

    # đồng bộ trạng thái chương tương ứng
    failed_ch = [j["chapter_id"] for j in dead if j.get("chapter_id")]
    requeued_ch = [j["chapter_id"] for j in stale if j.get("chapter_id")]
    if failed_ch:
        sb().table("chapters").update({"translation_status": "failed"}, returning="minimal").in_("id", failed_ch).execute()
    if requeued_ch:
        sb().table("chapters").update({"translation_status": "queued"}, returning="minimal").in_("id", requeued_ch).execute()

    n = len(dead) + len(stale)
    if n:
        log.warning("Reaper: %d job kẹt (%d requeue, %d failed)", n, len(stale), len(dead))
    return n


def reset_orphan_chapters() -> int:
    """Chương kẹt 'queued'/'translating' nhưng KHÔNG còn job pending/running (job bị
    huỷ/xoá mà chương chưa reset — vd huỷ tay trong DB) → trả về 'none'.

    Không có job thì chương này treo mãi ở màn Hàng đợi (đọc từ chapters.status).
    Chạy trong housekeeping cùng reaper. Luồng bình thường an toàn: request_translation
    set 'queued' + insert job trong CÙNG transaction plpgsql nên không bao giờ mồ côi tức thời.
    1 câu SQL (RPC, migration 024) — bản Python cũ kéo 2 bảng về so, dính trần 1000 dòng.
    """
    n = sb().rpc("reset_orphan_chapters").execute().data or 0
    if n:
        log.warning("Reaper: reset %d chương mồ côi (queued/translating không có job) về none", n)
    return n


def cleanup_orphan_translation_jobs() -> int:
    """Xoá job chapter pending khi chapter không còn queued/translating."""
    n = sb().rpc("cleanup_orphan_translation_jobs").execute().data or 0
    if n:
        log.warning("Reaper: xoá %d job pending lệch trạng thái chapter", n)
    return n


def reprioritize_chapters_by_reading(active_hours: int, prio_read: int, prio_idle: int) -> int:
    """Bám hoạt động đọc thật: chương pending của truyện có reader trong `active_hours`
    giờ qua → ưu tiên cao (prio_read); truyện không ai đọc → đẩy ra sau (prio_idle).

    Chỉ đụng job type='chapter' đang 'pending' (metadata không động tới).
    Chạy mỗi vòng housekeeping — quy mô nhỏ (2-5 user) nên quét thẳng, chưa cần tối ưu.
    """
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=active_hours)).isoformat()
    active = {
        r["novel_id"] for r in
        (sb().table("reading_progress").select("novel_id").gte("updated_at", cutoff).execute().data or [])
    }
    # page qua trần 1000 dòng PostgREST — backlog > 1000 job chương (1 truyện dài là
    # vượt) thì kéo 1 lần sẽ bỏ sót job của truyện đang đọc → không nâng prio_read được
    jobs: list[dict] = []
    frm = 0
    while True:
        b = (
            sb().table("translation_jobs").select("id, novel_id, priority")
            .eq("type", "chapter").eq("status", "pending")
            .order("id").range(frm, frm + 999).execute()
        ).data or []
        jobs += b
        if len(b) < 1000:
            break
        frm += 1000
    # gom 2 update theo lô thay vì 1 update/job (housekeeping chạy mỗi 60s)
    to_read = [j["id"] for j in jobs if j["novel_id"] in active and j["priority"] != prio_read]
    to_idle = [j["id"] for j in jobs if j["novel_id"] not in active and j["priority"] != prio_idle]
    # batch .in_() — backlog lớn (requeue hàng loạt) khiến list id quá dài → PostgREST 400.
    for ids, prio in ((to_read, prio_read), (to_idle, prio_idle)):
        for i in range(0, len(ids), 200):
            sb().table("translation_jobs").update({"priority": prio}, returning="minimal").in_("id", ids[i:i + 200]).execute()
    return len(to_read) + len(to_idle)


def queue_snapshot() -> dict[str, int]:
    """Đếm job chờ / đang chạy — cho dòng nhịp tiến độ mỗi 60s trong log translator."""
    def n(status: str) -> int:
        return (
            sb().table("translation_jobs").select("id", count="exact")
            .eq("status", status).limit(1).execute()
        ).count or 0
    return {"pending": n("pending"), "running": n("running")}


def count_chapters_translated_today() -> int:
    """Đếm chương dịch xong từ 00:00 UTC hôm nay — dùng cho cầu chì chi phí."""
    day_start = datetime.now(timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    ).isoformat()
    res = (
        sb().table("chapters").select("id", count="exact")
        .eq("translation_status", "done").gte("translated_at", day_start)
        .execute()
    )
    return res.count or 0


def lint_drift_novels() -> list[dict]:
    return sb().rpc("lint_drift_novels").execute().data or []


def record_model_call(model: str, latency_ms: int, ok: bool, error: str | None = None) -> None:
    """Ghi latency + ok/fail mỗi lần gọi model (tab Token admin). Best-effort — KHÔNG được
    làm hỏng đường dịch nếu ghi lỗi."""
    try:
        sb().rpc("bump_model_health", {
            "p_model": model, "p_latency_ms": int(latency_ms),
            "p_ok": ok, "p_error": (error or "")[:300] or None,
        }).execute()
    except Exception:
        log.debug("record_model_call lỗi (bỏ qua) model=%s", model)


def record_crawl_latency(source: str, n: int, ok: int, p50: float, p95: float,
                         mx: float, timeouts: int, http429: int) -> None:
    """P2b-0: ghi 1 cửa sổ đo latency crawl vào bảng crawl_latency (đọc từ Supabase).
    Best-effort — KHÔNG được làm hỏng đường crawl nếu ghi lỗi."""
    try:
        sb().table("crawl_latency").insert({
            "source": source, "n": n, "ok": ok,
            "p50_s": round(p50, 2), "p95_s": round(p95, 2), "max_s": round(mx, 2),
            "timeouts": timeouts, "http_429": http429,
        }).execute()
    except Exception:
        log.debug("record_crawl_latency lỗi (bỏ qua) source=%s", source)


def heartbeat(name: str, note: str | None = None) -> None:
    """Điểm danh định kỳ (crawler/translator) — tab Worker hiện sống/chết thật.
    Best-effort: lỗi mạng thì bỏ qua, không được làm hỏng vòng chính."""
    try:
        sb().table("worker_heartbeat").upsert(
            {"name": name, "at": utc_now(), "note": note}).execute()
    except Exception:
        log.debug("heartbeat lỗi (bỏ qua): %s", name)


def report_host_metrics(stats: dict) -> None:
    """Đẩy số liệu máy chủ chạy worker lên host_metrics (màn 'Theo dõi VPS' trong app).
    Best-effort: thiếu bảng (chưa migrate) / lỗi mạng → bỏ qua. Đổi VPS chỉ cần worker
    trên máy mới đẩy dòng host mới — app tự thấy thêm."""
    if not stats.get("host"):
        return
    try:
        sb().table("host_metrics").upsert(
            {**stats, "updated_at": utc_now()}, on_conflict="host").execute()
    except Exception as e:
        log.debug("report_host_metrics bỏ qua: %s", e)


def prune_stale_hosts(days: int = 30) -> None:
    """Xoá dòng host_metrics không cập nhật lâu (host ma từ container-ID cũ / VPS đã
    bỏ). Gọi thưa từ vòng metrics; lỗi thì bỏ qua."""
    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    try:
        sb().table("host_metrics").delete().lt("updated_at", cutoff).execute()
    except Exception as e:
        log.debug("prune_stale_hosts bỏ qua: %s", e)


def claim_host_command(host: str) -> dict | None:
    """Lấy 1 lệnh pending cho host này và đánh 'running'. Mỗi host 1 crawler nên
    không cần khoá phức tạp; 2 luồng đua nhau thì worst case chạy 2 lần lệnh idempotent."""
    try:
        rows = (
            sb().table("host_commands").select("id, command")
            .eq("host", host).eq("status", "pending")
            .order("created_at").limit(1).execute().data or []
        )
    except Exception as e:
        log.debug("claim_host_command bỏ qua: %s", e)
        return None
    if not rows:
        return None
    cmd = rows[0]
    try:
        sb().table("host_commands").update(
            {"status": "running", "updated_at": utc_now()}).eq("id", cmd["id"]).execute()
    except Exception:
        pass
    return cmd


def finish_host_command(cmd_id: int, status: str, output: str = "") -> None:
    try:
        sb().table("host_commands").update(
            {"status": status, "output": output[:2000], "updated_at": utc_now()}
        ).eq("id", cmd_id).execute()
    except Exception:
        log.debug("finish_host_command lỗi (bỏ qua)")


def host_identity() -> str:
    """Định danh ỔN ĐỊNH của máy chạy worker cho host_metrics. Thứ tự ưu tiên:
    env WORKER_HOST > /etc/machine-id (docker-compose mount file của HOST vào nên
    sống qua mọi lần recreate container) > hostname. Không có cái này thì hostname
    trong Docker là ID ngẫu nhiên → mỗi lần rebuild thành 'một VPS mới'."""
    import os
    import socket

    env = os.environ.get("WORKER_HOST", "").strip()
    if env:
        return env
    try:
        with open("/etc/machine-id", encoding="ascii") as f:
            mid = f.read().strip()
        if mid:
            return mid[:12]  # đủ phân biệt, khỏi lôi chuỗi 32 ký tự vào UI
    except OSError:
        pass
    return socket.gethostname()


# Mẫu mạng lần trước để tự tính tốc độ down/up giữa 2 lần đẩy (kB/s).
_net_prev: tuple[float, int, int] | None = None  # (monotonic, rx_bytes, tx_bytes)


def collect_host_stats(cpu_pct: float | None = None) -> dict:
    """Đọc số liệu hệ điều hành (Linux/VPS) KHÔNG cần psutil: /proc/meminfo,
    /proc/loadavg, /proc/uptime, /proc/net/dev, statvfs('/'). cpu_pct truyền vào từ
    vòng đo riêng (/proc/stat 2 lần) vì một lần đọc không ra được %. Trên Windows trả
    dict tối thiểu — chỉ để script chạy được khi dev local."""
    import os
    import socket

    def _read(path: str) -> str:
        with open(path, encoding="ascii") as f:
            return f.read()

    stats: dict = {"host": host_identity()}
    try:
        mem = {}
        for line in _read("/proc/meminfo").splitlines():
            k, _, v = line.partition(":")
            mem[k.strip()] = int(v.strip().split()[0])  # kB
        total = mem.get("MemTotal", 0)
        avail = mem.get("MemAvailable", 0)
        stats["mem_total_mb"] = total // 1024
        stats["mem_used_mb"] = max(0, (total - avail)) // 1024
        swap_total = mem.get("SwapTotal", 0)
        swap_free = mem.get("SwapFree", 0)
        stats["swap_used_mb"] = max(0, swap_total - swap_free) // 1024
    except OSError:
        pass
    try:
        parts = _read("/proc/loadavg").split()
        stats["load1"] = round(float(parts[0]), 2)
        stats["cpu_count"] = os.cpu_count()
    except (OSError, ValueError, IndexError):
        pass
    try:
        vm = os.statvfs("/")
        total_gb = vm.f_blocks * vm.f_frsize // (1 << 30)
        free_gb = vm.f_bavail * vm.f_frsize // (1 << 30)
        stats["disk_total_gb"] = total_gb
        stats["disk_used_gb"] = max(0, total_gb - free_gb)
    except OSError:
        pass
    try:
        stats["uptime_h"] = round(float(_read("/proc/uptime").split()[0]) / 3600, 1)
    except (OSError, ValueError, IndexError):
        pass
    # Mạng: tổng tích luỹ + tốc độ so với mẫu lần trước (trừ loopback).
    global _net_prev
    try:
        rx = tx = 0
        for line in _read("/proc/net/dev").splitlines()[2:]:
            iface, _, data = line.partition(":")
            if iface.strip() == "lo":
                continue
            cols = data.split()
            rx += int(cols[0])
            tx += int(cols[8])
        stats["net_rx_gb"] = round(rx / (1 << 30), 2)
        stats["net_tx_gb"] = round(tx / (1 << 30), 2)
        now = _time.monotonic()
        if _net_prev is not None:
            dt, prx, ptx = _net_prev
            if now > dt:
                stats["net_rx_kbps"] = round((rx - prx) / (now - dt) / 1024, 1)
                stats["net_tx_kbps"] = round((tx - ptx) / (now - dt) / 1024, 1)
        _net_prev = (now, rx, tx)
    except (OSError, ValueError, IndexError):
        pass
    if cpu_pct is not None:
        stats["cpu_pct"] = round(cpu_pct, 1)
    return stats


def read_cpu_jiffies() -> tuple[int, int]:
    """Đọc (busy, idle+iowait) tích lũy từ /proc/stat. Caller gọi 2 lần cách nhau vài
    giây rồi tự tính %CPU = Δbusy / (Δbusy + Δidle) — một lần đọc không ra được %."""
    with open("/proc/stat", encoding="ascii") as f:
        vals = [int(x) for x in f.readline().split()[1:]]  # dòng 'cpu' tổng hợp
    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
    return sum(vals) - idle, idle


def runtime_settings() -> dict[str, str]:
    """Config chỉnh từ app (bảng worker_settings) — đọc mỗi chu kỳ discovery,
    đổi trong app là ăn ngay không cần restart. Lỗi/thiếu → {} (dùng default code)."""
    try:
        rows = sb().table("worker_settings").select("key, value").execute().data or []
        return {r["key"]: r["value"] for r in rows}
    except Exception:
        log.warning("Không đọc được worker_settings — dùng default trong config.py")
        return {}


def last_discovery_at(source_id: int) -> float:
    """Mốc discovery mới nhất của nguồn, lưu bền qua restart worker."""
    rows = (
        sb().table("crawl_discovery_frontier").select("updated_at")
        .eq("source_id", source_id).order("updated_at", desc=True).limit(1).execute()
    ).data or []
    if not rows:
        return 0.0  # nguồn mới chưa có frontier → discovery ngay
    return datetime.fromisoformat(rows[0]["updated_at"].replace("Z", "+00:00")).timestamp()


def runtime_int(rs: dict, key: str, cur: int, lo: int = 1) -> int:
    """Ép 1 giá trị worker_settings về int ≥ lo; thiếu/hỏng → giữ giá trị hiện tại."""
    try:
        return max(lo, int(rs.get(key, cur)))
    except (TypeError, ValueError):
        return cur


def runtime_str(rs: dict, key: str, cur: str) -> str:
    """Như runtime_int nhưng cho chuỗi (tên model LLM). Rỗng/thiếu → giữ giá trị hiện tại."""
    return str(rs.get(key) or "").strip() or cur


# ---------- cache bìa (Supabase Storage) ----------

def upload_cover(path: str, data: bytes, content_type: str) -> None:
    sb().storage.from_("covers").upload(
        path, data,
        {"content-type": content_type or "image/jpeg", "upsert": "true", "cache-control": "86400"},
    )


def cover_public_url(path: str) -> str:
    return sb().storage.from_("covers").get_public_url(path)


# ---------- sức khoẻ nguồn ----------

def mark_source_ok(source_id: int) -> None:
    """Nguồn reach được (ít nhất 1 fetch OK trong chu kỳ) → reset fail, cập nhật mốc OK."""
    sb().table("sources").update(
        {"last_ok_at": utc_now(), "fail_count": 0}).eq("id", source_id).execute()


def mark_source_fail(source_id: int, fail_limit: int) -> bool:
    """Chu kỳ toàn fail (domain chết/SSL/403) → fail_count++. Vượt ngưỡng → tự tắt nguồn.
    Trả True nếu vừa bị tắt. Chỉ tắt khi TOÀN fetch fail nhiều chu kỳ → không tắt oan
    nguồn còn sống (vd shuhaige homepage flaky nhưng trang truyện vẫn OK)."""
    row = sb().table("sources").select("fail_count, enabled").eq("id", source_id).single().execute().data
    n = (row["fail_count"] or 0) + 1
    patch: dict[str, Any] = {"fail_count": n}
    disabled = n >= fail_limit and row.get("enabled")
    if disabled:
        patch["enabled"] = False
    sb().table("sources").update(patch).eq("id", source_id).execute()
    return disabled


# ---------- glossary ----------

# Thay theo RANH GIỚI TỪ. Cặp sửa của user là tiếng Việt ('em'→'muội'); replace() thô biến
# "xem" thành "xmuội" và term "Kiếm" thành "Kimuội" — đã ra lỗi thật (chapter_edit_vi_history).
# Chữ Hán không có biên từ nên chỉ dùng hàm này cho cặp Việt→Việt.
def replace_word(text: str, wrong: str, correct: str) -> str:
    if not wrong:
        return text
    return re.sub(rf"(?<!\w){re.escape(wrong)}(?!\w)", correct.replace("\\", "\\\\"), text)


def heal_glossary_terms(terms: list[dict]) -> list[dict]:
    """User sửa bản dịch qua form ("Hoan Yêu"→"Huyễn Yêu", term thường KHÔNG có term_zh)
    nhưng gợi ý LLM mang đúng cái sai đó (幻妖→"Hoan Yêu") vẫn nằm trong glossary → prompt
    tiếp tục ÉP model dịch sai ở mọi chương sau. Áp các cặp sửa (wrong_vi→correct_vi) lên
    correct_vi của những term khác, sửa IN-PLACE; bản cũ ghi vào wrong_vi (prompt nhắc
    "KHÔNG dịch thành ..." + job patch vá được chương cũ). Trả list term đã đổi."""
    repls = [(t["wrong_vi"], t["correct_vi"]) for t in terms
             if t.get("wrong_vi") and t.get("correct_vi") and t["wrong_vi"] != t["correct_vi"]]
    changed: list[dict] = []
    for t in terms:
        cv = t.get("correct_vi") or ""
        new = cv
        for w, c in repls:
            new = replace_word(new, w, c)
        if new != cv:
            if not t.get("wrong_vi"):
                t["wrong_vi"] = cv
            t["correct_vi"] = new
            changed.append(t)
    return changed


# Tên phương Tây giữ nguyên chữ Latin: "Maria", "Elton", "GG-Captain", "Simon Elton".
# Tối đa 3 từ: tên người trong truyện Trung hiếm khi dài hơn, mà cụm dài gần như luôn là
# LLM dịch NGHĨA sang tiếng Anh ("A City Central Hospital") chứ không phải phiên âm tên.
_LATIN_NAME = re.compile(r"^[A-Z][A-Za-z]*(?:[ .'\-][A-Za-z]+){0,2}$")
# Danh từ chung LLM hay gắn nhãn person: ghim lại thì mọi chỗ "cha" thành "Ba Ba".
_NOT_A_NAME = {
    "爸爸", "妈妈", "父亲", "母亲", "爷爷", "奶奶", "外公", "外婆", "哥哥", "姐姐",
    "弟弟", "妹妹", "叔叔", "阿姨", "舅舅", "儿子", "女儿", "老师", "师父", "师傅",
    "先生", "小姐", "夫人", "老板", "大人", "少爷", "小子", "老头", "丫头",
}


def _is_safe_pending_term(term: dict, canonical_vi: str | None) -> bool:
    """Chỉ cho tên riêng có đối chiếu chắc chắn đi qua trước khi được duyệt tay.

    Hai dạng được coi là chắc chắn:
    1. Bản dịch trùng đúng cách đọc Hán-Việt (tên Trung).
    2. Bản dịch là tên Latin thuần (tên Tây phiên qua tiếng Trung). Trước đây dạng này bị
       loại vì hanviet(玛利亚) = "Mã Lợi Á" ≠ "Maria" — đúng lớp tên mà model phiên loạn
       nhất (Malia/Marya/Mary/Mã Lợi Á trong cùng một chương) nên không ghim là hỏng nhất.

    Ngoại lệ (2) CHỈ áp cho tên NGƯỜI. Đo 26/07: nó từng cho 1137 term place/sect lọt vào
    bản dịch dưới dạng tiếng Anh dịch nghĩa — 组织→"Organization", 青年团→"Youth League",
    A基地→"A Base" — rồi termguard cưỡng chế thẳng vào câu tiếng Việt. Địa danh/môn phái
    không có lý do gì phải giữ chữ Latin: nếu đúng thì nó khớp Hán-Việt ở nhánh (1).
    """
    if term.get("term_type") not in {"person", "place", "sect"}:
        return False
    correct = (term.get("correct_vi") or "").strip()
    if not correct or (term.get("term_zh") or "").strip() in _NOT_A_NAME:
        return False
    if canonical_vi and correct == canonical_vi:
        return True
    if term.get("term_type") != "person":
        return False
    return correct.isascii() and bool(_LATIN_NAME.match(correct))


# ponytail: van chặn phình, KHÔNG phải để tiết kiệm prompt — termguard/prompts đều đã lọc
# term theo sự hiện diện trong chữ Hán nên term thừa gần như miễn phí. Trần đặt trên mức
# thực đo (26/07: median 21, p90 43, max 604) để hôm nay không cắt gì; nó chỉ chặn một
# truyện kéo vô hạn row mỗi chương. Cắt theo hit_count giảm dần → phần rơi là term ít gặp nhất.
PENDING_LIMIT = 1000


def get_glossary(novel_id: int) -> tuple[list[dict], int]:
    """Trả về (terms, version). Gồm term đã duyệt (truyện + global) VÀ term gợi ý
    (approved=false) của truyện.

    Gợi ý phải được dùng lại NGAY ở chương sau — trước đây chỉ lấy approved=true nên
    tên LLM tự phát hiện không bao giờ quay lại prompt, mỗi chương phiên âm một kiểu
    (bug "Lao Sen/Lâm Tùng"). Term duyệt tay thắng khi trùng term_zh; giữa các gợi ý,
    gợi ý CŨ nhất thắng (giữ cách phiên âm xuất hiện đầu tiên)."""
    terms = (
        sb().table("glossary_terms")
        .select("id,novel_id,term_zh,wrong_vi,correct_vi,term_type,note,narrator_term,approved,first_chapter,hit_count,conflict_vi")
        .eq("approved", True)
        .or_(f"novel_id.eq.{novel_id},novel_id.is.null")
        .execute()
    ).data or []
    seen = {t["term_zh"] for t in terms if t.get("term_zh")}
    pending = (
        sb().table("glossary_terms")
        .select("id,novel_id,term_zh,wrong_vi,correct_vi,term_type,note,narrator_term,approved,first_chapter,hit_count,conflict_vi")
        .eq("approved", False).eq("novel_id", novel_id)
        .order("hit_count", desc=True).order("created_at")
        .limit(PENDING_LIMIT)
        .execute()
    ).data or []
    # import muộn: db dùng được độc lập trong các tool không tải translator.
    from .translator import hanviet

    for t in pending:
        zh = t.get("term_zh")
        if zh and zh not in seen and _is_safe_pending_term(t, hanviet.han_viet(zh)):
            seen.add(zh)
            terms.append(t)
    # lành hoá gợi ý mang bản dịch đã bị user sửa; persist để màn Thuật ngữ cũng thấy
    # bản đúng (chỉ term của truyện này — không đụng term global từ sửa cục bộ)
    for t in heal_glossary_terms(terms):
        if t.get("id") and t.get("novel_id") == novel_id:
            try:
                sb().table("glossary_terms").update(
                    {"correct_vi": t["correct_vi"], "wrong_vi": t["wrong_vi"]}
                ).eq("id", t["id"]).execute()
            except Exception:
                log.debug("heal glossary term %s lỗi (bỏ qua)", t.get("id"))
    ver_rows = (
        sb().table("novel_glossary_version").select("version").eq("novel_id", novel_id).execute()
    ).data
    version = ver_rows[0]["version"] if ver_rows else 0
    return terms, version


def increment_glossary_hits(novel_id: int, terms: list[str]) -> None:
    if terms:
        sb().rpc("increment_glossary_hits", {"p_novel_id": novel_id, "p_terms": terms}).execute()
