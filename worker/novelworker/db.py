"""Supabase client (service role) + các thao tác DB dùng chung."""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from typing import Any

from supabase import Client, create_client

from .config import settings

log = logging.getLogger(__name__)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


@lru_cache(maxsize=1)
def sb() -> Client:
    return create_client(settings.supabase_url, settings.supabase_service_role_key)


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
            rows[i:i + 500], on_conflict="novel_id,chapter_index"
        ).execute()


def save_chapter_raw(chapter_id: int, content_zh: str) -> None:
    sb().table("chapters").update({"content_zh": content_zh}).eq("id", chapter_id).execute()


def save_chapter_translation(
    chapter_id: int, title_vi: str | None, content_vi: str,
    model: str, prompt_tokens: int, completion_tokens: int, glossary_version: int,
    summary_vi: str | None = None,
) -> None:
    sb().table("chapters").update(
        {
            "title_vi": title_vi,
            "summary_vi": summary_vi,
            "content_vi": content_vi,
            # Xoá bản gốc khi dịch xong — tiết kiệm ~2/3 dung lượng DB. Dịch lại
            # vẫn chạy: chương queued thiếu content_zh → translator defer job,
            # crawler backfill tự tải lại từ nguồn (sync.py).
            "content_zh": None,
            "translation_status": "done",
            "translated_at": utc_now(),
            "model_used": model,
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "glossary_version": glossary_version,
        }
    ).eq("id", chapter_id).execute()


def bump_translated_count(novel_id: int) -> None:
    done = (
        sb().table("chapters").select("id", count="exact")
        .eq("novel_id", novel_id).eq("translation_status", "done").execute()
    )
    sb().table("novels").update({"chapter_count_translated": done.count or 0}).eq("id", novel_id).execute()


# ---------- jobs ----------

def claim_next_job(worker_id: str) -> dict | None:
    res = sb().rpc("claim_next_job", {"worker_id": worker_id}).execute()
    return res.data[0] if res.data else None


def refresh_job_lock(job_id: int, worker_id: str) -> None:
    """Gia hạn lease để reaper không lấy lại job LLM vẫn đang chạy."""
    sb().table("translation_jobs").update({"locked_at": utc_now()}).eq(
        "id", job_id
    ).eq("status", "running").eq("locked_by", worker_id).execute()


def finish_job(job_id: int, ok: bool, error: str | None = None) -> None:
    if ok:
        sb().table("translation_jobs").update(
            {"status": "done", "done_at": utc_now(), "error": None, "locked_by": None, "locked_at": None}
        ).eq("id", job_id).execute()
        return
    # thất bại: còn lượt thì trả về pending để retry, hết lượt thì failed
    job = sb().table("translation_jobs").select("attempts,max_attempts,chapter_id").eq("id", job_id).single().execute().data
    status = "pending" if job["attempts"] < job["max_attempts"] else "failed"
    sb().table("translation_jobs").update(
        {"status": status, "error": (error or "")[:2000], "locked_by": None, "locked_at": None}
    ).eq("id", job_id).execute()
    if job.get("chapter_id"):
        sb().table("chapters").update(
            {"translation_status": "failed" if status == "failed" else "queued"}
        ).eq("id", job["chapter_id"]).execute()


def defer_job(job_id: int, error: str | None = None) -> None:
    sb().table("translation_jobs").update(
        {"status": "pending", "error": (error or "")[:2000], "locked_by": None, "locked_at": None}
    ).eq("id", job_id).execute()


def enqueue(type_: str, novel_id: int, chapter_id: int | None = None, priority: int = 100) -> None:
    try:
        sb().table("translation_jobs").insert(
            {"type": type_, "novel_id": novel_id, "chapter_id": chapter_id, "priority": priority}
        ).execute()
    except Exception as e:  # unique index chặn job trùng → bỏ qua
        if "duplicate" not in str(e).lower() and "unique" not in str(e).lower():
            raise
        log.debug("job trùng, bỏ qua: %s novel=%s ch=%s", type_, novel_id, chapter_id)


