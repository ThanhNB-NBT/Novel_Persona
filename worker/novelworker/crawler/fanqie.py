"""Adapter FANQIE (fanqienovel.com, 番茄小说 — ByteDance).

Khác hoàn toàn các khuôn HTML biquge: mọi dữ liệu nằm trong JSON nhúng
`window.__INITIAL_STATE__` của trang truyện/trang đọc.

  * Metadata + mục lục: /page/{book_id} → state.page có bookName/author/abstract/
    thumbUrl/categoryV2/itemIds… `itemIds` xếp MỚI-NHẤT-TRƯỚC (lastChapterItemId
    trùng phần tử đầu) → đảo lại thành thứ tự chương 1→N.
  * Nội dung chương: /reader/{chapter_id} → state."content" là HTML <p> xen ký tự
    PUA mã hóa font (0xE000–0xF8FF). Decode bằng BẢNG TĨNH `fanqie_charset.json`
    (xây trước bằng so-khớp glyph với Noto Sans SC, xem docs/crawl-multisource.md).
    Font woff2 là TOÀN CỤC dùng chung mọi sách (đã xác nhận 2 sách khác nhau cùng
    1 URL) nên bảng tĩnh đủ dùng; nếu ByteDance đổi font, URL khác mốc đã lưu →
    log cảnh báo để người vận hành build lại bảng (script builder trong docs).

Discovery: trang chủ/ranking JS-render phần lớn, nhưng /rank/1 và /rank/0 là
SERVER-RENDER (~10 truyện/bảng, tên cũng mã hóa PUA) → fetch_ranking đọc 2 bảng đó
làm pool khám phá; không có search → thêm truyện tay vẫn bằng
`add --source fanqie --book-id <id từ URL /page/{id}>`. Không VIP: chỉ chương free.
"""
from __future__ import annotations

import json
import logging
import re
from html import unescape
from pathlib import Path

from .base import ChapterRef, NovelMeta, SourceAdapter

log = logging.getLogger(__name__)

_CHARSET_PATH = Path(__file__).with_name("fanqie_charset.json")
_STATE_RE = re.compile(r"window\.__INITIAL_STATE__\s*=\s*")
_UNDEFINED_RE = re.compile(r"\bundefined\b")
def _as_int(v: object) -> int | None:
    """API fanqie trả số dưới dạng CHUỖI ("1", "84303"). Ép về int để so sánh và lưu
    đúng kiểu; giá trị lạ → None thay vì nổ."""
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return None


def normalize_cover_url(raw: object) -> str | None:
    """Đưa URL bìa fanqie về host KHÔNG ký, bỏ chữ ký.

    ByteDance chặn hẳn host ký (`*-novel-sign`) từ khoảng 24/8/2026: trả
    403 ACCESS DENIED kể cả khi `x-expires` còn hạn, kể cả từ mạng khác (đã thử
    bằng 4G trên máy khác IP). Host KHÔNG ký p1/p3/p6 vẫn phục vụ ảnh bình thường
    (đo 6/6 ảnh ngẫu nhiên, cả từ worker trên box) và không có `x-expires` nên bìa
    không tự chết theo đồng hồ như trước.

    Mã cũ ép mọi host về p9 vì hồi đó p9 ổn định nhất; giờ p9 chết CẢ hai kiểu
    (p9-novel-sign 403, p9-novel cũng 403) nên chính dòng đó làm hỏng toàn bộ bìa.
    """
    if not raw:
        return None
    url = re.sub(r"//p\d+-novel(-sign)?\.", "//p3-novel.", str(raw))
    return url.split("?", 1)[0] or None


_FONT_URL_RE = re.compile(r"url\((https://[^)\"]+\.woff2)")
_TITLE_RE = re.compile(r"<h1[^>]*muye-reader-title[^>]*>(.*?)</h1>", re.S)
_DEFAULT_AD_MARKERS = ["番茄小说", "扫码下载", "SVIP", "APP免费读", "免费阅读全本",
                       "会员登录后", "小说免费阅读全文", "下载番茄小说APP"]


