"""Đồng bộ nguồn → DB: discovery truyện mới + cập nhật mục lục truyện đang theo dõi."""
from __future__ import annotations

import logging
import re
import time
import unicodedata
from datetime import datetime, timedelta, timezone

from .. import db
from ..config import settings
from .base import ChapterNotReady, SourceAdapter, SourceBlocked

log = logging.getLogger(__name__)


def _chapter_sync_fields(
    old_count: int, old_status: str | None, source_status: str | None,
    total: int, full_toc: bool, now: str,
) -> dict:
    fields: dict = {}
    if source_status and source_status != old_status:
        fields["status"] = source_status
    if total > old_count:
        fields.update({
            "chapter_count_source": total,
            "last_chapter_at": now,
            "updated_at": now,
        })
    if full_toc and total > 0:
        fields["toc_synced_at"] = now
    return fields


def _source_id(adapter: SourceAdapter) -> int:
    sid = adapter.source_row.get("id")
    if sid is not None:  # adapter dựng từ bảng sources → có sẵn, khỏi query lại
        return sid
    rows = db.sb().table("sources").select("id").eq("name", adapter.name).execute().data
    if not rows:
        raise RuntimeError(f"Nguồn '{adapter.name}' chưa có trong bảng sources")
    return rows[0]["id"]


def _existing_novels(sid: int, source_ids: list[str]) -> dict[str, dict]:
    """Map source_novel_id → {id, source_rank} cho các id ĐÃ có trong DB (check theo lô,
    thay vì 1 query/ứng viên khi discovery quét hàng trăm slug). Kèm source_rank để
    discover_ranking bỏ qua UPDATE khi rank không đổi."""
    out: dict[str, dict] = {}
    for i in range(0, len(source_ids), 200):
        rows = (
            db.sb().table("novels").select("id, source_novel_id, source_rank")
            .eq("source_id", sid).in_("source_novel_id", source_ids[i:i + 200])
            .execute()
        ).data or []
        out.update({r["source_novel_id"]: r for r in rows})
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


def _blacklist(sid: int) -> tuple[set[str], set[str]]:
    """Truyện admin đã xoá vĩnh viễn (trigger ghi vào crawl_blacklist, migration 032)
    → discovery bỏ qua. Trả (source_novel_ids của nguồn này, dedup_keys mọi nguồn —
    chặn cả bản clone của truyện đã xoá trồi lên từ nguồn khác)."""
    rows = (
        db.sb().table("crawl_blacklist")
        .select("source_id, source_novel_id, dedup_key").execute()
    ).data or []
    ids = {r["source_novel_id"] for r in rows
           if r["source_id"] == sid and r.get("source_novel_id")}
    keys = {r["dedup_key"] for r in rows if r.get("dedup_key")}
    return ids, keys


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


# Lọc thể loại lúc discovery: ưu tiên fantasy/tu tiên; romance được giữ nếu đi
# cùng thể loại mạnh, chỉ chặn romance/đô thị/lịch sử thuần.
# Nguồn có thể thiếu category (ddxs), nên title + mô tả cũng tham gia lọc.
_BLOCKED_CATS = (
    "都市", "历史", "言情", "现言", "古言", "现代言情", "都市言情", "爱情", "恋爱", "婚恋",
    "đô thị", "lịch sử", "ngôn tình", "hiện đại", "tình cảm",
)
_STRONG_ALLOWED = (
    "玄幻", "修仙", "修真", "仙侠", "武侠", "灵异", "悬疑", "诡异", "恐怖", "惊悚",
    "末世", "末日", "天灾", "科幻", "无限流", "网游", "游戏异界", "诸天", "御兽",
    "高武", "废土", "huyền huyễn", "tu tiên", "tiên hiệp", "võ hiệp", "linh dị",
    "võng du", "tận thế", "khoa huyễn", "vô hạn lưu", "chư thiên", "ngự thú",
)
_BLOCKED_TEXT = (
    "都市", "现代都市", "都市生活", "历史", "言情", "现言", "古言", "总裁", "霸总",
    "校花", "娱乐圈", "明星", "豪门", "甜宠", "宠妻", "虐恋",
    "年代文", "知青", "四合院", "官场", "抗战", "娇妻", "sủng", "tổng tài",
    "hào môn", "giới giải trí", "quân hôn", "đô thị", "lịch sử", "ngôn tình",
)
# ponytail: cache RAM để mỗi chu kỳ ranking khỏi fetch lại metadata truyện đã chặn;
# worker restart thì fetch lại 1 lần — chấp nhận được
_genre_skipped: set[tuple[int, str]] = set()


