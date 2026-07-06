"""Đồng bộ nguồn → DB: discovery truyện mới + cập nhật mục lục truyện đang theo dõi."""
from __future__ import annotations

import logging
import re
import time
import unicodedata

from .. import db
from ..config import settings
from .base import ChapterNotReady, SourceAdapter

log = logging.getLogger(__name__)


def _source_id(adapter: SourceAdapter) -> int:
    sid = adapter.source_row.get("id")
    if sid is not None:  # adapter dựng từ bảng sources → có sẵn, khỏi query lại
        return sid
    rows = db.sb().table("sources").select("id").eq("name", adapter.name).execute().data
    if not rows:
        raise RuntimeError(f"Nguồn '{adapter.name}' chưa có trong bảng sources")
    return rows[0]["id"]


def _existing_novels(sid: int, source_ids: list[str]) -> dict[str, int]:
    """Map source_novel_id → novels.id cho các id ĐÃ có trong DB (check theo lô,
    thay vì 1 query/ứng viên khi discovery quét hàng trăm slug)."""
    out: dict[str, int] = {}
    for i in range(0, len(source_ids), 200):
        rows = (
            db.sb().table("novels").select("id, source_novel_id")
            .eq("source_id", sid).in_("source_novel_id", source_ids[i:i + 200])
            .execute()
        ).data or []
        out.update({r["source_novel_id"]: r["id"] for r in rows})
    return out


# ---------- Chống trùng (dedup) giữa các nguồn ----------

def dedup_key(title_zh: str | None, author_zh: str | None) -> str:
    """Khoá trùng = chuẩn hoá title_zh+author_zh (bỏ khoảng trắng/dấu câu, NFKC).
    Cùng truyện trên shuhaige & ddxs → cùng key → chỉ 1 bản hiện ở Khám phá."""
    def norm(s: str | None) -> str:
        s = unicodedata.normalize("NFKC", s or "")
        s = re.sub(r"[\s\W_]+", "", s)   # \W giữ chữ Hán (là \w unicode), bỏ dấu câu/space
        return s.lower()
    return f"{norm(title_zh)}|{norm(author_zh)}"


def _pick_canonical(rows: list[dict], prio: dict[int, int]) -> dict:
    """Bản canonical = meta_priority nhỏ nhất; hoà thì nhiều chương hơn thắng."""
    return min(rows, key=lambda n: (prio.get(n["source_id"], 999),
                                    -(n.get("chapter_count_source") or 0)))


def recompute_canonical(key: str) -> None:
    """Sau mỗi upsert: chọn lại 1 bản canonical trong nhóm cùng dedup_key."""
    if not key or key == "|":
        return
    rows = (
        db.sb().table("novels").select("id, source_id, chapter_count_source, is_canonical")
        .eq("dedup_key", key).execute()
    ).data or []
    if not rows:
        return
    winner_id = _pick_canonical(rows, _source_priority())["id"] if len(rows) > 1 else rows[0]["id"]
    for n in rows:
        want = n["id"] == winner_id
        if n["is_canonical"] != want:  # chỉ update khi đổi → khỏi ghi thừa
            db.sb().table("novels").update({"is_canonical": want}).eq("id", n["id"]).execute()


def _source_priority() -> dict[int, int]:
    rows = db.sb().table("sources").select("id, meta_priority").execute().data or []
    return {r["id"]: r["meta_priority"] for r in rows}


def backfill_dedup_keys() -> int:
    """Gán dedup_key cho truyện cũ (thêm trước khi có Phase 2, key=NULL) rồi recompute
    canonical. Chạy 1 lần lúc crawler khởi động — tự lành, không cần thao tác tay."""
    rows = (
        db.sb().table("novels").select("id, title_zh, author_zh")
        .is_("dedup_key", "null").execute()
    ).data or []
    keys = set()
    for n in rows:
        k = dedup_key(n.get("title_zh"), n.get("author_zh"))
        db.sb().table("novels").update({"dedup_key": k}).eq("id", n["id"]).execute()
        keys.add(k)
    for k in keys:
        recompute_canonical(k)
    if rows:
        log.info("Backfill dedup_key cho %d truyện (%d nhóm)", len(rows), len(keys))
    return len(rows)


