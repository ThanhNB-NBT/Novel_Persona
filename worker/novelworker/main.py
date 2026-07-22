"""Entry point.

Backend chạy nền (Docker: 2 service crawler + translator — xem docker-compose.yml):
    python -m novelworker.main crawl        # crawler: discovery + sync + tải chương
    python -m novelworker.main translate    # translator: consumer hàng đợi dịch

Lệnh vận hành:
    python -m novelworker.main add --book-id 59979          # thêm truyện shuhaige (số trong URL)
    python -m novelworker.main request --novel 1 --up-to 10  # giả lập app bấm "Đọc" (không cần app/auth)
    python -m novelworker.main cost                          # thống kê token đã dùng theo model
    python -m novelworker.main audit [--fix]                 # quét chương done hỏng (Trung/cụt/mất đoạn), --fix để dịch lại
    python -m novelworker.main quality [--novel <id>]        # chấm điểm chất lượng dịch (metric: len, glossary, lặp cụm, mất đoạn)
    python -m novelworker.main meta --novel <id>             # dịch lại metadata (tên/mô tả/thể loại) 1 truyện — sau khi sửa prompt tên
"""
from __future__ import annotations

import argparse
import logging
import threading
import time

from . import db
from .config import settings
from .crawler.base import SourceAdapter
from .crawler.registry import TEMPLATE_REGISTRY
from .crawler import sync
from .translator import worker as translator_worker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
# httpx INFO log MỌI request Supabase (~10 dòng/10s/container) → log Docker phình
# chiếm đĩa VPS; chỉ giữ cảnh báo/lỗi. Log nghiệp vụ của worker không bị ảnh hưởng.
logging.getLogger("httpx").setLevel(logging.WARNING)
log = logging.getLogger("main")


def build_adapters() -> dict[str, SourceAdapter]:
    """Dựng adapter từ bảng `sources` (enabled) theo template. Thêm nguồn biquge-clone
    = 1 dòng INSERT vào sources, KHÔNG code. Template lạ → bỏ qua + cảnh báo."""
    rows = db.sb().table("sources").select("*").eq("enabled", True).execute().data or []
    out: dict[str, SourceAdapter] = {}
    for s in rows:
        cls = TEMPLATE_REGISTRY.get(s.get("template") or "")
        if not cls:
            log.warning("Chưa hỗ trợ template '%s' (nguồn %s) — bỏ qua", s.get("template"), s["name"])
            continue
        out[s["name"]] = cls(base_url=s["base_url"], config=s.get("config") or {}, source_row=s)
    if not out:
        log.warning("Không có nguồn enabled nào dựng được adapter — kiểm tra bảng sources")
    return out


def _ordered_novel_ids(jobs: list[dict], missing_chapter_ids: set[int]) -> list[int]:
    """Giữ thứ tự priority/created_at của job, nhưng mỗi novel chỉ xuất hiện một lần."""
    out: list[int] = []
    seen: set[int] = set()
    for job in jobs:
        novel_id = job.get("novel_id")
        if job.get("chapter_id") in missing_chapter_ids and novel_id not in seen:
            seen.add(novel_id)
            out.append(novel_id)
    return out


def _reconcile_adapters(adapters: dict[str, SourceAdapter]) -> None:
    """Ăn trạng thái bật/tắt nguồn từ DB mà không cần restart crawler.

    Adapter đang chạy được giữ nguyên để không mất bộ đếm health; nguồn vừa bật mới
    được dựng thêm, nguồn vừa tắt bị gỡ ngay khỏi vòng crawl kế tiếp.
    """
    rows = db.sb().table("sources").select("*").eq("enabled", True).execute().data or []
    enabled = {s["name"]: s for s in rows}
    for name in set(adapters) - set(enabled):
        adapters.pop(name, None)
        log.info("Nguồn '%s' đã tắt — gỡ khỏi crawler đang chạy", name)
    for name, source in enabled.items():
        if name in adapters:
            continue
        cls = TEMPLATE_REGISTRY.get(source.get("template") or "")
        if not cls:
            log.warning("Chưa hỗ trợ template '%s' (nguồn %s) — bỏ qua",
                        source.get("template"), name)
            continue
        adapters[name] = cls(base_url=source["base_url"], config=source.get("config") or {},
                             source_row=source)
        log.info("Nguồn '%s' vừa bật — thêm vào crawler đang chạy", name)