def genre_blocked(meta) -> str | None:
    """Trả lý do chặn; không dùng từ yếu như 系统 để miễn cho đô thị."""
    def get(name: str, fallback):
        return getattr(meta, name, meta.get(name, fallback) if isinstance(meta, dict) else fallback)

    cats = " ".join(get("genres_zh", get("genres", [])) or []).lower()
    title = " ".join(filter(None, [get("title_zh", ""), get("title_vi", "")])).lower()
    desc = (get("description_zh", "") or "").split("小说推荐")[0].lower()
    text = f"{cats} {title} {desc}"
    hit = next((b for b in _BLOCKED_CATS if b in cats), None)
    strong = any(k.lower() in text for k in _STRONG_ALLOWED)
    if hit:
        # Ngôn tình/tình cảm vẫn hợp lệ nếu đi cùng fantasy mạnh (玄幻/修仙/灵异…);
        # chỉ chặn khi nó đứng một mình hoặc chỉ pha tag yếu như 系统.
        return None if strong else hit
    text_hit = next((k for k in _BLOCKED_TEXT if k.lower() in text), None)
    return text_hit if text_hit and not strong else None


def _skip_by_genre(sid: int, meta) -> bool:
    hit = genre_blocked(meta)
    if hit:
        _genre_skipped.add((sid, meta.source_novel_id))
        log.info("Discovery: bỏ qua %s — thể loại hạn chế '%s'", meta.title_zh, hit)
        return True
    return False


def _skip_by_source_policy(adapter: SourceAdapter, meta) -> bool:
    """Lọc điều kiện riêng của nguồn trước khi tạo novel trong DB."""
    if adapter.name != "faloo":
        return False
    threshold = settings.faloo_free_chapter_threshold
    if meta.chapter_count > threshold:
        return False
    log.info("Discovery: bỏ qua %s — Faloo chỉ có %d chương free (cần > %d)",
             meta.title_zh, meta.chapter_count, threshold)
    return True


def _queue_canonical_work(adapter: SourceAdapter, novel: dict, meta, prio_meta: int) -> bool:
    """Sau upsert truyện mới: LỌC CHẤT LƯỢNG rồi mới đốt token.
    Sync mục lục trước → truyện đang-ra dưới `discover_min_chapters` chương = truyện mỏng
    chưa kiểm chứng → ẩn luôn, không dịch metadata/chương mẫu (hoàn thành thì không lọc).
    Truyện đạt → dịch metadata + `sample_chapters` chương đọc thử ưu tiên thấp."""
    if not (novel.get("is_canonical") and not novel.get("meta_translated")):
        return False
    try:
        # mục lục lười: truyện mới chỉ giữ stub cho chương mẫu; user mở truyện thì
        # request_toc mới tải đủ (đỡ ~1.7k dòng stub/truyện không ai đọc)
        total, _ = sync_chapter_list(adapter, novel["id"], meta.source_novel_id,
                                     limit_stubs=settings.sample_chapters)
        source_status = getattr(adapter, "last_toc_status", None)
        if (source_status or meta.status) != "completed" and total < settings.discover_min_chapters:
            db.sb().table("novels").update({"hidden": True}).eq("id", novel["id"]).execute()
            log.info("Bỏ qua truyện mỏng %s (%s): %d chương < %d",
                     novel["id"], meta.title_zh, total, settings.discover_min_chapters)
            return False
        db.enqueue("metadata", novel["id"], priority=prio_meta)
        queue_sample_chapters(novel["id"], settings.sample_chapters, settings.prio_idle)
        return True
    except Exception:
        log.exception("Discovery: lỗi xếp việc cho novel %s", novel["id"])
        return False


def _frontier_step(cycle_count: int, next_page: int) -> tuple[int, int, bool]:
    """Cứ 2 chu kỳ chen trang 1; chu kỳ còn lại tiếp tục đúng cursor sâu."""
    cycle_count += 1
    hot_page = cycle_count % 2 == 0
    return cycle_count, 1 if hot_page else max(1, next_page), hot_page


def _candidate_priority(pool: str) -> int:
    return {"completed": 10, "recommended": 20, "top": 20, "latest": 30}.get(pool, 50)


def discover_pool(adapter: SourceAdapter, method: str, label: str) -> None:
    """Quét đúng một tầng của pool, lưu cursor + ứng viên; không enrich tại đây."""
    fetch = getattr(adapter, method, None)
    if not fetch:
        return
    sid = _source_id(adapter)
    pool = method.removeprefix("fetch_")
    state_rows = (
        db.sb().table("crawl_discovery_frontier")
        .select("next_page, cycle_count").eq("source_id", sid).eq("pool", pool)
        .limit(1).execute().data or []
    )
    state = state_rows[0] if state_rows else {}
    cycle, page, hot_page = _frontier_step(
        state.get("cycle_count") or 0, state.get("next_page") or 1)
    candidates = fetch(limit=200, page=page)
    next_page = state.get("next_page") or 1
    wrapped_at = None
    if not hot_page:
        next_page = page + 1 if candidates else 1
        if not candidates and page > 1:
            wrapped_at = db.utc_now()
    frontier = {
        "source_id": sid, "pool": pool, "next_page": next_page,
        "cycle_count": cycle, "updated_at": db.utc_now(),
    }
    if wrapped_at:
        frontier["wrapped_at"] = wrapped_at
    db.sb().table("crawl_discovery_frontier").upsert(
        frontier, on_conflict="source_id,pool").execute()

    if candidates:
        rows = [{
            "source_id": sid,
            "source_novel_id": item.source_novel_id,
            "pool": pool,
            "title_zh": item.title_zh,
            "status_hint": item.status,
            "discovered_page": page,
            "priority": _candidate_priority(pool),
        } for item in candidates]
        db.sb().table("crawl_candidates").upsert(
            rows, on_conflict="source_id,pool,source_novel_id",
            ignore_duplicates=True).execute()
    log.info("Frontier %s/%s: %s trang %d → %d ứng viên; cursor sâu=%d",
             adapter.name, label, "quét nóng" if hot_page else "đào sâu",
             page, len(candidates), next_page)