def reader_fetch_waiting() -> bool:
    """Có chương NGƯỜI ĐỌC chờ (job ưu tiên cao hơn nền) mà chưa tải nguồn → việc bảo trì
    (discovery/refresh, có thể cả tiếng) phải NHƯỜNG: dừng sớm, chu kỳ sau làm nốt.
    Không có guard này, vòng crawl 1 luồng để 'nguồn 0/1' treo suốt chu kỳ discovery."""
    jobs = (
        db.sb().table("translation_jobs").select("chapter_id")
        .eq("type", "chapter").eq("status", "pending")
        .lt("priority", settings.prio_idle)
        .not_.is_("chapter_id", "null")
        .limit(50).execute()
    ).data or []
    ids = [j["chapter_id"] for j in jobs]
    if not ids:
        return False
    n = (
        db.sb().table("chapters").select("id", count="exact")
        .in_("id", ids).is_("content_zh", "null").limit(1).execute()
    ).count or 0
    return n > 0


_STORAGE_COVERS_MARK = "/storage/v1/object/public/covers/"


def cache_cover(adapter: SourceAdapter, novel_id: int, external_url: str | None) -> str | None:
    """Tải bìa ngoài về Storage bucket 'covers' → trả public URL (khỏi phụ thuộc hotlink
    CDN nguồn). Idempotent: URL đã là storage của mình → trả lại. Lỗi/không có → None."""
    if not external_url or _STORAGE_COVERS_MARK in external_url:
        return external_url or None
    try:
        data, ctype = adapter.fetch_bytes(external_url)
    except Exception:
        log.warning("Không tải được bìa %s (novel %s)", external_url, novel_id)
        return None
    if not data or len(data) < 100:   # ảnh hỏng/trống → giữ hotlink cũ
        return None
    ext = "png" if "png" in ctype else "webp" if "webp" in ctype else "jpg"
    try:
        db.upload_cover(f"{novel_id}.{ext}", data, ctype)
        return db.cover_public_url(f"{novel_id}.{ext}")
    except Exception:
        log.exception("Upload bìa lỗi (novel %s)", novel_id)
        return None


def _cache_cover_and_update(adapter: SourceAdapter, novel_id: int, external_url: str | None) -> None:
    cached = cache_cover(adapter, novel_id, external_url)
    if cached and cached != external_url:
        db.sb().table("novels").update({"cover_url": cached}).eq("id", novel_id).execute()


def _queue_canonical_work(adapter: SourceAdapter, novel: dict, meta, prio_meta: int) -> None:
    """Sau upsert truyện mới: LỌC CHẤT LƯỢNG rồi mới đốt token.
    Sync mục lục trước → truyện đang-ra dưới `discover_min_chapters` chương = truyện mỏng
    chưa kiểm chứng → ẩn luôn, không dịch metadata/chương mẫu (hoàn thành thì không lọc).
    Truyện đạt → dịch metadata + `sample_chapters` chương đọc thử ưu tiên thấp."""
    if not (novel.get("is_canonical") and not novel.get("meta_translated")):
        return
    try:
        total = sync_chapter_list(adapter, novel["id"], meta.source_novel_id)
        if meta.status != "completed" and total < settings.discover_min_chapters:
            db.sb().table("novels").update({"hidden": True}).eq("id", novel["id"]).execute()
            log.info("Bỏ qua truyện mỏng %s (%s): %d chương < %d",
                     novel["id"], meta.title_zh, total, settings.discover_min_chapters)
            return
        db.enqueue("metadata", novel["id"], priority=prio_meta)
        queue_sample_chapters(novel["id"], settings.sample_chapters, settings.prio_idle)
    except Exception:
        log.exception("Discovery: lỗi xếp việc cho novel %s", novel["id"])