def _novels_needing_fetch(enabled_source_ids: set[int]) -> list[dict]:
    """Novel cần tải bản gốc, đúng thứ tự ưu tiên của hàng dịch và chỉ từ nguồn đang bật."""
    if not enabled_source_ids:
        return []
    jobs = (
        db.sb().table("translation_jobs")
        .select("novel_id,chapter_id,priority,created_at")
        .eq("type", "chapter").eq("status", "pending")
        .not_.is_("chapter_id", "null")
        .order("priority").order("created_at").limit(200).execute()
    ).data or []
    chapter_ids = [j["chapter_id"] for j in jobs]
    if not chapter_ids:
        return []
    missing = (
        db.sb().table("chapters").select("id")
        .in_("id", chapter_ids).eq("translation_status", "queued")
        .is_("content_zh", "null").execute()
    ).data or []
    ids = _ordered_novel_ids(jobs, {r["id"] for r in missing})
    if not ids:
        return []
    rows = (
        db.sb().table("novels").select("id, source_id, source_novel_id")
        .in_("id", ids).in_("source_id", list(enabled_source_ids)).execute()
    ).data or []
    by_id = {r["id"]: r for r in rows}
    return [by_id[novel_id] for novel_id in ids if novel_id in by_id]


def _eval_source_health(adapter: SourceAdapter) -> bool:
    """Cuối mỗi tick: có fetch OK → nguồn sống; toàn fail → fail++ và có thể tự tắt.
    Không fetch gì thì bỏ qua. Sau đó reset counter cho tick kế tiếp."""
    sid = adapter.source_row.get("id")
    if sid is None:
        return False
    disabled = False
    if adapter.fetch_ok > 0:
        db.mark_source_ok(sid)
    elif adapter.fetch_err > 0:
        disabled = db.mark_source_fail(sid, settings.source_fail_limit)
        if disabled:
            log.error("Đã TỰ TẮT nguồn '%s' (toàn fetch fail ≥%d tick). Khi nguồn hồi phục, "
                      "chỉ cần bật lại trong bảng sources; crawler sẽ tự nạp lại.",
                      adapter.name, settings.source_fail_limit)
    adapter.reset_health_counters()
    return disabled


def _refresh_cfg(cfg: dict) -> None:
    """Config chỉnh từ app (worker_settings) → cập nhật dict dùng chung; luồng nguồn đọc
    mỗi tick nên đổi là ăn trong ~10s. Lỗi/thiếu → giữ giá trị hiện tại."""
    rs = db.runtime_settings()
    cfg["interval_min"] = db.runtime_int(rs, "crawl_interval_min", cfg["interval_min"])
    cfg["max_new"] = db.runtime_int(rs, "discover_new_per_cycle", cfg["max_new"])
    cfg["refresh_n"] = db.runtime_int(rs, "refresh_per_cycle", cfg["refresh_n"])
    settings.faloo_free_chapter_threshold = db.runtime_int(
        rs, "faloo_free_chapter_threshold", settings.faloo_free_chapter_threshold)
    settings.discover_min_chapters = db.runtime_int(
        rs, "discover_min_chapters", settings.discover_min_chapters)
    settings.sample_chapters = db.runtime_int(
        rs, "sample_chapters", settings.sample_chapters, lo=0)  # 0 = tắt dịch đọc thử
    settings.crawl_fetch_batch = db.runtime_int(
        rs, "crawl_fetch_batch", settings.crawl_fetch_batch)