def _candidate_batch(sid: int, limit: int) -> list[dict]:
    table = db.sb().table("crawl_candidates")
    rows = (
        table.select("*").eq("source_id", sid).eq("status", "pending")
        .order("priority").order("created_at").limit(limit).execute().data or []
    )
    if len(rows) < limit:
        due = (
            db.sb().table("crawl_candidates").select("*").eq("source_id", sid)
            .in_("status", ["too_short", "failed"]).lte("retry_after", db.utc_now())
            .order("priority").order("retry_after").limit(limit - len(rows))
            .execute().data or []
        )
        rows.extend(due)
    return rows


def _mark_candidate(row_id: int, status: str, **fields) -> None:
    fields.update({"status": status, "updated_at": db.utc_now()})
    db.sb().table("crawl_candidates").update(fields).eq("id", row_id).execute()


def process_discovery_candidates(adapter: SourceAdapter, max_new: int = 10) -> None:
    """Rút hàng đợi bền vững; tối đa 2× quota lần kiểm tra để không hammer nguồn."""
    sid = _source_id(adapter)
    rows = _candidate_batch(sid, max_new * 2)
    if not rows:
        return
    known = _existing_novels(sid, [r["source_novel_id"] for r in rows])
    bl_ids, bl_keys = _blacklist(sid)
    added = checked = 0
    consec_fail = 0
    for row in rows:
        if added >= max_new:
            break
        source_novel_id = row["source_novel_id"]
        if source_novel_id in known:
            _mark_candidate(row["id"], "done")
            continue
        if source_novel_id in bl_ids or (sid, source_novel_id) in _genre_skipped:
            _mark_candidate(row["id"], "rejected")
            continue
        checked += 1
        try:
            meta = adapter.fetch_novel_meta(source_novel_id)
        except SourceBlocked as exc:
            # Chặn theo IP là lỗi của CHU KỲ, không phải của truyện: giữ candidate
            # pending nguyên trạng, dừng ngay để không nuôi mức chặn.
            log.warning("Discovery queue %s: %s — dừng chu kỳ này", adapter.name, exc)
            break
        except Exception as exc:
            consec_fail += 1
            retry = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
            _mark_candidate(row["id"], "failed", attempts=(row.get("attempts") or 0) + 1,
                            retry_after=retry, last_error=str(exc)[:500])
            log.warning("Discovery queue %s: lỗi %s — %s", adapter.name, source_novel_id, exc)
            if consec_fail >= 8:
                log.warning("Discovery queue %s: 8 lỗi liên tiếp, dừng để tránh bị chặn",
                            adapter.name)
                break
            time.sleep(1.0)
            continue
        consec_fail = 0
        if row.get("status_hint") == "completed":
            meta.status = "completed"
        if _skip_by_source_policy(adapter, meta):
            retry = (datetime.now(timezone.utc) + timedelta(days=7)).isoformat()
            _mark_candidate(row["id"], "too_short", attempts=(row.get("attempts") or 0) + 1,
                            free_chapter_count=meta.chapter_count, retry_after=retry,
                            last_error=None)
            continue
        if _skip_by_genre(sid, meta):
            _mark_candidate(row["id"], "rejected")
            continue
        key = dedup_key(meta.title_zh, meta.author_zh)
        if key in bl_keys:
            _mark_candidate(row["id"], "rejected")
            continue
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
            "last_chapter_at": meta.last_chapter_at.isoformat() if meta.last_chapter_at else None,
            "updated_at": db.utc_now(),
        })
        known[source_novel_id] = novel
        recompute_canonical(key)
        _cache_cover_and_update(adapter, novel["id"], meta.cover_url)
        queued = _queue_canonical_work(
            adapter, novel, meta, prio_meta=8 if meta.status == "completed" else 10)
        _mark_candidate(row["id"], "done", attempts=(row.get("attempts") or 0) + 1,
                        free_chapter_count=meta.chapter_count, retry_after=None,
                        last_error=None)
        if queued:
            added += 1
        time.sleep(1.0)
    log.info("Discovery queue %s: kiểm tra %d/%d, nhận %d/%d",
             adapter.name, checked, len(rows), added, max_new)