def discover_latest(adapter: SourceAdapter, max_new: int = 50) -> None:
    """Quét trang liệt kê nguồn → thêm tối đa `max_new` truyện MỚI mỗi chu kỳ.

    fetch_latest chỉ trả slug (nhẹ). Truyện MỚI → gọi fetch_novel_meta lấy đủ metadata
    → upsert + dedup → enqueue dịch metadata (chỉ bản canonical). Truyện đã có: bỏ qua.
    KHÔNG tải mục lục/chương (doc §3.5) — vẫn lazy khi user bấm Đọc.
    Trần max_new = cầu chì chống tràn Khám phá + đốt token dịch metadata (doc §6.4)."""
    sid = _source_id(adapter)
    added = 0
    cands = adapter.fetch_latest(limit=max_new * 4)  # quét dư vì nhiều truyện đã có
    known = _existing_novels(sid, [c.source_novel_id for c in cands])  # check theo lô
    for cand in cands:
        if added >= max_new:
            break
        if reader_fetch_waiting():
            log.info("Discovery %s: nhường chỗ tải chương người đọc (đã thêm %d)", adapter.name, added)
            break
        if cand.source_novel_id in known:
            continue
        try:
            meta = adapter.fetch_novel_meta(cand.source_novel_id)
        except Exception:
            log.exception("Discovery: lỗi lấy metadata %s (%s)", cand.source_novel_id, adapter.name)
            continue
        key = dedup_key(meta.title_zh, meta.author_zh)
        novel = db.upsert_novel({
            "source_id": sid,
            "source_novel_id": meta.source_novel_id,
            "source_url": meta.source_url,
            "title_zh": meta.title_zh,
            "author_zh": meta.author_zh,
            "cover_url": meta.cover_url,
            "description_zh": meta.description_zh,
            "genres": meta.genres_zh,      # tiếng Trung, job metadata sẽ dịch
            "status": meta.status,
            "dedup_key": key,
            "last_chapter_at": meta.last_chapter_at.isoformat() if meta.last_chapter_at else None,
            "updated_at": db.utc_now(),
        })
        recompute_canonical(key)
        _cache_cover_and_update(adapter, novel["id"], meta.cover_url)
        # chỉ bản canonical + qua lọc chất lượng mới tốn token (metadata + chương mẫu)
        _queue_canonical_work(adapter, novel, meta, prio_meta=10)
        added += 1
        time.sleep(1.0)  # lịch sự với nguồn
    if added:
        log.info("Discovery %s: thêm %d truyện mới", adapter.name, added)


def discover_ranking(adapter: SourceAdapter, max_new: int = 30) -> None:
    """Discovery theo BẢNG XẾP HẠNG nguồn (truyện hot) — ưu tiên hơn discovery thường.
    Lưu `source_rank` (để "Đề cử" xếp theo độ hot) + dịch metadata/chương mẫu như discover_latest.
    Truyện đã có → chỉ cập nhật lại rank. Adapter không có fetch_ranking (ddxs) → bỏ qua."""
    fetch = getattr(adapter, "fetch_ranking", None)
    if not fetch:
        return
    sid = _source_id(adapter)
    added = 0
    # Quét HẾT bảng xếp hạng mỗi chu kỳ: rank mọi truyện đã có được cập nhật (top
    # không cố định), truyện chưa có thì thêm dần max_new/chu kỳ tới khi vét cạn top.
    ranked = list(fetch(limit=1000))
    known = _existing_novels(sid, [r[0] for r in ranked])  # check theo lô
    for source_novel_id, rank in ranked:
        if source_novel_id in known:
            db.sb().table("novels").update({"source_rank": rank}).eq("id", known[source_novel_id]).execute()
            continue
        if added >= max_new:
            continue  # hết quota thêm mới nhưng vẫn quét nốt để cập nhật rank truyện đã có
        if reader_fetch_waiting():
            log.info("Ranking %s: nhường chỗ tải chương người đọc (đã thêm %d)", adapter.name, added)
            break
        try:
            meta = adapter.fetch_novel_meta(source_novel_id)
        except Exception:
            log.exception("Ranking: lỗi metadata %s (%s)", source_novel_id, adapter.name)
            continue
        key = dedup_key(meta.title_zh, meta.author_zh)
        novel = db.upsert_novel({
            "source_id": sid,
            "source_novel_id": meta.source_novel_id,
            "source_url": meta.source_url,
            "title_zh": meta.title_zh,
            "author_zh": meta.author_zh,
            "cover_url": meta.cover_url,
            "description_zh": meta.description_zh,
            "genres": meta.genres_zh,
            "status": meta.status,
            "dedup_key": key,
            "source_rank": rank,
            "last_chapter_at": meta.last_chapter_at.isoformat() if meta.last_chapter_at else None,
            "updated_at": db.utc_now(),
        })
        recompute_canonical(key)
        _cache_cover_and_update(adapter, novel["id"], meta.cover_url)
        # truyện hoàn thành ưu tiên hơn (metadata prio nhỏ hơn) — user muốn ưu tiên hoàn thành
        _queue_canonical_work(adapter, novel, meta,
                              prio_meta=8 if meta.status == "completed" else 10)
        added += 1
        time.sleep(1.0)
    if added:
        log.info("Ranking %s: thêm %d truyện hot", adapter.name, added)