def _source_tick(adapter: SourceAdapter, pending_fetch: list[dict], due: bool,
                 max_new: int, refresh_n: int) -> None:
    """Một vòng crawl của MỘT nguồn: tải chương người đọc chờ trước, rồi discovery/refresh
    theo chu kỳ. Tách khỏi run_crawler để mỗi nguồn chạy luồng riêng — nguồn chậm/chết
    không chặn nguồn khác. process_novel_requests KHÔNG ở đây (luồng riêng lo, khỏi mỗi
    nguồn tìm lại cùng một yêu cầu)."""
    sid = adapter.source_row.get("id")
    # 0) mục lục lười: app xin tải mục lục đầy đủ (request_toc) — ưu tiên, tối đa 3 truyện/tick
    toc_reqs = (
        db.sb().table("novels").select("id, source_id, source_novel_id")
        .eq("source_id", sid).is_("toc_synced_at", "null")
        .not_.is_("toc_requested_at", "null")
        .order("toc_requested_at").limit(3).execute()
    ).data or []
    for nv in toc_reqs:
        try:
            total, n = sync.sync_chapter_list(adapter, nv["id"], nv["source_novel_id"])
            log.info("TOC lười: novel %s đủ mục lục (%d chương, +%d stub)", nv["id"], total, n)
        except Exception:
            # gỡ cờ xin để không hammer mỗi tick; user mở lại truyện sẽ xin lại
            db.sb().table("novels").update({"toc_requested_at": None}).eq("id", nv["id"]).execute()
            log.exception("TOC lười: lỗi novel %s — gỡ cờ chờ xin lại", nv["id"])
    # 1) tải nội dung chương đang chờ dịch — NGƯỜI ĐỌC TRƯỚC. Discovery (bước 2, có thể
    # cả tiếng) tự nhường giữa chừng khi có chương ưu tiên cao chờ (sync.reader_fetch_waiting).
    for nv in pending_fetch:
        if nv["source_id"] != sid:
            continue
        # Mục lục chỉ cần sync khi có chương queued THIẾU stub nguồn (lần đầu user bấm Đọc,
        # RPC tạo row trước khi TOC về).
        missing_stub = (
            db.sb().table("chapters").select("id", count="exact")
            .eq("novel_id", nv["id"]).eq("translation_status", "queued")
            .is_("source_chapter_id", "null").limit(1).execute()
        ).count or 0
        if missing_stub:
            sync.sync_chapter_list(adapter, nv["id"], nv["source_novel_id"])
        sync.ensure_chapters_fetched(adapter, nv["id"])
    # 2) discovery + sync truyện theo dõi — theo chu kỳ dài. Cào MỌI mục để truyện dày dần.
    if due:
        sync.discover_ranking(adapter, max_new=max_new)
        sync.discover_pool(adapter, "fetch_recommended", "Recommended")
        sync.discover_pool(adapter, "fetch_top", "Top")
        sync.discover_pool(adapter, "fetch_completed", "Completed")
        sync.discover_pool(adapter, "fetch_latest", "Latest")
        sync.process_discovery_candidates(adapter, max_new=max_new)
        sync.sync_followed_novels(adapter)
        # truyện đã có ra chương mới → nổi "Mới cập nhật" (không chỉ truyện mới)
        sync.refresh_canonical_updates(adapter, limit=refresh_n)


def _source_loop(adapter: SourceAdapter, stop: threading.Event, cfg: dict) -> None:
    """Luồng crawl riêng một nguồn: tự cadence discovery, tự đo sức khoẻ. Tự tắt nguồn
    (toàn fetch fail nhiều chu kỳ) → thoát luồng; coordinator reconcile sẽ gỡ khỏi vòng."""
    sid = adapter.source_row.get("id")
    # Mốc = lúc luồng bắt đầu, KHÔNG phải 0: nếu 0 thì tick đầu sau restart luôn "due"
    # → discovery chạy ngay bất chấp interval_min (interval to cỡ nào cũng bị cào 1 đợt).
    last_discovery = time.time()
    while not stop.is_set():
        started = time.time()
        db.heartbeat("crawler")  # nguồn nào còn sống cũng điểm danh — app thấy crawler sống
        due = started - last_discovery > cfg["interval_min"] * 60
        try:
            pending = _novels_needing_fetch({sid}) if sid is not None else []
            _source_tick(adapter, pending, due, cfg["max_new"], cfg["refresh_n"])
        except Exception:
            log.exception("Lỗi vòng crawl (%s)", adapter.name)
        finally:
            # Dời mốc discovery kể cả khi tick lỗi (như bản cũ) — khỏi lặp lại cả khối
            # discovery nặng mỗi 10s; tải chương người đọc vẫn chạy mỗi tick.
            if due:
                last_discovery = started
            try:
                if _eval_source_health(adapter):
                    log.warning("Nguồn '%s' tự tắt — dừng luồng crawl", adapter.name)
                    return
            except Exception:
                log.exception("Không ghi được health nguồn %s", adapter.name)
        stop.wait(10)