def discover_ranking(adapter: SourceAdapter, max_new: int = 30) -> None:
    """Discovery theo BẢNG XẾP HẠNG nguồn (truyện hot) — ưu tiên hơn discovery thường.
    Lưu `source_rank` (để "Đề cử" xếp theo độ hot) + dịch metadata/chương mẫu như discover_latest.
    Truyện đã có → chỉ cập nhật lại rank. Adapter không có fetch_ranking (ddxs) → bỏ qua."""
    fetch = getattr(adapter, "fetch_ranking", None)
    if not fetch:
        return
    sid = _source_id(adapter)
    added = skipped = errors = scanned = 0
    # Quét HẾT bảng xếp hạng mỗi chu kỳ: rank mọi truyện đã có được cập nhật (top
    # không cố định), truyện chưa có thì thêm dần max_new/chu kỳ tới khi vét cạn top.
    ranked = list(fetch(limit=1000))
    known = _existing_novels(sid, [r[0] for r in ranked])  # check theo lô
    bl_ids, bl_keys = _blacklist(sid)
    consec_fail = 0
    blocked = False  # nguồn bị chặn → thôi thử metadata mới, vẫn cập nhật rank truyện đã có
    for i, (source_novel_id, rank) in enumerate(ranked):
        # Cập nhật rank cho hàng trăm truyện đã có là chuỗi UPDATE lặng (không log,
        # không tải gì) — điểm danh định kỳ để Worker tab không tưởng crawler chết.
        if i % 50 == 0:
            db.heartbeat("crawler", note=f"quét ranking {adapter.name} ({i}/{len(ranked)})")
        if source_novel_id in known:
            # ranking /allvisit/ = lượt đọc tổng → thứ hạng gần như bất động giữa các
            # chu kỳ; chỉ UPDATE khi rank ĐỔI thật, khỏi bắn trăm round-trip no-op.
            if known[source_novel_id].get("source_rank") != rank:
                db.sb().table("novels").update({"source_rank": rank}).eq(
                    "id", known[source_novel_id]["id"]).execute()
            skipped += 1
            continue
        if source_novel_id in bl_ids or (sid, source_novel_id) in _genre_skipped:
            skipped += 1
            continue  # admin đã xoá vĩnh viễn / thể loại hạn chế — không crawl lại dù trong top
        if added >= max_new or blocked:
            continue  # hết quota / nguồn bị chặn — vẫn quét nốt để cập nhật rank truyện đã có
        scanned += 1
        try:
            meta = adapter.fetch_novel_meta(source_novel_id)
        except Exception as e:
            consec_fail += 1
            if isinstance(e, ValueError):
                skipped += 1
                log.info("Ranking: bỏ qua %s (%s) — %s", source_novel_id, adapter.name, e)
            else:
                errors += 1
                log.exception("Ranking: lỗi metadata %s (%s)", source_novel_id, adapter.name)
            if consec_fail >= 8:
                blocked = True
                log.warning("Ranking %s: %d truyện liên tiếp thất bại — nguồn có vẻ bị chặn, "
                            "dừng thêm mới (vẫn cập nhật rank truyện đã có)", adapter.name, consec_fail)
            time.sleep(0.5)
            continue
        consec_fail = 0  # lấy được metadata → nguồn còn sống, reset đếm
        if _skip_by_source_policy(adapter, meta):
            skipped += 1
            continue
        if _skip_by_genre(sid, meta):
            skipped += 1
            continue
        key = dedup_key(meta.title_zh, meta.author_zh)
        if key in bl_keys:
            skipped += 1
            continue  # bản clone của truyện admin đã xoá vĩnh viễn
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
        if not _queue_canonical_work(
                adapter, novel, meta,
                prio_meta=8 if meta.status == "completed" else 10):
            skipped += 1
            continue
        added += 1
        log.info("Ranking %s: nhận %d/%d — #%d %s (source=%s, novel=%s)",
                 adapter.name, added, max_new, rank + 1, meta.title_zh,
                 meta.source_novel_id, novel["id"])
        time.sleep(1.0)
    log.info("Ranking %s: xong %d/%d truyện đạt — ứng viên=%d, đã thử=%d, "
             "bỏ qua=%d, lỗi=%d%s", adapter.name, added, max_new, len(ranked),
             scanned, skipped, errors, " (hết pool ứng viên)" if added < max_new else "")


_CJK = re.compile(r"[㐀-䶿一-鿿]")