class FanqieAdapter(SourceAdapter):
    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        # Bảng PUA→Hán nạp 1 lần/instance (file ~10KB); thiếu file → mọi fetch_chapter fail rõ ràng.
        data = json.loads(_CHARSET_PATH.read_text(encoding="utf-8"))
        self._translate = str.maketrans(
            {chr(int(k, 16)): v for k, v in data["table"].items()})
        self._known_font_url = data.get("font_url", "")
        self._font_warned = False
        self._dir_cache: tuple[str, dict] | None = None

    # ---------- helpers ----------

    def _api(self, path: str) -> dict:
        """GET một API JSON của fanqie, trả `data`. Ném ValueError nếu code != 0."""
        obj = json.loads(self._get(path))
        if obj.get("code") not in (0, "0"):
            raise ValueError(f"{self.name}: API {path} trả code={obj.get('code')} "
                             f"msg={str(obj.get('message'))[:80]}")
        data = obj.get("data")
        if not isinstance(data, dict):
            raise ValueError(f"{self.name}: API {path} không có data dict")
        return data

    def _directory(self, bid: str) -> dict:
        """Mục lục. Nhớ lại kết quả cho ĐÚNG bookId vừa hỏi: fetch_novel_meta và
        fetch_chapter_list thường được gọi liền nhau cho cùng một truyện, cache 1 ô
        là đủ tiết kiệm một request mà không phình bộ nhớ trong lượt crawl dài."""
        if self._dir_cache and self._dir_cache[0] == bid:
            return self._dir_cache[1]
        data = self._api(f"/api/reader/directory/detail?bookId={bid}")
        self._dir_cache = (bid, data)
        return data

    def _check_font(self, html: str) -> None:
        """Font woff2 đổi URL = ByteDance rebuild bảng mã → bảng tĩnh sẽ decode sai.
        Cảnh báo 1 lần để kịp build lại (bảng cũ vẫn chạy, PUA sót bị audit bắt)."""
        if self._font_warned or not self._known_font_url:
            return
        m = _FONT_URL_RE.search(html)
        url = m.group(1) if m else ""
        # URL có biến thể CDN host (lf3-/lf6-) + hậu tố -500/-700 (weight) — so phần hash
        if url and url.rsplit("/", 1)[-1].split("-")[0] != \
                self._known_font_url.rsplit("/", 1)[-1].split("-")[0]:
            self._font_warned = True
            log.warning(
                "%s: font fanqie ĐỔI (%s ≠ %s) — bảng PUA tĩnh có thể sai, cần build lại!",
                self.name, url, self._known_font_url)

    @staticmethod
    def _find_content_html(state: dict) -> str | None:
        """Duyệt state tìm trường 'content' dạng chuỗi HTML (<p>…) — vị trí thay đổi
        theo phiên bản site nên duyệt rộng hơn là neo cứng đường dẫn."""
        stack = [state]
        while stack:
            cur = stack.pop()
            if isinstance(cur, dict):
                for k, v in cur.items():
                    if k == "content" and isinstance(v, str) and "<p" in v:
                        return v
                    stack.append(v)
            elif isinstance(cur, list):
                stack.extend(cur)
        return None

    def _decode_content(self, content_html: str) -> str:
        text = unescape(content_html)
        text = re.sub(r"</p\s*>|<br\s*/?>", "\n", text, flags=re.I)
        text = re.sub(r"<[^>]+>", "", text)
        text = text.translate(self._translate)
        markers = [k.lower() for k in (
            self.config.get("ad_markers") or _DEFAULT_AD_MARKERS)]
        lines = []
        seen_promo_tail = False
        for ln in (ln.strip() for ln in text.split("\n")):
            low = ln.lower()
            if any(k in low for k in markers):
                seen_promo_tail = True  # quảng cáo thường chen CUỐI chương → cắt luôn phần sau
                continue
            if seen_promo_tail and not ln:
                continue
            if seen_promo_tail:
                break
            if ln:
                lines.append(ln)
        return "\n".join(lines).strip()

    # ---------- SourceAdapter ----------

    def fetch_latest(self, limit: int = 30, page: int | None = None) -> list[NovelMeta]:
        """Feed 'MỚI CẬP NHẬT' TOÀN NỀN TẢNG qua /api/rank/recent/update/list —
        phân trang vô hạn (page_index), mỗi mục = 1 chương vừa cập nhật kèm bookId/
        tên/thể loại/tác giả/updateTime. Đây là mỏ discovery chính của fanqie: mọi
        sách đang ra chương đều chảy qua đây, không giới hạn như bảng rank.
        Trả metadata đầy đủ luôn (API cho sẵn) → discovery khỏi fetch_novel_meta lại."""
        page_index = (page or 1) - 1
        try:
            data = json.loads(self._get(
                f"/api/rank/recent/update/list?page_count={limit}&page_index={page_index}"))
        except Exception:
            log.warning("%s: không lấy được feed mới cập nhật", self.name)
            return []
        out: dict[str, NovelMeta] = {}
        for item in ((data.get("data") or {}).get("data") or []):
            bid = str(item.get("bookId") or "")
            title = (item.get("bookName") or "").strip()
            if not bid or not 2 <= len(title) <= 60 or bid in out:
                continue
            last_at = None
            ts = str(item.get("updateTime") or "")
            if ts.isdigit():
                from datetime import datetime, timezone
                last_at = datetime.fromtimestamp(int(ts), tz=timezone.utc)
            cat = (item.get("category") or "").strip()
            out[bid] = NovelMeta(
                source_novel_id=bid,
                source_url=f"{self.base_url}/page/{bid}",
                title_zh=title,
                author_zh=item.get("author"),
                genres_zh=[cat] if cat else [],
                last_chapter_at=last_at,
            )
        return list(out.values())[:limit]

    def fetch_ranking(self, limit: int = 100) -> list[tuple[str, int]]:
        """Discovery fanqie — 2 tầng:
        1. API nội bộ web `/api/rank/list?type={0,1,2}`: JSON sạch, tên KHÔNG mã hóa
           (mỗi type một bảng ~7-10 sách; type ≥3 rỗng). Ưu tiên vì dữ liệu giàu.
        2. HTML server-render `/rank/{0,1,2}` + trang chủ: tên mã hóa PUA → decode
           bằng bảng tĩnh; dùng bù những sách API không có.
        Trần thật của web ẩn danh ~48 truyện độc lập/đợt (đã đếm thực tế 2026-08-23);
        sâu hơn cần API di động có ký số — không đáng."""
        out: dict[str, NovelMeta] = {}

        def _add(bid: str, title: str) -> None:
            title = title.strip()
            if bid and bid not in out and 2 <= len(title) <= 60:
                out[bid] = NovelMeta(
                    source_novel_id=bid,
                    source_url=f"{self.base_url}/page/{bid}",
                    title_zh=title,
                )

        for t in range(3):
            try:
                data = json.loads(self._get(f"/api/rank/list?type={t}"))
                for b in ((data.get("data") or {}).get("list") or []):
                    _add(str(b.get("bookId") or ""), b.get("bookName") or "")
            except Exception:
                log.warning("%s: không lấy được api/rank/list type=%s", self.name, t)
        for path in ("/rank/1", "/rank/0", "/rank/2", "/"):
            try:
                html = self._get(path)
            except Exception:
                log.warning("%s: không lấy được ranking %s", self.name, path)
                continue
            for bid, raw_title in re.findall(
                    r'href="/page/(\d+)"[^>]*>([^<]{2,60})</a>', html):
                _add(bid, unescape(raw_title).translate(self._translate))
        return [(m.source_novel_id, i) for i, m in enumerate(out.values())][:limit]

    def fetch_novel_meta(self, source_novel_id: str) -> NovelMeta:
        # ĐỔI TỪ /page/{id} SANG API JSON (2026-09-03): fanqie biến /page/ thành
        # endpoint cần ký — trả HTTP 200 content-type json mà body 0 byte. Đo 8 lượt:
        # /page/ 0/8, /api/book/info 8/8, /api/reader/directory/detail 8/8.
        p = self._api(f"/api/book/info?bookId={source_novel_id}")
        title = (p.get("bookName") or "").strip()
        if not title:
            raise ValueError(f"Không parse được truyện {source_novel_id} ({self.name})")
        genres: list[str] = []
        raw_cat = p.get("categoryV2")
        if isinstance(raw_cat, str) and raw_cat.startswith("["):
            try:
                genres = [item.get("Name", "") for item in json.loads(raw_cat)
                          if isinstance(item, dict) and item.get("Name")]
            except ValueError:
                pass
        if not genres and p.get("category"):
            genres = [str(p["category"])]
        cover = normalize_cover_url(p.get("thumbUrl"))
        # Ngữ nghĩa đã đối chiếu thực tế (2026-08-22): status luôn =1 vô nghĩa;
        # creationStatus: 1 = 连载 đang ra (lastPublishTime hôm nay), 0 = 完结 xong.
        # API trả CHUỖI ("1") ở chỗ __INITIAL_STATE__ cũ trả SỐ (1) — so thẳng với 1
        # thì MỌI truyện đang ra bị đánh dấu hoàn thành. Ép kiểu trước khi so.
        status = "ongoing" if _as_int(p.get("creationStatus")) == 1 else "completed"
        last_at = None
        raw_ts = str(p.get("lastPublishTime") or "")
        if raw_ts.isdigit():
            from datetime import datetime, timezone
            last_at = datetime.fromtimestamp(int(raw_ts), tz=timezone.utc)
        return NovelMeta(
            source_novel_id=source_novel_id,
            source_url=f"{self.base_url}/page/{source_novel_id}",
            title_zh=title,
            author_zh=p.get("author"),
            cover_url=cover,
            description_zh=p.get("abstract") or p.get("description"),
            genres_zh=genres,
            status=status,
            # book/info KHÔNG có chapterTotal/itemIds → đếm từ mục lục (dùng chung
            # cache với fetch_chapter_list nên không tốn thêm request)
            chapter_count=len(self._directory(source_novel_id).get("allItemIds") or []),
            word_count=_as_int(p.get("wordNumber")),
            last_chapter_at=last_at,
            stats={"readCount": _as_int(p.get("readCount"))} if p.get("readCount") else {},
        )

    def fetch_chapter_list(self, source_novel_id: str) -> list[ChapterRef]:
        self.last_toc_status = None
        d = self._directory(source_novel_id)
        ids = [str(x) for x in (d.get("allItemIds") or [])]
        if not ids:
            raise ValueError(f"Mục lục rỗng {self.name} cho {source_novel_id}")
        # allItemIds xếp CŨ-TRƯỚC sẵn (đối chiếu chapterListWithVolume: phần tử đầu là
        # "第1章"), khác itemIds của /page/ vốn mới-trước và phải đảo.
        titles = {str(c.get("itemId")): (c.get("title") or "").strip()
                  for vol in (d.get("chapterListWithVolume") or [])
                  for c in (vol or []) if c.get("itemId")}
        return [ChapterRef(index=i + 1, source_chapter_id=cid,
                           title_zh=titles.get(cid) or None)
                for i, cid in enumerate(ids)]

    def fetch_chapter(self, source_chapter_id: str) -> str:
        html = self._get(f"/reader/{source_chapter_id}")
        self._check_font(html)
        state = self._parse_reader_state(html)
        content_html = self._find_content_html(state)
        if not content_html:
            raise ValueError(f"Không thấy nội dung chương {source_chapter_id} ({self.name})")
        text = self._decode_content(content_html)
        left_pua = sum(1 for c in text if 0xE000 <= ord(c) <= 0xF8FF)
        if left_pua > max(5, len(text) // 50):
            raise ValueError(f"Chương {source_chapter_id} còn {left_pua} ký tự PUA "
                             f"sau khi decode — bảng mã lệch font?")
        if not text:
            raise ValueError(f"Chương {source_chapter_id} rỗng sau khi lọc ({self.name})")
        return text

    def _parse_reader_state(self, html: str) -> dict:
        m = _STATE_RE.search(html)
        if not m:
            raise ValueError(f"{self.name}: trang reader thiếu __INITIAL_STATE__")
        start = html.index("{", m.end())
        end = html.find("</script>", start)
        seg = _UNDEFINED_RE.sub("null", html[start:end if end != -1 else len(html)])
        obj, _ = json.JSONDecoder().raw_decode(seg.lstrip())
        return obj if isinstance(obj, dict) else {}
