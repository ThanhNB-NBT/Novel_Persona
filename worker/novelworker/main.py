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
import random
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


def run_crawler() -> None:
    adapters = build_adapters()
    log.info("Crawler bắt đầu (%d nguồn: %s), chu kỳ discovery %d phút",
             len(adapters), ", ".join(adapters) or "—", settings.crawl_interval_min)
    sync.backfill_dedup_keys()  # gán dedup_key cho truyện cũ (1 lần, tự lành)
    last_discovery = 0.0
    interval_min = settings.crawl_interval_min
    max_new = settings.discover_new_per_cycle
    refresh_n = settings.refresh_per_cycle
    while True:
        now = time.time()
        db.heartbeat("crawler")  # điểm danh mỗi vòng 10s — app hiện sống/chết thật
        try:
            _reconcile_adapters(adapters)
        except Exception:
            # DB chập chờn không được làm rơi crawler; giữ adapter hiện tại và thử lại tick sau.
            log.exception("Không đồng bộ được trạng thái nguồn — tạm giữ cấu hình hiện tại")
        due = now - last_discovery > interval_min * 60
        if due:
            # config chỉnh từ app (worker_settings) — đọc lại mỗi chu kỳ, đổi là ăn ngay
            rs = db.runtime_settings()
            def _num(key: str, cur: int) -> int:
                try:
                    return max(1, int(rs.get(key, cur)))
                except (TypeError, ValueError):
                    return cur
            interval_min = _num("crawl_interval_min", interval_min)
            max_new = _num("discover_new_per_cycle", max_new)
            refresh_n = _num("refresh_per_cycle", refresh_n)
            settings.faloo_free_chapter_threshold = _num(
                "faloo_free_chapter_threshold", settings.faloo_free_chapter_threshold)
        enabled_source_ids = {
            a.source_row["id"] for a in adapters.values() if a.source_row.get("id") is not None
        }
        pending_fetch = _novels_needing_fetch(enabled_source_ids)
        # 0) yêu cầu truyện từ app: tìm tên trên các nguồn có search → crawl + vào tủ sách.
        # Chạy mỗi tick (user đang ngóng), 1 query khi không có yêu cầu nào.
        try:
            sync.process_novel_requests(list(adapters.values()))
        except Exception:
            log.exception("Lỗi xử lý yêu cầu truyện")
        for adapter in list(adapters.values()):
            try:
                # 1) tải nội dung chương đang chờ dịch — NGƯỜI ĐỌC TRƯỚC, chạy mỗi tick.
                # Discovery/refresh (bước 2, có thể cả tiếng) cũng tự nhường giữa chừng
                # khi có chương ưu tiên cao chờ tải (sync.reader_fetch_waiting).
                sid = adapter.source_row.get("id")
                # 0) mục lục lười: app xin tải mục lục đầy đủ (request_toc) — ưu tiên vì
                # user đang đứng chờ ở màn danh sách chương; tối đa 3 truyện/tick
                toc_reqs = (
                    db.sb().table("novels").select("id, source_id, source_novel_id")
                    .eq("source_id", sid).is_("toc_synced_at", "null")
                    .not_.is_("toc_requested_at", "null")
                    .order("toc_requested_at").limit(3).execute()
                ).data or []
                for nv in toc_reqs:
                    try:
                        total, n = sync.sync_chapter_list(adapter, nv["id"], nv["source_novel_id"])
                        log.info("TOC lười: novel %s đủ mục lục (%d chương, +%d stub)",
                                 nv["id"], total, n)
                    except Exception:
                        # gỡ cờ xin để không hammer mỗi tick; user mở lại truyện sẽ xin lại
                        db.sb().table("novels").update(
                            {"toc_requested_at": None}).eq("id", nv["id"]).execute()
                        log.exception("TOC lười: lỗi novel %s — gỡ cờ chờ xin lại", nv["id"])
                for nv in pending_fetch:
                    if nv["source_id"] != sid:
                        continue  # để adapter đúng nguồn xử lý ở vòng lặp của nó
                    # Mục lục chỉ cần sync khi có chương queued THIẾU stub nguồn (lần
                    # đầu user bấm Đọc, RPC tạo row trước khi TOC về). Trước đây fetch
                    # cả trang mục lục nguồn MỖI vòng 10s cho mọi truyện đang chờ dịch.
                    missing_stub = (
                        db.sb().table("chapters").select("id", count="exact")
                        .eq("novel_id", nv["id"]).eq("translation_status", "queued")
                        .is_("source_chapter_id", "null").limit(1).execute()
                    ).count or 0
                    if missing_stub:
                        sync.sync_chapter_list(adapter, nv["id"], nv["source_novel_id"])
                    sync.ensure_chapters_fetched(adapter, nv["id"])
                # 2) discovery + sync truyện được theo dõi — theo chu kỳ dài
                if due:
                    # Cào MỌI mục để truyện dày dần, không chỉ vét lại top cũ:
                    # - ranking (nếu có) → lưu source_rank cho "Đề cử"; chart /allvisit/
                    #   gần như bất động nên riêng nó cào đi cào lại vẫn mấy truyện đó.
                    # - "mới cập nhật" → thêm truyện mới ra (đủ >200 chương + qua lọc mới giữ,
                    #   nên không sợ truyện mỏng). Nguồn không có latest → fetch_latest trả [].
                    sync.discover_ranking(adapter, max_new=max_new)
                    sync.discover_latest(adapter, max_new=max_new)
                    # chen giữa các bước dài: yêu cầu truyện không phải đợi hết cả
                    # chu kỳ discovery (10-15 phút) mới được xử
                    sync.process_novel_requests(list(adapters.values()))
                    sync.sync_followed_novels(adapter)
                    # truyện đã có ra chương mới → nổi "Mới cập nhật" (không chỉ truyện mới)
                    sync.refresh_canonical_updates(adapter, limit=refresh_n)
                    sync.process_novel_requests(list(adapters.values()))
            except Exception:
                log.exception("Lỗi vòng crawl (%s)", adapter.name)
            finally:
                try:
                    if _eval_source_health(adapter):
                        # Nguồn vừa tự tắt: bỏ adapter ngay, không hammer tiếp tới vòng kế.
                        adapters.pop(adapter.name, None)
                except Exception:
                    log.exception("Không ghi được health nguồn %s", adapter.name)
        if due:
            last_discovery = now
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