def _zh_candidates(q: str) -> list[str]:
    """Tên không có chữ Hán (user gõ tên Hán-Việt/tiếng Việt) → nhờ LLM đoán tối đa
    3 tên gốc tiếng Trung khả dĩ để search nguồn. Có chữ Hán thì dùng nguyên văn.
    # ponytail: nguồn chặn search → tick sau gọi LLM lại cho cùng request (vài chục
    # token/lần, tối đa 1h) — cache vào note khi nào thấy tốn mới làm."""
    if _CJK.search(q):
        return [q]
    from ..translator.providers import build_chain
    res = build_chain().complete(
        "Bạn là chuyên gia tiểu thuyết mạng Trung Quốc, thuộc tên Hán-Việt của các bộ nổi tiếng.",
        f'Tên tiếng Việt (Hán-Việt) của một tiểu thuyết mạng Trung Quốc: "{q}".\n'
        "Liệt kê tối đa 3 tên gốc tiếng Trung khả dĩ nhất (khả dĩ nhất đứng đầu), "
        "mỗi dòng một tên, CHỮ HÁN GIẢN THỂ (简体字), không đánh số, không giải thích.",
        temperature=0.0, max_tokens=2048)
    from opencc import OpenCC  # LLM hay trả phồn thể dù dặn giản thể → ép bằng code
    t2s = OpenCC("t2s")
    out: list[str] = []
    for ln in res.text.strip().splitlines():
        ln = t2s.convert(ln.strip(" \t-•*.、0123456789"))
        # chỉ nhận dòng thuần tên (có chữ Hán, không quá dài) — lọc rác/giải thích
        if ln and _CJK.search(ln) and len(ln) <= 30 and ln not in out:
            out.append(ln)
    log.info("Yêu cầu '%s' → ứng viên tên gốc: %s", q, out[:3])
    return out[:3]


def process_novel_requests(adapters: list[SourceAdapter], limit: int = 3) -> None:
    """User nhập tên truyện trong app (bảng novel_requests) — tiếng Trung dùng thẳng,
    tiếng Việt thì tra DB sẵn có rồi nhờ LLM đoán tên gốc → tìm lần lượt trên các
    nguồn có search, thấy thì crawl như thêm tay + bỏ vào tủ sách người xin.
    Truyện crawl về hiển thị chung ở Khám phá như mọi truyện khác."""
    reqs = (
        db.sb().table("novel_requests").select("id, user_id, query, created_at")
        .eq("status", "pending").order("created_at").limit(limit).execute()
    ).data or []
    for r in reqs:
        q = (r["query"] or "").strip()
        novel = None
        blocked = False  # có nguồn đang chặn search → chưa thể kết luận "không có"
        try:
            # tên tiếng Việt mà truyện đã crawl sẵn → khớp title_vi trong DB, khỏi LLM
            if not _CJK.search(q):
                hit = (db.sb().table("novels").select("id")
                       .ilike("title_vi", q).limit(1).execute()).data
                if hit:
                    novel = hit[0]
                    log.info("Yêu cầu truyện #%s '%s' → đã có sẵn novel %s",
                             r["id"], q, novel["id"])
            for q_zh in [] if novel else _zh_candidates(q):
                for a in adapters:
                    try:
                        hits = a.search(q_zh)
                    except Exception:
                        blocked = True  # (shuhaige chặn tần suất search) — thử lại tick sau
                        continue
                    # Trang kết quả (shuhaige) lẫn cả khối đề cử → CHỈ nhận tựa khớp đúng
                    # hoặc chứa chuỗi tìm; không thì coi như nguồn này không có (bug thật
                    # 2026-07-07: từng lấy nhầm truyện đề cử đầu trang).
                    exact = [h for h in hits if h[1] == q_zh]
                    cand = exact or [h for h in hits if q_zh in h[1]]
                    if not cand:
                        continue
                    novel = add_novel(a, cand[0][0])
                    log.info("Yêu cầu truyện #%s '%s' (%s) → novel %s (%s)",
                             r["id"], q, q_zh, novel["id"], a.name)
                    break
                if novel is not None:
                    break
        except Exception as e:
            log.exception("Yêu cầu truyện #%s lỗi", r["id"])
            db.sb().table("novel_requests").update(
                {"status": "failed", "note": str(e)[:300]}).eq("id", r["id"]).execute()
            continue
        if novel is None:
            # Nguồn đang chặn tần suất → giữ pending thử lại. Hạn 1 GIỜ mới chốt:
            # discovery quét nguồn xong thì search thường bị chặn thêm một lúc,
            # hạn 10 phút từng chốt oan "không có" (E2E 2026-07-08).
            age_sec = (datetime.now(timezone.utc)
                       - datetime.fromisoformat(r["created_at"])).total_seconds()
            if blocked and age_sec < 3600:
                continue
            db.sb().table("novel_requests").update(
                {"status": "notfound", "note": "Không nguồn nào có truyện này"}
            ).eq("id", r["id"]).execute()
        else:
            # vào thẳng tủ sách người xin — yêu cầu riêng thì kết quả phải nằm trong tầm tay
            db.sb().table("library").upsert(
                {"user_id": r["user_id"], "novel_id": novel["id"]}).execute()
            db.sb().table("novel_requests").update(
                {"status": "done", "novel_id": novel["id"]}).eq("id", r["id"]).execute()