def run_crawler() -> None:
    """Coordinator: mỗi nguồn 1 luồng crawl riêng + 1 luồng xử lý yêu cầu truyện. Main
    thread lo heartbeat, reconcile bật/tắt nguồn, refresh config, quản vòng đời luồng.

    curl_cffi Session tạo curl handle theo từng luồng (use_thread_local_curl) → chia sẻ
    adapter giữa các luồng an toàn."""
    adapters = build_adapters()
    adapters_lock = threading.Lock()
    log.info("Crawler bắt đầu (%d nguồn: %s), chu kỳ discovery %d phút — mỗi nguồn 1 luồng",
             len(adapters), ", ".join(adapters) or "—", settings.crawl_interval_min)
    sync.backfill_dedup_keys()  # gán dedup_key cho truyện cũ (1 lần, tự lành)
    cfg = {
        "interval_min": settings.crawl_interval_min,
        "max_new": settings.discover_new_per_cycle,
        "refresh_n": settings.refresh_per_cycle,
    }

    # Yêu cầu truyện từ app tìm tên trên MỌI nguồn → luồng riêng, poll 10s, không phải
    # đợi discovery của nguồn nào.
    def _requests_loop() -> None:
        while True:
            try:
                with adapters_lock:
                    ads = list(adapters.values())
                if ads:
                    sync.process_novel_requests(ads)
            except Exception:
                log.exception("Lỗi xử lý yêu cầu truyện")
            time.sleep(10)
    threading.Thread(target=_requests_loop, daemon=True).start()

    threads: dict[str, tuple[threading.Thread, threading.Event]] = {}
    while True:
        db.heartbeat("crawler")
        try:
            with adapters_lock:
                _reconcile_adapters(adapters)  # bật/tắt nguồn từ DB, không cần restart
        except Exception:
            log.exception("Không đồng bộ được trạng thái nguồn — tạm giữ cấu hình hiện tại")
        try:
            _refresh_cfg(cfg)
        except Exception:
            log.exception("Không đọc được worker_settings — giữ cấu hình hiện tại")
        # Vòng đời luồng nguồn. Reconcile chạy TRƯỚC nên nguồn vừa tự tắt (enabled=False)
        # đã rời `adapters` → không bị khởi động lại.
        # ponytail: luồng chết bất ngờ mà nguồn còn enabled thì khởi động lại (self-heal);
        # nguồn vừa tự tắt lỡ bị restart 1 nhịp sẽ được reconcile gỡ ở tick kế (~10s, vô hại).
        with adapters_lock:
            names = set(adapters)
            snap = dict(adapters)
        for name in list(threads):
            if name not in names or not threads[name][0].is_alive():
                threads[name][1].set()
                threads.pop(name)
        for name in names:
            if name not in threads:
                ev = threading.Event()
                t = threading.Thread(target=_source_loop, args=(snap[name], ev, cfg), daemon=True)
                t.start()
                threads[name] = (t, ev)
                log.info("Khởi động luồng crawl nguồn '%s'", name)
        time.sleep(10)


def run_cost() -> None:
    """Thống kê token đã dùng theo model (soi chi phí LLM).

    Token lưu trong chapters khi dịch xong. NVIDIA NIM + OpenRouter free = $0;
    chỉ Fireworks (tấm chắn cuối) trả phí — nhìn token model đó để ước tính.
    """
    from collections import defaultdict

    rows = (
        db.sb().table("chapters")
        .select("model_used, prompt_tokens, completion_tokens")
        .eq("translation_status", "done")
        .execute()
    ).data or []
    agg: dict[str, list[int]] = defaultdict(lambda: [0, 0, 0])  # [số chương, prompt, completion]
    for r in rows:
        a = agg[r.get("model_used") or "(chưa rõ)"]
        a[0] += 1
        a[1] += r.get("prompt_tokens") or 0
        a[2] += r.get("completion_tokens") or 0

    print(f"{'model':<40} {'chương':>7} {'prompt':>12} {'output':>12} {'tổng tok':>12}")
    print("-" * 86)
    tot = [0, 0, 0]
    for model, (n, pt, ct) in sorted(agg.items(), key=lambda kv: -kv[1][1] - kv[1][2]):
        print(f"{model[:40]:<40} {n:>7} {pt:>12,} {ct:>12,} {pt + ct:>12,}")
        tot[0] += n; tot[1] += pt; tot[2] += ct
    print("-" * 86)
    print(f"{'TỔNG':<40} {tot[0]:>7} {tot[1]:>12,} {tot[2]:>12,} {tot[1] + tot[2]:>12,}")
    print("\nGhi chú: NVIDIA NIM + OpenRouter (model :free) = $0. Chỉ token model Fireworks mới tính phí.")