def add_novel(adapter: SourceAdapter, source_novel_id: str) -> dict:
    """Thêm 1 truyện theo book_id (luồng chính: nguồn không có discovery tự động)."""
    meta = adapter.fetch_novel_meta(source_novel_id)
    key = dedup_key(meta.title_zh, meta.author_zh)
    novel = db.upsert_novel({
        "source_id": _source_id(adapter),
        "source_novel_id": meta.source_novel_id,
        "source_url": meta.source_url,
        "title_zh": meta.title_zh,
        "author_zh": meta.author_zh,
        "cover_url": meta.cover_url,
        "description_zh": meta.description_zh,
        "genres": meta.genres_zh,
        "status": meta.status,
        "dedup_key": key,
        "last_chapter_at": meta.last_chapter_at.isoformat() if meta.last_chapter_at else None,
        "updated_at": db.utc_now(),
    })
    recompute_canonical(key)
    _cache_cover_and_update(adapter, novel["id"], meta.cover_url)
    sync_chapter_list(adapter, novel["id"], source_novel_id)
    if not novel.get("meta_translated"):
        db.enqueue("metadata", novel["id"], priority=10)
    queue_sample_chapters(novel["id"], settings.sample_chapters, settings.prio_idle)
    return novel


def queue_sample_chapters(novel_id: int, count: int, priority: int) -> int:
    """Dịch sẵn `count` chương đầu để user 'đọc thử' — ưu tiên thấp (chỉ chạy khi rảnh).
    Cần mục lục đã sync trước. Trả số chương vừa xếp."""
    if count <= 0:
        return 0
    rows = (
        db.sb().table("chapters").select("id, chapter_index")
        .eq("novel_id", novel_id).lte("chapter_index", count)
        .in_("translation_status", ["none", "failed"])
        .order("chapter_index").execute()
    ).data or []
    if not rows:
        return 0
    db.sb().table("chapters").update({"translation_status": "queued"}).in_(
        "id", [r["id"] for r in rows]).execute()
    for r in rows:
        db.enqueue("chapter", novel_id, chapter_id=r["id"], priority=priority)
    return len(rows)


def sync_chapter_list(adapter: SourceAdapter, novel_id: int, source_novel_id: str) -> int:
    """Cập nhật mục lục 1 truyện; trả về số chương mới phát hiện.

    Chỉ upsert phần CHƯA có: trường hợp thường gặp nhất khi soi định kỳ là "không
    đổi gì" → 1 query count là xong, khỏi kéo 4000 index + re-upsert 4000 stub.
    ponytail: chương đã có KHÔNG được refresh title/source_chapter_id — nguồn đánh
    lại số chương (cực hiếm) thì xoá chapters của truyện đó rồi để sync tự lấp."""
    refs = adapter.fetch_chapter_list(source_novel_id)
    existing_count = (
        db.sb().table("chapters").select("id", count="exact")
        .eq("novel_id", novel_id).limit(1).execute()
    ).count or 0
    if existing_count >= len(refs):
        return 0
    # kéo index đã có THEO TRANG — PostgREST trần 1000 dòng/query; kéo 1 lần với
    # truyện 4000 chương → have thiếu → tưởng nhầm +3000 chương mới, bump nhiễu.
    have: set[int] = set()
    frm = 0
    while True:
        b = (
            db.sb().table("chapters").select("chapter_index")
            .eq("novel_id", novel_id).range(frm, frm + 999).execute()
        ).data or []
        have.update(r["chapter_index"] for r in b)
        if len(b) < 1000:
            break
        frm += 1000
    new_refs = [ref for ref in refs if ref.index not in have]
    if not new_refs:
        return 0
    db.upsert_chapter_stubs([
        {
            "novel_id": novel_id,
            "chapter_index": ref.index,
            "source_chapter_id": ref.source_chapter_id,
            "title_zh": ref.title_zh,
        }
        for ref in new_refs
    ])
    # CHỈ bump khi thật có chương mới → "Mới cập nhật" phản ánh đúng, không nhiễu.
    now = db.utc_now()
    db.sb().table("novels").update(
        {"chapter_count_source": len(refs), "last_chapter_at": now, "updated_at": now}
    ).eq("id", novel_id).execute()
    return len(new_refs)