def add_novel(adapter: SourceAdapter, source_novel_id: str) -> dict:
    """Thêm 1 truyện theo book_id (luồng chính: nguồn không có discovery tự động).
    Thêm TAY là chủ đích → gỡ khỏi crawl_blacklist nếu từng bị xoá vĩnh viễn."""
    meta = adapter.fetch_novel_meta(source_novel_id)
    if _skip_by_source_policy(adapter, meta):
        raise ValueError(
            f"Faloo chỉ crawl truyện có hơn {settings.faloo_free_chapter_threshold} "
            f"chương free; truyện này có {meta.chapter_count}")
    key = dedup_key(meta.title_zh, meta.author_zh)
    db.sb().table("crawl_blacklist").delete().eq(
        "source_id", _source_id(adapter)).eq("source_novel_id", source_novel_id).execute()
    db.sb().table("crawl_blacklist").delete().eq("dedup_key", key).execute()
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


def sync_chapter_list(
    adapter: SourceAdapter, novel_id: int, source_novel_id: str,
    limit_stubs: int | None = None,
) -> tuple[int, int]:
    """Cập nhật mục lục 1 truyện; trả (tổng chương trên nguồn, số stub mới upsert).

    MỤC LỤC LƯỜI (tiết kiệm DB — stub từng chiếm 92% dung lượng):
    - limit_stubs=None → sync ĐẦY ĐỦ + đánh dấu novels.toc_synced_at (truyện active).
    - limit_stubs=N    → chỉ giữ N stub đầu (chương mẫu của truyện chưa ai đọc).
    - limit_stubs=0    → không đụng stub, chỉ cập nhật số chương/last_chapter_at
      (refresh định kỳ truyện lười).

    Chỉ upsert phần CHƯA có: trường hợp thường gặp nhất khi soi định kỳ là "không
    đổi gì" → 1 query count là xong, khỏi kéo 4000 index + re-upsert 4000 stub.
    ponytail: chương đã có KHÔNG được refresh title/source_chapter_id — nguồn đánh
    lại số chương thì _rescue_stale_chapter tự làm mới khi phát hiện."""
    refs = adapter.fetch_chapter_list(source_novel_id)
    total = len(refs)
    if limit_stubs is not None:
        refs = refs[:limit_stubs]
    added = 0
    if refs:
        existing_count = (
            db.sb().table("chapters").select("id", count="exact")
            .eq("novel_id", novel_id).limit(1).execute()
        ).count or 0
        # Stub do request_translation tạo (migration 042) có source_chapter_id NULL.
        # PHẢI backfill id từ mục lục nguồn, không thì ensure_chapters_fetched bỏ qua
        # → chương kẹt 'queued' vĩnh viễn (và chặn chương sau theo dịch tuần tự 030).
        # 1 count rẻ để GIỮ fast-path: truyện refresh không có stub thiếu id thì khỏi
        # kéo cả 4000 index về so.
        null_stub_count = (
            db.sb().table("chapters").select("id", count="exact")
            .eq("novel_id", novel_id).is_("source_chapter_id", "null")
            .limit(1).execute()
        ).count or 0
        if existing_count < len(refs) or null_stub_count > 0:
            # kéo (index → source_chapter_id) đã có THEO TRANG — PostgREST trần 1000
            # dòng/query; kéo 1 lần với truyện 4000 chương → thiếu → bump nhiễu.
            have: dict[int, str | None] = {}
            frm = 0
            while True:
                b = (
                    db.sb().table("chapters").select("chapter_index, source_chapter_id")
                    .eq("novel_id", novel_id).range(frm, frm + 999).execute()
                ).data or []
                for r in b:
                    have[r["chapter_index"]] = r.get("source_chapter_id")
                if len(b) < 1000:
                    break
                frm += 1000
            # ghi: chương CHƯA có index (nguồn dài thêm) + stub CŨ còn thiếu id (backfill).
            # Chương đã có id thì KHÔNG đụng — giữ nguyên ý "không refresh title/id" cũ.
            to_write = [ref for ref in refs
                        if ref.index not in have or have[ref.index] is None]
            if to_write:
                db.upsert_chapter_stubs([
                    {
                        "novel_id": novel_id,
                        "chapter_index": ref.index,
                        "source_chapter_id": ref.source_chapter_id,
                        "title_zh": ref.title_zh,
                    }
                    for ref in to_write
                ])
                added = len(to_write)
    # bump khi TỔNG trên nguồn tăng so với số đã lưu → "Mới cập nhật" đúng cả với
    # truyện lười (không có stub để so)
    row = (
        db.sb().table("novels").select("chapter_count_source, status")
        .eq("id", novel_id).single().execute()
    ).data or {}
    # status parse ké từ chính trang mục lục vừa tải (khuôn biquge; nguồn không lộ →
    # None, bỏ qua) → truyện hoàn thành SAU discovery tự flip completed (rời vòng
    # refresh), truyện completed viết tiếp tự flip ongoing (quay lại vòng).
    src_status = getattr(adapter, "last_toc_status", None)
    fields = _chapter_sync_fields(
        old_count=row.get("chapter_count_source") or 0,
        old_status=row.get("status"),
        source_status=src_status,
        total=total,
        full_toc=limit_stubs is None,
        now=db.utc_now(),
    )
    if src_status and src_status != row.get("status"):
        log.info("Truyện %s đổi trạng thái %s → %s (theo nguồn)",
                 novel_id, row.get("status"), src_status)
    if fields:
        db.sb().table("novels").update(fields).eq("id", novel_id).execute()
    return total, added


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
            total, n = sync_chapter_list(adapter, nv["id"], nv["source_novel_id"])
            if n:
                log.info("Truyện %s có %d chương mới", nv["id"], n)
                queued = queue_followed_new_chapters(nv["id"], total, n)
                if queued:
                    log.info("Tủ sách: tự dịch đón %d chương mới truyện %s", queued, nv["id"])
            db.sb().table("novels").update(
                {"last_checked_at": db.utc_now()}).eq("id", nv["id"]).execute()
        except Exception:
            log.exception("Lỗi sync truyện %s", nv["id"])
        time.sleep(2.0)


