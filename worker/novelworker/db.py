"""Supabase client (service role) + các thao tác DB dùng chung."""
from __future__ import annotations

import logging
from functools import lru_cache
from typing import Any

from supabase import Client, create_client

from .config import settings

log = logging.getLogger(__name__)


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


def upsert_chapter_stub(novel_id: int, index: int, source_chapter_id: str | None, title_zh: str | None) -> None:
    sb().table("chapters").upsert(
        {
            "novel_id": novel_id,
            "chapter_index": index,
            "source_chapter_id": source_chapter_id,
            "title_zh": title_zh,
        },
        on_conflict="novel_id,chapter_index",
        ignore_duplicates=True,   # không ghi đè chương đã có nội dung/bản dịch
    ).execute()


def save_chapter_raw(chapter_id: int, content_zh: str) -> None:
    sb().table("chapters").update({"content_zh": content_zh}).eq("id", chapter_id).execute()


def save_chapter_translation(
    chapter_id: int, title_vi: str | None, content_vi: str,
    model: str, prompt_tokens: int, completion_tokens: int, glossary_version: int,
) -> None:
    sb().table("chapters").update(
        {
            "title_vi": title_vi,
            "content_vi": content_vi,
            "translation_status": "done",
            "translated_at": "now()",
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


def finish_job(job_id: int, ok: bool, error: str | None = None) -> None:
    if ok:
        sb().table("translation_jobs").update(
            {"status": "done", "done_at": "now()", "error": None}
        ).eq("id", job_id).execute()
        return
    # thất bại: còn lượt thì trả về pending để retry, hết lượt thì failed
    job = sb().table("translation_jobs").select("attempts,max_attempts,chapter_id").eq("id", job_id).single().execute().data
    status = "pending" if job["attempts"] < job["max_attempts"] else "failed"
    sb().table("translation_jobs").update({"status": status, "error": (error or "")[:2000]}).eq("id", job_id).execute()
    if status == "failed" and job.get("chapter_id"):
        sb().table("chapters").update({"translation_status": "failed"}).eq("id", job["chapter_id"]).execute()


def enqueue(type_: str, novel_id: int, chapter_id: int | None = None, priority: int = 100) -> None:
    try:
        sb().table("translation_jobs").insert(
            {"type": type_, "novel_id": novel_id, "chapter_id": chapter_id, "priority": priority}
        ).execute()
    except Exception as e:  # unique index chặn job trùng → bỏ qua
        if "duplicate" not in str(e).lower() and "unique" not in str(e).lower():
            raise
        log.debug("job trùng, bỏ qua: %s novel=%s ch=%s", type_, novel_id, chapter_id)


# ---------- glossary ----------

def get_glossary(novel_id: int) -> tuple[list[dict], int]:
    """Trả về (terms, version). Gồm term của truyện + term global đã duyệt."""
    terms = (
        sb().table("glossary_terms")
        .select("term_zh,wrong_vi,correct_vi,term_type")
        .eq("approved", True)
        .or_(f"novel_id.eq.{novel_id},novel_id.is.null")
        .execute()
    ).data or []
    ver_rows = (
        sb().table("novel_glossary_version").select("version").eq("novel_id", novel_id).execute()
    ).data
    version = ver_rows[0]["version"] if ver_rows else 0
    return terms, version