def run_ab(novel_id: int | None, up_to: int, out_dir: str, *, parallel: bool = True,
           refetch: bool = False) -> None:
    """Chay hai bo prompt tren cung chuong, chi ghi file test, khong ghi DB."""
    from pathlib import Path

    from .translator.ab import compare_chapter, dumps, render_html
    from .translator.providers import build_chain

    if refetch and novel_id is None:
        candidates = (db.sb().table("chapters").select("novel_id")
                      .limit(max(500, up_to * 20)).execute().data or [])
        novel_ids = list({row["novel_id"] for row in candidates if row.get("novel_id")})
        if not novel_ids:
            raise RuntimeError("Khong tim thay truyen de refetch")
        novel_id = random.choice(novel_ids)
        print(f"AB refetch chon ngau nhien novel {novel_id}")
    if refetch:
        nv = (db.sb().table("novels").select("source_id,source_novel_id")
              .eq("id", novel_id).single().execute().data)
        source = (db.sb().table("sources").select("name")
                  .eq("id", nv["source_id"]).single().execute().data)
        adapter = build_adapters().get(source["name"])
        if not adapter:
            raise RuntimeError(f"Khong tim thay crawler dang bat cho source {source['name']}")
        sync.sync_chapter_list(adapter, novel_id, nv["source_novel_id"])
        missing = (db.sb().table("chapters").select("id,translation_status")
                   .eq("novel_id", novel_id).is_("content_zh", "null")
                   .order("chapter_index").limit(up_to).execute().data or [])
        if missing:
            ids = [row["id"] for row in missing]
            db.sb().table("chapters").update({"translation_status": "queued"}).in_("id", ids).execute()
            sync.ensure_chapters_fetched(adapter, novel_id)
            for row in missing:
                db.sb().table("chapters").update(
                    {"translation_status": row["translation_status"]}).eq("id", row["id"]).execute()
        print(f"AB refetch xong, da tai lai toi da {up_to} chuong cho novel {novel_id}")

    def load_chapters(book_id: int) -> list[dict]:
        return (db.sb().table("chapters")
                .select("id,novel_id,chapter_index,title_zh,content_zh,summary_vi,content_vi")
                .eq("novel_id", book_id)
                .not_.is_("content_zh", "null").order("chapter_index")
                .execute().data or [])

    rows: list[dict] = []
    if novel_id is None:
        candidates = (db.sb().table("chapters").select("novel_id,chapter_index")
                      .not_.is_("content_zh", "null")
                      .limit(max(500, up_to * 20)).execute().data or [])
        novel_ids = list({row["novel_id"] for row in candidates if row.get("novel_id")})
        random.shuffle(novel_ids)
        best_id: int | None = None
        best_rows: list[dict] = []
        for candidate in novel_ids:
            possible = load_chapters(candidate)
            if len(possible) > len(best_rows):
                best_id, best_rows = candidate, possible
            if len(possible) >= up_to:
                novel_id, rows = candidate, possible[:up_to]
                break
        if novel_id is None and best_id is not None:
            novel_id, rows = best_id, best_rows[:up_to]
        if novel_id is None:
            raise RuntimeError("Khong tim thay chuong nao co content_zh de chon ngau nhien")
        print(f"AB chon ngau nhien novel {novel_id}, co {len(rows)} chuong co content_zh")

    novel = db.sb().table("novels").select("id,title_vi,title_zh,genres").eq(
        "id", novel_id).single().execute().data
    if not rows:
        rows = load_chapters(novel_id)[:up_to]
    if not rows:
        raise RuntimeError(f"Khong co chuong co content_zh cho novel {novel_id}")

    terms, _ = db.get_glossary(novel_id)
    chains = (build_chain(0), build_chain(1), build_chain(2))
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    novel_line = novel.get("title_vi") or novel.get("title_zh")
    if novel_line and novel.get("genres"):
        novel_line += " — thể loại: " + ", ".join(novel["genres"])

    payloads = []
    for row in rows:
        previous = next((item for item in rows
                         if item["chapter_index"] == row["chapter_index"] - 1), None)
        payload = compare_chapter({
            **row,
            "novel_line": novel_line,
            "prev_summary": (previous or {}).get("summary_vi"),
            "prev_tail": (previous or {}).get("content_vi", "")[-1800:] or None,
        }, terms, chains, parallel=parallel)
        payloads.append(payload)
        target = out / f"n{novel_id}_c{row['chapter_index']}.json"
        target.write_text(dumps(payload), encoding="utf-8")
        print(f"AB xong n{novel_id} c{row['chapter_index']} -> {target}")

    (out / "index.html").write_text(
        render_html(payloads, f"A/B translation — novel {novel_id}"), encoding="utf-8")
    print(f"Da luu {len(rows)} cap ban dich vao {out.resolve()}")
    print(f"Mo viewer: {(out / 'index.html').resolve()}")


def main() -> None:
    parser = argparse.ArgumentParser(prog="novelworker")
    parser.add_argument("mode",
                        choices=["crawl", "translate", "request", "add", "cost", "audit", "quality", "meta", "ab"])
    parser.add_argument("--book-id", help="add: id truyện (số trong URL nguồn)")
    parser.add_argument("--source", default="shuhaige",
                        help="add: sources.name của nguồn crawl (mặc định shuhaige)")
    parser.add_argument("--novel", type=int, help="request: novels.id trong DB")
    parser.add_argument("--up-to", type=int, default=10, help="request: dịch tới chương N")
    parser.add_argument("--fix", action="store_true",
                        help="audit: xếp lại hàng đợi các chương hỏng để dịch lại")
    parser.add_argument("--out", default="ab_out", help="ab: thư mục lưu kết quả JSON")
    parser.add_argument("--serial", action="store_true", help="ab: chạy tuần tự thay vì song song")
    parser.add_argument("--refetch", action="store_true",
                        help="ab: tải lại content_zh cho các chương thiếu nguyên văn")
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
    elif args.mode == "ab":
        run_ab(args.novel, args.up_to, args.out, parallel=not args.serial, refetch=args.refetch)
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