def sync_followed_novels(adapter: SourceAdapter) -> None:
    """Với truyện có trong ít nhất 1 tủ sách: kiểm tra chương mới."""
    sid = _source_id(adapter)
    rows = (
        db.sb().table("library").select("novel_id, novels!inner(id, source_id, source_novel_id)")
        .eq("novels.source_id", sid)
        .execute()
    ).data or []
    seen: set[int] = set()
    for row in rows:
        nv = row["novels"]
        if nv["id"] in seen:
            continue
        if reader_fetch_waiting():
            log.info("Sync tủ sách %s: nhường chỗ tải chương người đọc", adapter.name)
            break
        seen.add(nv["id"])
        try:
            n = sync_chapter_list(adapter, nv["id"], nv["source_novel_id"])
            if n:
                log.info("Truyện %s có %d chương mới", nv["id"], n)
        except Exception:
            log.exception("Lỗi sync truyện %s", nv["id"])
        time.sleep(2.0)


def refresh_canonical_updates(adapter: SourceAdapter, limit: int) -> None:
    """Theo dõi chương mới cho truyện CANONICAL của nguồn (không chỉ tủ sách) → truyện
    ra chương mới nổi lên 'Mới cập nhật', không chỉ truyện mới toanh.

    Soi MỤC LỤC (danh sách chương stub, KHÔNG tải nội dung — nội dung vẫn lazy). Nguồn
    nhóm này không cho tín hiệu update rẻ (ddxs không có update_time, shuhaige trang
    truyện = cả mục lục) nên đành fetch 1 trang/truyện.
    ponytail: trần `limit` truyện/chu kỳ, xoay vòng theo last_checked_at (NULL/cũ nhất
    trước) → mọi truyện được soi dần mà không nặng nhất thời. Truyện phình quá thì giãn
    chu kỳ / tăng limit."""
    sid = _source_id(adapter)
    rows = (
        db.sb().table("novels").select("id, source_novel_id, hidden, meta_translated, status")
        .eq("source_id", sid).eq("is_canonical", True)
        .order("last_checked_at", desc=False, nullsfirst=True)  # chưa soi/lâu nhất trước
        .limit(limit).execute()
    ).data or []
    for i, nv in enumerate(rows):
        if reader_fetch_waiting():
            log.info("Refresh %s: nhường chỗ tải chương người đọc (đã soi %d/%d)",
                     adapter.name, i, len(rows))
            break
        db.heartbeat("crawler", note=f"soi mục lục novel {nv['id']} ({i + 1}/{len(rows)})")
        try:
            n = sync_chapter_list(adapter, nv["id"], nv["source_novel_id"])
            if n:
                log.info("Truyện %s +%d chương mới", nv["id"], n)
                _maybe_unhide_grown(nv)
        except Exception:
            log.exception("Lỗi refresh truyện %s", nv["id"])
        # đánh dấu đã soi (kể cả khi không có chương mới) → xoay vòng đúng
        db.sb().table("novels").update({"last_checked_at": db.utc_now()}).eq("id", nv["id"]).execute()
        time.sleep(2.0)


