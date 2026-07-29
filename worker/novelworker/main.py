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
    python -m novelworker.main backfill --source ptwxz       # tải lại metadata truyện đã có (sau khi vá adapter)
    python -m novelworker.main gclean [--write]              # dọn gợi ý glossary là cụm tiếng Anh (chưa duyệt)
    python -m novelworker.main gfix [--write]                # term viết bằng pinyin → đổi về Hán-Việt
"""
from __future__ import annotations

import argparse
import collections
import logging
import os
import threading
import time
from datetime import datetime, timedelta, timezone

from . import db
from .config import settings
from .crawler.base import SourceAdapter
from .crawler.registry import TEMPLATE_REGISTRY
from .crawler import sync
from .translator import worker as translator_worker

_LOG_FMT = "%(asctime)s %(levelname)s %(name)s: %(message)s"
# LOG_FILE=<đường dẫn> → ghi thẳng ra file bằng UTF-8, KHÔNG đi qua console.
# Lý do (26/07): trên Windows, `python ... *>> worker.log` để PowerShell 5.1 giải mã đầu ra
# theo bảng mã console rồi mới ghi — dấu tiếng Việt hỏng ("NHß║¼N"), và cách hỏng đổi theo
# chcp nên không có câu lệnh nào chữa cho chắc. Docker/Linux không đặt biến này, giữ nguyên
# log ra stdout như cũ.
_log_file = os.getenv("LOG_FILE", "").strip()
logging.basicConfig(
    level=logging.INFO, format=_LOG_FMT,
    handlers=[logging.FileHandler(_log_file, encoding="utf-8")] if _log_file else None,
)
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
    """Novel cần tải bản gốc, đúng thứ tự ưu tiên của hàng dịch và chỉ từ nguồn đang bật.

    Lọc nằm trong RPC (migration 087), KHÔNG kéo job về Python rồi lọc: bản cũ lấy 200
    job đầu rồi mới bỏ những job có chương không ở 'queued', mà 587 job đầu hàng đợi đều
    như vậy — crawler thấy rỗng và ngừng tải suốt, dù 1377 chương đang chờ nội dung.
    """
    out: list[dict] = []
    for sid in enabled_source_ids:
        rows = db.sb().rpc("novels_needing_fetch", {"p_source_id": sid}).execute().data or []
        out += rows
    return out


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
        .lte("toc_requested_at", db.utc_now())
        .order("toc_requested_at").limit(3).execute()
    ).data or []
    for nv in toc_reqs:
        try:
            total, n = sync.sync_chapter_list(adapter, nv["id"], nv["source_novel_id"])
            log.info("TOC lười: novel %s đủ mục lục (%d chương, +%d stub)", nv["id"], total, n)
        except Exception:
            # Giữ yêu cầu qua lỗi tạm; dùng chính timestamp làm mốc retry để không thêm cột.
            retry_at = (datetime.now(timezone.utc) + timedelta(minutes=1)).isoformat()
            db.sb().table("novels").update(
                {"toc_requested_at": retry_at}, returning="minimal").eq("id", nv["id"]).execute()
            log.exception("TOC lười: lỗi novel %s — hẹn thử lại sau 1 phút", nv["id"])
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
        # chương 'failed' vì nguồn đánh lại id → hồi sinh (không thì kẹt vĩnh viễn)
        sync.revive_stale_failed_chapters(adapter)


def _source_loop(adapter: SourceAdapter, stop: threading.Event, cfg: dict) -> None:
    """Luồng crawl riêng một nguồn: tự cadence discovery, tự đo sức khoẻ. Tự tắt nguồn
    (toàn fetch fail nhiều chu kỳ) → thoát luồng; coordinator reconcile sẽ gỡ khỏi vòng."""
    sid = adapter.source_row.get("id")
    # Lấy mốc bền từ frontier: restart không làm chu kỳ dài đếm lại từ đầu. Nguồn mới
    # chưa có frontier trả 0 → discovery ngay; lỗi đọc DB thì giữ hành vi an toàn cũ.
    try:
        last_discovery = db.last_discovery_at(sid) if sid is not None else time.time()
    except Exception:
        last_discovery = time.time()
        log.warning("Không đọc được mốc discovery nguồn %s — tính chu kỳ từ lúc khởi động",
                    adapter.name)
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
    from .translator.termguard import _LEAK
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

    # n, sum_len, sum_adh, dup, no_para, han_bad, leak
    agg: dict[str, list[float]] = defaultdict(lambda: [0, 0.0, 0.0, 0, 0, 0, 0])
    bad: list[tuple[float, str]] = []
    for c in rows:
        zh, vi = c.get("content_zh") or "", c.get("content_vi") or ""
        if not vi:
            continue
        han = han_ratio(vi)
        len_ratio = len(vi) / max(len(zh), 1)
        dup = len(DUP_PHRASE.findall(vi))
        lost_para = 1 if (zh.count("\n") >= 5 and vi.count("\n") == 0) else 0
        # mảnh mã termguard lọt ra bản dịch — rác người đọc thấy tận mắt, luôn là lỗi nặng
        leak = 1 if _LEAK.search(vi) else 0
        ok, appl = _glossary_adherence(zh, vi, gloss(c["novel_id"]))
        adh = ok / appl if appl else 1.0

        a = agg[c.get("model_used") or "(?)"]
        a[0] += 1; a[1] += len_ratio; a[2] += adh
        a[3] += dup; a[4] += lost_para; a[5] += 1 if han > 0.02 else 0; a[6] += leak

        # điểm "tệ" gộp để xếp chương cần soi (cao = tệ). zh→vi tính KÝ TỰ nên ~2.5-3.5x
        # là BÌNH THƯỜNG; chỉ cờ khi <1.5x (cụt) hoặc >5x (phình/lặp).
        score = (han * 100) + max(0, 1.5 - len_ratio) * 20 + (len_ratio > 5.0) * 20 + \
                (1 - adh) * 30 + dup * 10 + lost_para * 30 + leak * 50
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
            if leak: reasons.append(f"mã sót '{_LEAK.search(vi).group(0)}'")
            bad.append((score, f"  nv{c['novel_id']} ch{c['chapter_index']} {title}: {', '.join(reasons)}"))

    print(f"Đã chấm {len(rows)} chương done.\n")
    print(f"{'model':<40}{'chương':>7}{'len TB':>8}{'glossary':>9}{'lặp':>6}{'mất đoạn':>9}{'còn Hán':>8}{'mã sót':>8}")
    print("-" * 95)
    for m, a in sorted(agg.items(), key=lambda kv: -kv[1][0]):
        n = int(a[0]) or 1
        print(f"{m[:40]:<40}{int(a[0]):>7}{a[1]/n:>8.2f}{a[2]/n*100:>8.0f}%{int(a[3]):>6}{int(a[4]):>9}{int(a[5]):>8}{int(a[6]):>8}")
    print("\nGhi chú: len TB ~2.5-3.5 là bình thường (zh→vi tính KÝ TỰ); "
          "glossary nên ~100%; lặp cụm/mất đoạn/còn Hán/mã sót nên 0.")
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


def run_backfill(source: str, dry: bool = True, limit: int | None = None) -> None:
    """Tải lại metadata từ nguồn cho truyện ĐÃ có trong kho — dùng khi adapter được vá và
    các trường trước đó bị bỏ trống (ptwxz 2026-07-28: thiếu genres/description/status nên
    bộ lọc thể loại chưa từng chặn được truyện nào của nguồn này).

    Chỉ ghi đè trường đang RỖNG, trừ `status` (adapter cũ hardcode 'ongoing' nên giá trị cũ
    không đáng tin). Hai mức xử lý truyện lọt lưới:
      * VI PHẠM thể loại cấm → XOÁ; trigger novels_delete_blacklist ghi crawl_blacklist
        nên discovery không crawl lại (migration 032).
      * KHÔNG ĐẠT (đang ra, dưới `discover_min_chapters`) → chỉ ẩn, chờ đủ chương thì
        _maybe_unhide_grown tự hiện lại.
    Truyện đã dịch meta mà giờ mới có mô tả/thể loại → xếp lại job metadata để dịch bổ sung.
    ponytail: chạy tuần tự + sleep 1s, vài trăm truyện là đủ; cần nhanh hơn thì mới song song."""
    adapter = build_adapters().get(source)
    if not adapter:
        print(f"Nguồn '{source}' không enabled hoặc không có adapter.")
        return
    sid = adapter.source_row["id"]
    q = (db.sb().table("novels")
         .select("id, source_novel_id, genres, description_zh, status, author_zh, hidden, "
                 "meta_translated, chapter_count_source, title_zh")
         .eq("source_id", sid).order("id"))
    rows = (q.limit(limit).execute() if limit else q.execute()).data or []
    print(f"{source}: {len(rows)} truyện" + (" — CHẠY THỬ, không ghi DB" if dry else ""))
    n_fix = n_hide = n_del = n_err = 0
    for i, nv in enumerate(rows, 1):
        try:
            meta = adapter.fetch_novel_meta(nv["source_novel_id"])
        except Exception as e:
            n_err += 1
            print(f"  [{i}] #{nv['id']} LỖI: {e}")
            continue
        blocked = sync.genre_blocked(meta)
        if blocked:
            # VI PHẠM → xoá hẳn. Trigger tự blacklist theo source_novel_id + dedup_key.
            n_del += 1
            print(f"  [{i}] #{nv['id']} {meta.title_zh}: XOÁ — thể loại cấm '{blocked}'")
            if not dry:
                db.sb().table("novels").delete(returning="minimal").eq("id", nv["id"]).execute()
                time.sleep(1.0)
            continue
        patch: dict = {}
        # KHÔNG ĐẠT: đang ra mà chưa đủ chương → ẩn (cùng ngưỡng với lọc discovery)
        thin = (meta.status != "completed"
                and (meta.chapter_count or nv.get("chapter_count_source") or 0)
                < settings.discover_min_chapters)
        if thin and not nv.get("hidden"):
            patch["hidden"] = True
        if meta.genres_zh and not nv.get("genres"):
            patch["genres"] = meta.genres_zh
        if meta.description_zh and not nv.get("description_zh"):
            patch["description_zh"] = meta.description_zh
        if meta.author_zh and not nv.get("author_zh"):
            patch["author_zh"] = meta.author_zh
        if meta.status != nv.get("status"):
            patch["status"] = meta.status
        if not patch:
            continue
        n_fix += 1
        n_hide += bool(patch.get("hidden"))
        print(f"  [{i}] #{nv['id']} {meta.title_zh}: {patch}" + ("  ← ẨN: chưa đủ chương" if thin else ""))
        if dry:
            continue
        patch["updated_at"] = db.utc_now()
        db.sb().table("novels").update(patch, returning="minimal").eq("id", nv["id"]).execute()
        # đã dịch meta từ trước + vừa có thêm mô tả/thể loại zh → dịch lại cho khớp
        if nv.get("meta_translated") and (
                "description_zh" in patch or "genres" in patch):
            db.sb().table("translation_jobs").delete().eq(
                "novel_id", nv["id"]).eq("type", "metadata").execute()
            db.enqueue("metadata", nv["id"], priority=20)
        time.sleep(1.0)  # lịch sự với nguồn
    print(f"Xong: {n_del} XOÁ (thể loại cấm), {n_fix} sửa metadata ({n_hide} ẩn vì thiếu chương), "
          f"{n_err} lỗi tải." + ("  Thêm --write để ghi thật." if dry else ""))


def run_gclean(dry: bool = True) -> None:
    """Xoá gợi ý glossary là cụm tiếng Anh dịch nghĩa (rác model trích tên 25-26/07/2026).
    Worker đã tự rà term MỚI mỗi chu kỳ audit; lệnh này quét CẢ KHO, dùng sau khi sửa luật.

    CHỈ đụng term chưa duyệt, và đây là ranh giới cứng — không mở cờ cho term đã duyệt.
    Đo 28/07/2026: cả kho chỉ có 520 term approved (70 do user tạo tay), KHÔNG có đợt
    LLM tự duyệt hàng loạt như tưởng; lần thử mở sang approved chỉ xoá đúng 3 term
    curated ("Goblin da xanh", "Virus zombie", "First Blood") rồi phải khôi phục tay.
    Term đã duyệt = đã có người chốt, và nó ĐANG nằm trong prompt dịch — heuristic
    không được quyền đụng."""
    _, bad = db.sweep_glossary(dry=dry, fix=False)
    per = collections.Counter(t["novel_id"] for t in bad)
    print(f"{len(bad)} gợi ý là cụm tiếng Anh" + (" (CHẠY THỬ)" if dry else ""))
    for t in bad[:15]:
        print(f"  {t['term_zh']} -> {t['correct_vi']} | {t['term_type']}")
    if len(bad) > 15:
        print(f"  ... còn {len(bad) - 15} dòng")
    if per:
        print("Truyện dính nhiều nhất:", ", ".join(f"#{n}={c}" for n, c in per.most_common(8)))
    print("Thêm --write để xoá thật." if dry else f"Đã xoá {len(bad)} gợi ý.")


def run_gfix(dry: bool = True) -> None:
    """Term đang bị viết bằng PINYIN → đổi về Hán-Việt (仓库 "Cangku" → "Thương Khố").
    Sửa tại chỗ, KHÔNG xoá — bản cũ ghi vào `wrong_vi` để prompt biết mà tránh và job
    patch vá được chương đã dịch. Worker đã tự rà term MỚI mỗi chu kỳ audit; lệnh này
    quét CẢ KHO, dùng sau khi sửa luật để áp lại lên dữ liệu cũ."""
    fixed, _ = db.sweep_glossary(dry=dry, clean=False)
    print(f"{len(fixed)} term đang viết bằng pinyin" + (" (CHẠY THỬ)" if dry else ""))
    for t in fixed[:20]:
        print(f"  {t['term_zh']} : {t['correct_vi']} → {t['new_vi']}   ({t['term_type']})")
    if len(fixed) > 20:
        print(f"  ... còn {len(fixed) - 20} dòng")
    print("Thêm --write để sửa thật." if dry else f"Đã sửa {len(fixed)} term.")


def run_request(novel_id: int, up_to: int) -> None:
    """Bản service-role của RPC request_translation — test không cần app/đăng nhập."""
    rows = (
        db.sb().table("chapters").select("id, chapter_index")
        .eq("novel_id", novel_id).lte("chapter_index", up_to)
        .in_("translation_status", ["none", "failed"])
        .order("chapter_index").execute()
    ).data or []
    for r in rows:
        db.sb().table("chapters").update({"translation_status": "queued"}, returning="minimal").eq("id", r["id"]).execute()
        db.enqueue("chapter", novel_id, chapter_id=r["id"], priority=50)
    print(f"Đã xếp hàng {len(rows)} chương (novel {novel_id}, tới chương {up_to}).")
    print("Chạy `python -m novelworker.main crawl` để tải nội dung gốc"
          " và `... translate` để dịch; theo dõi bảng chapters trong Supabase.")


def _chunks(seq: list, n: int):
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def run_redich(novel_id: int | None, engine: str = "hachimi",
               priority: int = 70) -> None:
    """Dịch LẠI chương đã done bằng engine khác (mặc định 'hachimi').

    Đổi translation_provider của truyện → engine (model=NULL để re-pin ở chương đầu),
    xoá job chương cũ, đặt chương done → queued rồi enqueue lại. `--novel <id>` để canary
    1 truyện; bỏ trống = TẤT CẢ truyện. Chương có content_zh NULL sẽ được crawler backfill
    trước khi dịch.

    priority mặc định 70: dưới người đang đọc (5) và tủ sách (30), TRÊN chương đọc thử
    (75) — dịch lại kho là việc chính, không nên xếp sau hàng nghìn chương mẫu của truyện
    chưa ai đọc. Đặt 90 nếu muốn nó chạy nền đúng nghĩa."""
    # nhiều chương trước: job cùng priority xếp theo thứ tự chèn, nên enqueue truyện
    # dày trước là nó được dịch trước.
    q = db.sb().table("novels").select("id, title_zh, title_vi") \
        .order("chapter_count_translated", desc=True)
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
            {"translation_provider": engine, "translation_model": None}, returning="minimal").eq("id", nid).execute()
        ids = [c["id"] for c in (
            db.sb().table("chapters").select("id")
            .eq("novel_id", nid).eq("translation_status", "done").execute()
        ).data or []]
        for batch in _chunks(ids, 500):
            db.sb().table("translation_jobs").delete().eq(
                "novel_id", nid).eq("type", "chapter").in_("chapter_id", batch).execute()
            db.sb().table("chapters").update(
                {"translation_status": "queued"}, returning="minimal").in_("id", batch).execute()
            db.sb().table("translation_jobs").insert(
                [{"type": "chapter", "novel_id": nid, "chapter_id": cid, "priority": priority}
                 for cid in batch], returning="minimal").execute()
        total += len(ids)
        print(f"  nv{nid} {nv.get('title_vi') or nv.get('title_zh')}: {len(ids)} chương")
    print(f"\nĐã xếp {total} chương của {len(novels)} truyện dịch lại bằng '{engine}' "
          f"(priority nền 90). Theo dõi bảng chapters/translation_jobs trong Supabase.")


def run_redich_leaked(priority: int = 70, dry: bool = True) -> None:
    """Xếp dịch lại ĐÚNG những chương còn mảnh mã termguard (bug 26/07).

    `redich --novel N` xếp cả truyện; lỗi này chỉ dính lác đác vài chương rải nhiều truyện
    nên quét theo dấu vết rồi nhặt từng chương. Không đổi engine của truyện — lỗi nằm ở
    termguard, không phải ở model."""
    from .translator.termguard import _LEAK

    dirty: list[dict] = []
    frm = 0
    while True:
        rows = (db.sb().table("chapters")
                .select("id, novel_id, chapter_index, content_vi")
                .eq("translation_status", "done").not_.is_("content_vi", "null")
                .range(frm, frm + 299).execute().data or [])
        dirty += [r for r in rows if _LEAK.search(r["content_vi"] or "")]
        if len(rows) < 300:
            break
        frm += 300
        print(f"  ...đã quét {frm} chương, thấy {len(dirty)} dính", end="\r")

    novels = {r["novel_id"] for r in dirty}
    print(f"\n{len(dirty)} chương dính mã sót trên {len(novels)} truyện.")
    for r in dirty[:20]:
        sample = _LEAK.search(r["content_vi"]).group(0)
        print(f"  nv{r['novel_id']} ch{r['chapter_index']}: {sample!r}")
    if dry:
        print("\nChạy thử — thêm --write để xếp hàng dịch lại.")
        return
    ids = [r["id"] for r in dirty]
    for batch in _chunks(ids, 500):
        db.sb().table("translation_jobs").delete().eq(
            "type", "chapter").in_("chapter_id", batch).execute()
        db.sb().table("chapters").update({"translation_status": "queued"}, returning="minimal").in_("id", batch).execute()
        db.sb().table("translation_jobs").insert(
            [{"type": "chapter", "novel_id": r["novel_id"], "chapter_id": r["id"],
              "priority": priority} for r in dirty if r["id"] in set(batch)], returning="minimal").execute()
    print(f"Đã xếp lại {len(ids)} chương (priority {priority}).")


def main() -> None:
    parser = argparse.ArgumentParser(prog="novelworker")
    parser.add_argument("mode",
                        choices=["crawl", "translate", "request", "add", "cost", "audit", "quality",
                                 "meta", "redich", "backfill", "gclean", "gfix"])
    parser.add_argument("--engine", default="hachimi", help="redich: engine dịch lại (mặc định hachimi)")
    parser.add_argument("--priority", type=int, default=70,
                        help="redich: priority job (nhỏ = dịch trước; 70 = trên chương đọc thử)")
    parser.add_argument("--leaked", action="store_true",
                        help="redich: chỉ nhặt chương còn mảnh mã termguard (mặc định chạy thử)")
    parser.add_argument("--write", action="store_true",
                        help="redich --leaked / backfill: ghi DB thật (mặc định chạy thử)")
    parser.add_argument("--limit", type=int, help="backfill: chỉ xử lý N truyện đầu")
    parser.add_argument("--book-id", help="add: id truyện (số trong URL nguồn)")
    parser.add_argument("--source", default="shuhaige",
                        help="add/backfill: sources.name của nguồn (mặc định shuhaige)")
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
    elif args.mode == "gfix":
        run_gfix(dry=not args.write)
    elif args.mode == "gclean":
        run_gclean(dry=not args.write)
    elif args.mode == "backfill":
        run_backfill(args.source, dry=not args.write, limit=args.limit)
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
    elif args.mode == "redich":
        if args.leaked:
            run_redich_leaked(args.priority, dry=not args.write)
        else:
            run_redich(args.novel, args.engine, args.priority)  # bỏ --novel = tất cả truyện
    else:
        if args.novel is None:
            parser.error("request cần --novel <id>")
        run_request(args.novel, args.up_to)


if __name__ == "__main__":
    main()