def requeue_stale_jobs(max_minutes: int = 10) -> int:
    """Job 'running' quá lâu (worker chết/mất mạng giữa chừng) → trả về hàng đợi.

    Chạy định kỳ trong translator loop — không cần pg_cron.
    Job đã hết lượt retry (attempts >= 3) thì đánh failed luôn thay vì lặp vô hạn.
    """
    cutoff = (datetime.now(timezone.utc) - timedelta(minutes=max_minutes)).isoformat()

    # hết lượt → failed
    dead = (
        sb().table("translation_jobs")
        .update({"status": "failed", "locked_by": None, "locked_at": None,
                 "error": f"worker không phản hồi sau {max_minutes} phút, hết lượt retry"})
        .eq("status", "running").lt("locked_at", cutoff).gte("attempts", 3)
        .execute()
    ).data or []

    # còn lượt → pending
    stale = (
        sb().table("translation_jobs")
        .update({"status": "pending", "locked_by": None, "locked_at": None,
                 "error": f"requeue: worker không phản hồi sau {max_minutes} phút"})
        .eq("status", "running").lt("locked_at", cutoff)
        .execute()
    ).data or []

    # đồng bộ trạng thái chương tương ứng
    failed_ch = [j["chapter_id"] for j in dead if j.get("chapter_id")]
    requeued_ch = [j["chapter_id"] for j in stale if j.get("chapter_id")]
    if failed_ch:
        sb().table("chapters").update({"translation_status": "failed"}).in_("id", failed_ch).execute()
    if requeued_ch:
        sb().table("chapters").update({"translation_status": "queued"}).in_("id", requeued_ch).execute()

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
    jobs = (
        sb().table("translation_jobs").select("id, novel_id, priority")
        .eq("type", "chapter").eq("status", "pending").execute()
    ).data or []
    # gom 2 update theo lô thay vì 1 update/job (housekeeping chạy mỗi 60s)
    to_read = [j["id"] for j in jobs if j["novel_id"] in active and j["priority"] != prio_read]
    to_idle = [j["id"] for j in jobs if j["novel_id"] not in active and j["priority"] != prio_idle]
    if to_read:
        sb().table("translation_jobs").update({"priority": prio_read}).in_("id", to_read).execute()
    if to_idle:
        sb().table("translation_jobs").update({"priority": prio_idle}).in_("id", to_idle).execute()
    return len(to_read) + len(to_idle)


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


def heartbeat(name: str, note: str | None = None) -> None:
    """Điểm danh định kỳ (crawler/translator) — tab Worker hiện sống/chết thật.
    Best-effort: lỗi mạng thì bỏ qua, không được làm hỏng vòng chính."""
    try:
        sb().table("worker_heartbeat").upsert(
            {"name": name, "at": utc_now(), "note": note}).execute()
    except Exception:
        log.debug("heartbeat lỗi (bỏ qua): %s", name)


def runtime_settings() -> dict[str, str]:
    """Config chỉnh từ app (bảng worker_settings) — đọc mỗi chu kỳ discovery,
    đổi trong app là ăn ngay không cần restart. Lỗi/thiếu → {} (dùng default code)."""
    try:
        rows = sb().table("worker_settings").select("key, value").execute().data or []
        return {r["key"]: r["value"] for r in rows}
    except Exception:
        log.warning("Không đọc được worker_settings — dùng default trong config.py")
        return {}


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
            new = new.replace(w, c)
        if new != cv:
            if not t.get("wrong_vi"):
                t["wrong_vi"] = cv
            t["correct_vi"] = new
            changed.append(t)
    return changed


def get_glossary(novel_id: int) -> tuple[list[dict], int]:
    """Trả về (terms, version). Gồm term đã duyệt (truyện + global) VÀ term gợi ý
    (approved=false) của truyện.

    Gợi ý phải được dùng lại NGAY ở chương sau — trước đây chỉ lấy approved=true nên
    tên LLM tự phát hiện không bao giờ quay lại prompt, mỗi chương phiên âm một kiểu
    (bug "Lao Sen/Lâm Tùng"). Term duyệt tay thắng khi trùng term_zh; giữa các gợi ý,
    gợi ý CŨ nhất thắng (giữ cách phiên âm xuất hiện đầu tiên)."""
    terms = (
        sb().table("glossary_terms")
        .select("id,novel_id,term_zh,wrong_vi,correct_vi,term_type,note,narrator_term")
        .eq("approved", True)
        .or_(f"novel_id.eq.{novel_id},novel_id.is.null")
        .execute()
    ).data or []
    seen = {t["term_zh"] for t in terms if t.get("term_zh")}
    pending = (
        sb().table("glossary_terms")
        .select("id,novel_id,term_zh,wrong_vi,correct_vi,term_type,note,narrator_term")
        .eq("approved", False).eq("novel_id", novel_id)
        .order("created_at")
        .execute()
    ).data or []
    for t in pending:
        zh = t.get("term_zh")
        if zh and zh not in seen:
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