def _maybe_unhide_grown(nv: dict) -> None:
    """Truyện bị ẩn vì MỎNG (lọc discovery) mà giờ đã đủ chương → tự hiện lại + dịch
    metadata/chương mẫu. Chỉ đụng truyện `meta_translated=false` — truyện admin ẩn TAY
    đều đã dịch tên từ trước, không bị auto bật lại."""
    if not nv.get("hidden") or nv.get("meta_translated"):
        return
    row = (
        db.sb().table("novels").select("chapter_count_source, status")
        .eq("id", nv["id"]).single().execute()
    ).data or {}
    count = row.get("chapter_count_source") or 0
    if row.get("status") != "completed" and count < settings.discover_min_chapters:
        return
    db.sb().table("novels").update({"hidden": False}).eq("id", nv["id"]).execute()
    db.enqueue("metadata", nv["id"], priority=10)
    queue_sample_chapters(nv["id"], settings.sample_chapters, settings.prio_idle)
    log.info("Truyện %s đủ %d chương — tự hiện lại + dịch metadata", nv["id"], count)


# Đếm số lần liên tiếp một chương "chưa sẵn trên nguồn" (in-memory, reset khi worker
# restart — chấp nhận: restart chỉ kéo dài thêm vài vòng thử).
_not_ready_count: dict[int, int] = {}
NOT_READY_GIVE_UP = 10


def ensure_chapters_fetched(adapter: SourceAdapter, novel_id: int) -> None:
    """Tải content_zh cho các chương đã queued dịch mà chưa có nội dung gốc."""
    rows = (
        db.sb().table("chapters")
        .select("id, source_chapter_id, chapter_index")
        .eq("novel_id", novel_id)
        .eq("translation_status", "queued")
        .is_("content_zh", "null")
        .order("chapter_index")
        .execute()
    ).data or []
    for i, ch in enumerate(rows):
        if not ch["source_chapter_id"]:
            continue
        db.heartbeat("crawler",
                     note=f"tải chương {ch['chapter_index']} novel {novel_id} ({i + 1}/{len(rows)})")
        try:
            content = adapter.fetch_chapter(ch["source_chapter_id"])
            db.save_chapter_raw(ch["id"], content)
            _not_ready_count.pop(ch["id"], None)
            log.info("Đã tải chương %s (novel %s)", ch["chapter_index"], novel_id)
        except ChapterNotReady as e:
            # Lỗi TẠM: nguồn liệt kê chương nhưng trang chưa sinh → giữ queued thử lại.
            # Nhưng quá NOT_READY_GIVE_UP lần liên tiếp = truyện bị GỠ khỏi nguồn (404
            # cả trang truyện) → đánh failed kèm lý do, thôi lặp nóng mỗi vòng crawl.
            n = _not_ready_count[ch["id"]] = _not_ready_count.get(ch["id"], 0) + 1
            if n >= NOT_READY_GIVE_UP:
                _not_ready_count.pop(ch["id"], None)
                db.sb().table("chapters").update(
                    {"translation_status": "failed"}).eq("id", ch["id"]).execute()
                db.sb().table("translation_jobs").update(
                    {"status": "failed",
                     "error": f"crawl: trang chương không tồn tại sau {n} lần thử "
                              f"— truyện có thể đã bị gỡ khỏi nguồn ({e})"[:500]}
                ).eq("chapter_id", ch["id"]).eq("status", "pending").execute()
                log.warning("Chương %s không sẵn sau %d lần — đánh failed", ch["id"], n)
            else:
                log.info("Chương %s chưa sẵn trên nguồn (lần %d) — thử lại vòng sau", ch["id"], n)
        except Exception as e:
            # Lỗi tải (đổi cấu trúc/mạng): đánh dấu failed để thôi retry mỗi vòng crawl.
            db.sb().table("chapters").update(
                {"translation_status": "failed"}).eq("id", ch["id"]).execute()
            # Job dịch kèm chương cũng phải failed — để pending là job "kẹt" mãi:
            # translator không claim (thiếu content_zh), admin retry lại chỉ reset job failed.
            db.sb().table("translation_jobs").update(
                {"status": "failed", "error": f"crawl: {e}"[:500]}
            ).eq("chapter_id", ch["id"]).eq("status", "pending").execute()
            log.exception("Lỗi tải chương %s → failed", ch["id"])
        time.sleep(1.5)