def run_audit(fix: bool) -> None:
    """Quét MỌI chương đã 'done', bắt bản dịch hỏng (còn tiếng Trung / cụt / mất đoạn)
    mà lỡ lọt qua (chủ yếu chương cũ dịch bằng model kém trước khi có fuse). In danh sách
    kèm lý do; `--fix` xếp lại hàng đợi để model hiện tại dịch lại.

    Chương dịch MỚI đã được fuse (validate trong FallbackChain) chặn — không thành 'done'
    nếu hỏng. Lệnh này để dọn nợ cũ + tự soi định kỳ cho yên tâm, không phải đợi vào đọc mới biết.
    """
    from .translator.worker import scan_bad_chapters, requeue_bad

    bad = scan_bad_chapters()
    print(f"Quét xong → {len(bad)} chương 'done' hỏng.")
    for c, reason in bad:
        nv = c.get("novels") or {}
        title = nv.get("title_vi") or nv.get("title_zh") or f"#{c['novel_id']}"
        print(f"  nv{c['novel_id']} ch{c['chapter_index']} [{c.get('model_used')}] {title}: {reason}")

    if not bad:
        return
    if not fix:
        print("\nThêm --fix để xếp lại hàng đợi dịch lại các chương này.")
        return
    requeue_bad(bad)
    print(f"\nĐã xếp lại {len(bad)} chương để dịch lại (translator sẽ tự xử lý).")




def _glossary_adherence(zh: str, vi: str, terms: list[dict]) -> tuple[int, int]:
    """(số term tuân thủ, số term áp dụng được). Term áp dụng = term_zh xuất hiện trong zh.
    Tuân thủ = correct_vi có trong vi VÀ (wrong_vi nếu có thì KHÔNG có trong vi)."""
    ok = applicable = 0
    for tm in terms:
        tzh, cv, wv = tm.get("term_zh"), tm.get("correct_vi"), tm.get("wrong_vi")
        if not tzh or not cv or tzh not in zh:
            continue
        applicable += 1
        if cv in vi and (not wv or wv not in vi):
            ok += 1
    return ok, applicable


