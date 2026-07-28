"""E2E CHẠM MẠNG THẬT: mọi nguồn đang bật phải đi trọn latest → meta → mục lục → chương.

Khác các self-check còn lại (HTML giả, chạy mọi lúc): file này gọi ra Internet nên
KHÔNG chạy mặc định — nguồn TQ chập chờn, để nó trong CI thì PR đỏ vì lý do chẳng
liên quan gì tới thay đổi của bạn.

    RUN_E2E=1 python test/test_e2e_sources.py            # tất cả nguồn đang bật
    RUN_E2E=1 python test/test_e2e_sources.py 69shuba    # chỉ 1 nguồn

Chạy khi: thêm/sửa adapter, trước lúc deploy, hoặc khi nghi một nguồn đã đổi HTML.
Đọc cấu hình TỪ BẢNG sources để test đúng cái production chạy, không phải bản sao chép tay.
"""
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

HAN = re.compile(r"[一-鿿]")
# Rác tuyệt đối không được có trong text đã bóc.
CAM = ("<div", "<br", "<script", "&nbsp;", "&emsp;", "loadAdv",
       "上一章", "下一章", "返回目录", "手机阅读")
MIN_CHUONG = 100      # ký tự; chương ngắn có thật (lời tác giả) nên để ngưỡng thấp
MIN_MUC_LUC = 5


def kiem_tra_chuong(nguon: str, scid: str, text: str) -> None:
    assert len(text) >= MIN_CHUONG, f"[{nguon}] chương {scid} chỉ {len(text)} ký tự"
    for k in CAM:
        assert k not in text, f"[{nguon}] chương {scid} còn sót {k!r}"
    ratio = len(HAN.findall(text)) / len(text)
    assert ratio > 0.5, f"[{nguon}] chương {scid} tỷ lệ chữ Hán chỉ {ratio:.0%} — bóc trượt?"


def kiem_tra_nguon(name: str, adapter) -> dict:
    t0 = time.time()
    latest = adapter.fetch_latest(limit=5)
    assert latest, f"[{name}] fetch_latest rỗng"
    assert all(m.source_novel_id and m.title_zh for m in latest), \
        f"[{name}] có mục thiếu id/tựa: {[(m.source_novel_id, m.title_zh) for m in latest]}"
    assert len({m.source_novel_id for m in latest}) == len(latest), \
        f"[{name}] fetch_latest trả trùng id"

    bid = latest[0].source_novel_id
    meta = adapter.fetch_novel_meta(bid)
    assert meta.title_zh, f"[{name}] meta thiếu tựa"
    assert meta.status in ("ongoing", "completed", "hiatus"), f"[{name}] status lạ: {meta.status}"
    assert meta.source_url.startswith("http"), f"[{name}] source_url không phải URL"

    refs = adapter.fetch_chapter_list(bid)
    assert len(refs) >= MIN_MUC_LUC, f"[{name}] mục lục chỉ {len(refs)} chương"
    assert [r.index for r in refs] == list(range(1, len(refs) + 1)), \
        f"[{name}] index mục lục không liên tục 1..N"
    assert len({r.source_chapter_id for r in refs}) == len(refs), \
        f"[{name}] mục lục có source_chapter_id trùng"

    # đầu / giữa / cuối — cuối hay là chương mới nhất, dễ lộ đổi cấu trúc nhất
    for ref in (refs[0], refs[len(refs) // 2], refs[-1]):
        kiem_tra_chuong(name, ref.source_chapter_id, adapter.fetch_chapter(ref.source_chapter_id))
        time.sleep(0.4)  # lịch sự với nguồn

    return {"latest": len(latest), "toc": len(refs), "giay": round(time.time() - t0, 1)}


def main() -> int:
    if os.environ.get("RUN_E2E") != "1":
        print("BỎ QUA e2e (chạm mạng thật) — đặt RUN_E2E=1 để chạy")
        return 0
    from novelworker import db
    from novelworker.crawler.registry import TEMPLATE_REGISTRY

    only = set(sys.argv[1:])
    rows = db.sb().table("sources").select("*").eq("enabled", True).order("name").execute().data
    rows = [r for r in rows or [] if not only or r["name"] in only]
    assert rows, "Không có nguồn enabled nào để test"

    ok, loi = {}, {}
    for r in rows:
        cls = TEMPLATE_REGISTRY.get(r.get("template") or "")
        if not cls:
            loi[r["name"]] = f"template '{r.get('template')}' chưa có adapter"
            continue
        adapter = cls(base_url=r["base_url"], config=r.get("config") or {}, source_row=r)
        try:
            ok[r["name"]] = kiem_tra_nguon(r["name"], adapter)
            print(f"  ✔ {r['name']:10} {ok[r['name']]}")
        except Exception as e:
            loi[r["name"]] = f"{type(e).__name__}: {str(e)[:160]}"
            print(f"  ✘ {r['name']:10} {loi[r['name']]}")

    print(f"\n{len(ok)} nguồn đạt / {len(loi)} trượt")
    if loi:
        for n, e in loi.items():
            print(f"  TRƯỢT {n}: {e}")
        return 1
    return 0


if __name__ == "__main__":
    code = main()
    print("OK — e2e sources pass" if code == 0 else "FAIL — e2e sources")
    raise SystemExit(code)