def queue_followed_new_chapters(novel_id: int, total: int, n_new: int) -> int:
    """Truyện trong tủ sách ra chương mới → tự xếp dịch luôn, người đọc đuổi mở app
    là có sẵn (không phải bấm rồi ngồi chờ). Chỉ khi bản dịch đã ĐUỔI KỊP gần cuối
    truyện trước đợt chương mới — đang cày giữa truyện thì tự-dịch-trước lúc đọc lo,
    nhảy cóc dịch mấy chương cuối là thừa.
    ponytail: n_new lớn = đợt sync đầu sau khi thêm tủ sách (truyện lười vừa có đủ
    mục lục), không phải chương mới thật → bỏ qua."""
    if n_new > 20:
        return 0
    last_done = (
        db.sb().table("chapters").select("chapter_index")
        .eq("novel_id", novel_id).eq("translation_status", "done")
        .order("chapter_index", desc=True).limit(1).execute()
    ).data
    if not last_done or last_done[0]["chapter_index"] < total - n_new - 3:
        return 0
    rows = (
        db.sb().table("chapters").select("id")
        .eq("novel_id", novel_id).gt("chapter_index", last_done[0]["chapter_index"])
        .in_("translation_status", ["none", "failed"])
        .order("chapter_index").limit(20).execute()
    ).data or []
    if not rows:
        return 0
    db.sb().table("chapters").update({"translation_status": "queued"}).in_(
        "id", [r["id"] for r in rows]).execute()
    for r in rows:
        db.enqueue("chapter", novel_id, chapter_id=r["id"], priority=settings.prio_follow)
    return len(rows)


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
        db.sb().table("novels")
        .select("id, source_novel_id, hidden, meta_translated, status, toc_synced_at")
        .eq("source_id", sid).eq("is_canonical", True)
        # Truyện HOÀN THÀNH không bao giờ ra chương mới → soi lại mục lục là phí trắng
        # (từng chiếm 56% kho canonical). Ngân sách refresh dồn cho truyện đang-ra, mới
        # đáng theo dõi. status chỉ được set lúc discovery nên đây là "đã biết hoàn thành".
        .neq("status", "completed")
        .order("last_checked_at", desc=False, nullsfirst=True)  # chưa soi/lâu nhất trước
        .limit(limit).execute()
    ).data or []
    # Vé phụ ~10% ngân sách: truyện completed bị loại khỏi vòng chính, nhưng nguồn có
    # thể gắn nhầm trạng thái / viết tiếp → soi lác đác vài truyện cũ nhất mỗi chu kỳ;
    # nguồn nói ongoing thì sync_chapter_list tự flip status → quay lại vòng chính.
    rows += (
        db.sb().table("novels")
        .select("id, source_novel_id, hidden, meta_translated, status, toc_synced_at")
        .eq("source_id", sid).eq("is_canonical", True).eq("status", "completed")
        .order("last_checked_at", desc=False, nullsfirst=True)
        .limit(max(1, limit // 10)).execute()
    ).data or []
    for i, nv in enumerate(rows):
        if reader_fetch_waiting():
            log.info("Refresh %s: nhường chỗ tải chương người đọc (đã soi %d/%d)",
                     adapter.name, i, len(rows))
            break
        db.heartbeat("crawler", note=f"soi mục lục novel {nv['id']} ({i + 1}/{len(rows)})")
        synced = False
        try:
            # truyện lười (chưa ai đọc) → limit_stubs=0: chỉ cập nhật số chương, không đẻ stub
            total, n = sync_chapter_list(
                adapter, nv["id"], nv["source_novel_id"],
                limit_stubs=None if nv.get("toc_synced_at") else 0)
            if n:
                log.info("Truyện %s +%d chương mới", nv["id"], n)
            if n or total:
                _maybe_unhide_grown(nv)
            synced = True
        except Exception:
            log.exception("Lỗi refresh truyện %s", nv["id"])
        # Chỉ đánh dấu đã soi khi parse thành công; lỗi tạm phải được retry sớm.
        if synced:
            db.sb().table("novels").update(
                {"last_checked_at": db.utc_now()}).eq("id", nv["id"]).execute()
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


def _fail_chapter(ch: dict, msg: str) -> None:
    db.sb().table("chapters").update(
        {"translation_status": "failed"}).eq("id", ch["id"]).execute()
    db.sb().table("translation_jobs").update(
        {"status": "failed", "error": msg[:500]}
    ).eq("chapter_id", ch["id"]).eq("status", "pending").execute()


def _refresh_chapter_ids(novel_id: int, refs: list) -> int:
    """Nguồn đánh lại id trang chương → cập nhật source_chapter_id các stub bị lệch
    theo mục lục mới (khớp theo chapter_index). Trả số stub đã làm mới."""
    by_index = {r.index: r for r in refs}
    updated = 0
    frm = 0
    while True:
        rows = (
            db.sb().table("chapters").select("id, chapter_index, source_chapter_id")
            .eq("novel_id", novel_id).range(frm, frm + 999).execute()
        ).data or []
        for row in rows:
            ref = by_index.get(row["chapter_index"])
            if ref and ref.source_chapter_id != row["source_chapter_id"]:
                db.sb().table("chapters").update(
                    {"source_chapter_id": ref.source_chapter_id}).eq("id", row["id"]).execute()
                updated += 1
        if len(rows) < 1000:
            break
        frm += 1000
    return updated


def _rescue_stale_chapter(adapter: SourceAdapter, novel_id: int, ch: dict, err) -> bool:
    """Chương vẫn 404 sau NOT_READY_GIVE_UP lần: KIỂM CHỨNG trước khi kết luận, vì
    "trang chương chết" ≠ "truyện bị gỡ" — truyện trong top nguồn vẫn sống nhăn răng,
    thường chỉ là nguồn ĐÁNH LẠI id chương làm stub của ta stale.

    - Trang truyện cũng chết → đánh failed "truyện có thể đã bị gỡ" (như cũ, giờ có kiểm chứng).
    - Truyện còn + id chương trong mục lục mới KHÁC stub → làm mới toàn bộ id, giữ queued
      thử lại. Trả True để dừng chu kỳ này của truyện (các chương sau cũng stale).
    - Truyện còn + id không đổi → nguồn thật sự thiếu trang chương này → failed với lý do đúng.
    """
    nv = (
        db.sb().table("novels").select("source_novel_id")
        .eq("id", novel_id).single().execute()
    ).data or {}
    try:
        refs = adapter.fetch_chapter_list(nv.get("source_novel_id") or "")
    except Exception:
        _fail_chapter(ch, f"crawl: trang chương lẫn trang truyện đều không truy cập được "
                          f"sau {NOT_READY_GIVE_UP} lần thử — truyện có thể đã bị gỡ khỏi nguồn ({err})")
        log.warning("Chương %s + trang truyện novel %s đều chết — đánh failed", ch["id"], novel_id)
        return False
    ref = next((r for r in refs if r.index == ch["chapter_index"]), None)
    if ref and ref.source_chapter_id != ch["source_chapter_id"]:
        n = _refresh_chapter_ids(novel_id, refs)
        log.warning("Novel %s: nguồn đánh lại id chương — làm mới %d stub, thử lại vòng sau",
                    novel_id, n)
        return True
    _fail_chapter(ch, f"crawl: truyện vẫn còn trên nguồn nhưng trang chương "
                      f"{ch['chapter_index']} không tồn tại sau {NOT_READY_GIVE_UP} lần thử ({err})")
    log.warning("Chương %s không có trang dù truyện %s còn sống — đánh failed", ch["id"], novel_id)
    return False


def ensure_chapters_fetched(adapter: SourceAdapter, novel_id: int) -> None:
    """Tải content_zh cho các chương đã queued dịch mà chưa có nội dung gốc."""
    rows = (
        db.sb().table("chapters")
        .select("id, source_chapter_id, chapter_index")
        .eq("novel_id", novel_id)
        .eq("translation_status", "queued")
        .is_("content_zh", "null")
        .order("chapter_index")
        .limit(max(1, settings.crawl_fetch_batch))
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
        except SourceBlocked as e:
            log.warning("Nguồn %s đang chặn IP (%s) — dừng tải chương chu kỳ này",
                        adapter.name, e)
            return
        except ChapterNotReady as e:
            # Lỗi TẠM: nguồn liệt kê chương nhưng trang chưa sinh → giữ queued thử lại.
            # Quá NOT_READY_GIVE_UP lần liên tiếp → kiểm chứng trang truyện rồi mới kết luận.
            n = _not_ready_count[ch["id"]] = _not_ready_count.get(ch["id"], 0) + 1
            if n >= NOT_READY_GIVE_UP:
                _not_ready_count.pop(ch["id"], None)
                if _rescue_stale_chapter(adapter, novel_id, ch, e):
                    return  # id đã làm mới — chương còn lại cũng stale, để chu kỳ sau tải bằng id mới
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