def run_quality(novel_id: int | None) -> None:
    """Chấm điểm chất lượng dịch (metric, KHÔNG tốn LLM) cho chương done → báo cáo.
    Bắt: còn tiếng Trung, tỉ lệ độ dài bất thường, mất đoạn, lặp từ, lệch glossary."""
    from collections import defaultdict
    from .translator.worker import DUP_PHRASE, han_ratio

    gloss_cache: dict[int, list[dict]] = {}
    def gloss(nid: int) -> list[dict]:
        if nid not in gloss_cache:
            gloss_cache[nid] = db.get_glossary(nid)[0]
        return gloss_cache[nid]

    rows: list[dict] = []
    frm = 0
    while True:
        q = (db.sb().table("chapters")
             .select("id, novel_id, chapter_index, content_zh, content_vi, model_used, "
                     "novels(title_vi, title_zh)")
             .eq("translation_status", "done"))
        if novel_id:
            q = q.eq("novel_id", novel_id)
        b = q.range(frm, frm + 299).execute().data or []
        rows += b
        if len(b) < 300:
            break
        frm += 300

    agg: dict[str, list[float]] = defaultdict(lambda: [0, 0.0, 0.0, 0, 0, 0])  # n, sum_len, sum_adh, dup, no_para, han_bad
    bad: list[tuple[float, str]] = []
    for c in rows:
        zh, vi = c.get("content_zh") or "", c.get("content_vi") or ""
        if not vi:
            continue
        han = han_ratio(vi)
        len_ratio = len(vi) / max(len(zh), 1)
        dup = len(DUP_PHRASE.findall(vi))
        lost_para = 1 if (zh.count("\n") >= 5 and vi.count("\n") == 0) else 0
        ok, appl = _glossary_adherence(zh, vi, gloss(c["novel_id"]))
        adh = ok / appl if appl else 1.0

        a = agg[c.get("model_used") or "(?)"]
        a[0] += 1; a[1] += len_ratio; a[2] += adh
        a[3] += dup; a[4] += lost_para; a[5] += 1 if han > 0.02 else 0

        # điểm "tệ" gộp để xếp chương cần soi (cao = tệ). zh→vi tính KÝ TỰ nên ~2.5-3.5x
        # là BÌNH THƯỜNG; chỉ cờ khi <1.5x (cụt) hoặc >5x (phình/lặp).
        score = (han * 100) + max(0, 1.5 - len_ratio) * 20 + (len_ratio > 5.0) * 20 + \
                (1 - adh) * 30 + dup * 10 + lost_para * 30
        if score >= 10:
            nv = c.get("novels") or {}
            title = nv.get("title_vi") or nv.get("title_zh") or f"#{c['novel_id']}"
            reasons = []
            if han > 0.02: reasons.append(f"Hán {han:.0%}")
            if len_ratio < 1.5: reasons.append(f"cụt {len_ratio:.2f}x")
            if len_ratio > 5.0: reasons.append(f"phình {len_ratio:.2f}x")
            if adh < 1.0 and appl: reasons.append(f"glossary {adh:.0%}({ok}/{appl})")
            if dup: reasons.append(f"lặp cụm {dup}")
            if lost_para: reasons.append("mất đoạn")
            bad.append((score, f"  nv{c['novel_id']} ch{c['chapter_index']} {title}: {', '.join(reasons)}"))

    print(f"Đã chấm {len(rows)} chương done.\n")
    print(f"{'model':<40}{'chương':>7}{'len TB':>8}{'glossary':>9}{'lặp':>6}{'mất đoạn':>9}{'còn Hán':>8}")
    print("-" * 87)
    for m, a in sorted(agg.items(), key=lambda kv: -kv[1][0]):
        n = int(a[0]) or 1
        print(f"{m[:40]:<40}{int(a[0]):>7}{a[1]/n:>8.2f}{a[2]/n*100:>8.0f}%{int(a[3]):>6}{int(a[4]):>9}{int(a[5]):>8}")
    print("\nGhi chú: len TB ~2.5-3.5 là bình thường (zh→vi tính KÝ TỰ); "
          "glossary nên ~100%; lặp cụm/mất đoạn/còn Hán nên 0.")
    bad.sort(reverse=True)
    if bad:
        print(f"\n{len(bad)} chương cần soi (tệ nhất trước):")
        for _, line in bad[:40]:
            print(line)


def run_meta(novel_id: int) -> None:
    """Xếp lại job dịch metadata (tên/mô tả/thể loại) cho 1 truyện — dùng khi đã sửa
    prompt metadata và muốn dịch lại tên đã lưu. Translator đang chạy sẽ tự xử lý."""
    nv = (
        db.sb().table("novels").select("id, title_zh, title_vi")
        .eq("id", novel_id).maybe_single().execute()
    ).data
    if not nv:
        print(f"Không thấy truyện #{novel_id}.")
        return
    # xoá job metadata cũ trước (unique index chặn enqueue trùng khi còn job done), rồi xếp lại
    db.sb().table("translation_jobs").delete().eq("novel_id", novel_id).eq("type", "metadata").execute()
    db.enqueue("metadata", novel_id, priority=5)
    print(f"Đã xếp dịch lại metadata truyện #{novel_id} "
          f"({nv.get('title_vi') or nv.get('title_zh')}).")
    print("Translator đang chạy sẽ dịch lại trong vài giây; kiểm tra lại title_vi trong app/Supabase.")


def run_request(novel_id: int, up_to: int) -> None:
    """Bản service-role của RPC request_translation — test không cần app/đăng nhập."""
    rows = (
        db.sb().table("chapters").select("id, chapter_index")
        .eq("novel_id", novel_id).lte("chapter_index", up_to)
        .in_("translation_status", ["none", "failed"])
        .order("chapter_index").execute()
    ).data or []
    for r in rows:
        db.sb().table("chapters").update({"translation_status": "queued"}).eq("id", r["id"]).execute()
        db.enqueue("chapter", novel_id, chapter_id=r["id"], priority=50)
    print(f"Đã xếp hàng {len(rows)} chương (novel {novel_id}, tới chương {up_to}).")
    print("Chạy `python -m novelworker.main crawl` để tải nội dung gốc"
          " và `... translate` để dịch; theo dõi bảng chapters trong Supabase.")


