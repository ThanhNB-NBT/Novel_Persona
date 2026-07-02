"""Consumer hàng đợi dịch: metadata / chapter / comment_batch."""
from __future__ import annotations

import json
import logging
import re
import time

from .. import db
from ..config import settings
from . import prompts
from .providers import get_provider

log = logging.getLogger(__name__)

GLOSSARY_LINE = re.compile(r"GLOSSARY_JSON:\s*(\[.*\])\s*$", re.S)


def _extract_json(text: str) -> dict | list:
    """LLM đôi khi bọc JSON trong ```json ...``` — bóc ra."""
    m = re.search(r"```(?:json)?\s*(.+?)\s*```", text, re.S)
    return json.loads(m.group(1) if m else text.strip())


# ---------- xử lý từng loại job ----------

def handle_metadata(job: dict) -> None:
    novel = db.sb().table("novels").select("*").eq("id", job["novel_id"]).single().execute().data
    llm = get_provider()
    res = llm.complete(prompts.SYSTEM_METADATA, prompts.build_metadata_user(novel), max_tokens=2048)
    data = _extract_json(res.text)
    db.sb().table("novels").update({
        "title_vi": data.get("title_vi"),
        "author_vi": data.get("author_vi"),
        "description_vi": data.get("description_vi"),
        "genres": data.get("genres_vi") or novel.get("genres"),
        "meta_translated": True,
        "updated_at": "now()",
    }).eq("id", novel["id"]).execute()
    log.info("Đã dịch metadata truyện %s: %s", novel["id"], data.get("title_vi"))


def handle_chapter(job: dict) -> None:
    ch = db.sb().table("chapters").select("*").eq("id", job["chapter_id"]).single().execute().data
    if not ch.get("content_zh"):
        raise RuntimeError(f"Chương {ch['id']} chưa có content_zh — crawler chưa tải xong, retry sau")

    db.sb().table("chapters").update({"translation_status": "translating"}).eq("id", ch["id"]).execute()

    terms, glossary_version = db.get_glossary(ch["novel_id"])
    llm = get_provider()
    res = llm.complete(
        prompts.build_chapter_system(terms),
        prompts.build_chapter_user(ch.get("title_zh"), ch["content_zh"]),
    )

    text = res.text
    # bóc bảng tên riêng LLM phát hiện (phục vụ glossary suggest trong app)
    detected: list[dict] = []
    m = GLOSSARY_LINE.search(text)
    if m:
        text = text[: m.start()].rstrip()
        try:
            detected = json.loads(m.group(1))
        except json.JSONDecodeError:
            pass

    # dịch tiêu đề: dòng đầu nếu LLM có kèm, không thì dịch nhanh riêng — đơn giản: lấy title từ text nếu match
    title_vi = None
    if ch.get("title_zh"):
        first, _, rest = text.partition("\n")
        if len(first) < 100 and rest:
            title_vi, text = first.strip(), rest.strip()

    db.save_chapter_translation(
        ch["id"], title_vi, text, res.model, res.prompt_tokens, res.completion_tokens, glossary_version
    )
    db.bump_translated_count(ch["novel_id"])

    # lưu tên riêng phát hiện được làm term "gợi ý" (approved=false, scope=novel)
    for t in detected:
        if t.get("zh") and t.get("vi"):
            try:
                db.sb().table("glossary_terms").insert({
                    "novel_id": ch["novel_id"], "term_zh": t["zh"], "correct_vi": t["vi"],
                    "term_type": t.get("type", "other") if t.get("type") in
                        ("person", "place", "sect", "item", "skill") else "other",
                    "scope": "novel", "approved": False,
                }).execute()
            except Exception:
                pass  # trùng thì thôi

    log.info("Đã dịch chương %s/%s (novel %s)", ch["chapter_index"], ch["novel_id"], res.model)


def handle_comment_batch(job: dict) -> None:
    comments = (
        db.sb().table("comments").select("id, content_zh")
        .eq("novel_id", job["novel_id"]).eq("translation_status", "none")
        .order("likes", desc=True).limit(50).execute()
    ).data or []
    if not comments:
        return
    llm = get_provider()
    res = llm.complete(prompts.SYSTEM_COMMENTS, prompts.build_comments_user(comments), max_tokens=8192)
    data = _extract_json(res.text)
    for item in data.get("translations", []):
        db.sb().table("comments").update(
            {"content_vi": item["vi"], "translation_status": "done"}
        ).eq("id", int(item["id"])).execute()
    log.info("Đã dịch %d bình luận truyện %s", len(comments), job["novel_id"])


HANDLERS = {
    "metadata": handle_metadata,
    "chapter": handle_chapter,
    "comment_batch": handle_comment_batch,
}


def run_forever(poll_seconds: float = 3.0) -> None:
    log.info("Translator worker '%s' bắt đầu (provider=%s)", settings.worker_id, settings.llm_provider)
    while True:
        job = db.claim_next_job(settings.worker_id)
        if not job:
            time.sleep(poll_seconds)
            continue
        log.info("Nhận job #%s type=%s novel=%s", job["id"], job["type"], job["novel_id"])
        try:
            HANDLERS[job["type"]](job)
            db.finish_job(job["id"], ok=True)
        except Exception as e:
            log.exception("Job #%s lỗi", job["id"])
            db.finish_job(job["id"], ok=False, error=str(e))