def _chunks(seq: list, n: int):
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def run_redich(novel_id: int | None, engine: str = "hachimi") -> None:
    """Dịch LẠI chương đã done bằng engine khác (mặc định 'hachimi').

    Đổi translation_provider của truyện → engine (model=NULL để re-pin ở chương đầu),
    xoá job chương cũ, đặt chương done → queued rồi enqueue lại với priority NỀN (90 —
    không giành lượt với người đang đọc). `--novel <id>` để canary 1 truyện; bỏ trống =
    TẤT CẢ truyện. Chương có content_zh NULL sẽ được crawler backfill trước khi dịch."""
    q = db.sb().table("novels").select("id, title_zh, title_vi")
    if novel_id is not None:
        q = q.eq("id", novel_id)
    novels = q.execute().data or []
    if not novels:
        print("Không có truyện nào." if novel_id is None else f"Không thấy truyện #{novel_id}.")
        return
    total = 0
    for nv in novels:
        nid = nv["id"]
        db.sb().table("novels").update(
            {"translation_provider": engine, "translation_model": None}).eq("id", nid).execute()
        ids = [c["id"] for c in (
            db.sb().table("chapters").select("id")
            .eq("novel_id", nid).eq("translation_status", "done").execute()
        ).data or []]
        for batch in _chunks(ids, 500):
            db.sb().table("translation_jobs").delete().eq(
                "novel_id", nid).eq("type", "chapter").in_("chapter_id", batch).execute()
            db.sb().table("chapters").update(
                {"translation_status": "queued"}).in_("id", batch).execute()
            db.sb().table("translation_jobs").insert(
                [{"type": "chapter", "novel_id": nid, "chapter_id": cid, "priority": 90}
                 for cid in batch]).execute()
        total += len(ids)
        print(f"  nv{nid} {nv.get('title_vi') or nv.get('title_zh')}: {len(ids)} chương")
    print(f"\nĐã xếp {total} chương của {len(novels)} truyện dịch lại bằng '{engine}' "
          f"(priority nền 90). Theo dõi bảng chapters/translation_jobs trong Supabase.")


def main() -> None:
    parser = argparse.ArgumentParser(prog="novelworker")
    parser.add_argument("mode",
                        choices=["crawl", "translate", "request", "add", "cost", "audit", "quality", "meta", "redich"])
    parser.add_argument("--engine", default="hachimi", help="redich: engine dịch lại (mặc định hachimi)")
    parser.add_argument("--book-id", help="add: id truyện (số trong URL nguồn)")
    parser.add_argument("--source", default="shuhaige",
                        help="add: sources.name của nguồn crawl (mặc định shuhaige)")
    parser.add_argument("--novel", type=int, help="request: novels.id trong DB")
    parser.add_argument("--up-to", type=int, default=10, help="request: dịch tới chương N")
    parser.add_argument("--fix", action="store_true",
                        help="audit: xếp lại hàng đợi các chương hỏng để dịch lại")
    args = parser.parse_args()
    if args.mode == "cost":
        run_cost()
    elif args.mode == "quality":
        run_quality(args.novel)  # --novel <id> để chấm 1 truyện; bỏ trống = tất cả
    elif args.mode == "audit":
        run_audit(args.fix)
    elif args.mode == "meta":
        if args.novel is None:
            parser.error("meta cần --novel <id>")
        run_meta(args.novel)
    elif args.mode == "crawl":
        run_crawler()
    elif args.mode == "translate":
        translator_worker.run_forever()
    elif args.mode == "add":
        if not args.book_id:
            parser.error("add cần --book-id <id>")
        adapters = build_adapters()
        adapter = adapters.get(args.source)
        if not adapter:
            parser.error(f"--source phải là một trong: {', '.join(adapters) or '(không có nguồn enabled)'}")
        novel = sync.add_novel(adapter, args.book_id)
        print(f"Đã thêm truyện #{novel['id']} ({args.source}): {novel['title_zh']} — "
              f"dùng `request --novel {novel['id']} --up-to N` để xếp hàng dịch.")
    else:
        if args.novel is None:
            parser.error("request cần --novel <id>")
        run_request(args.novel, args.up_to)


if __name__ == "__main__":
    main()
