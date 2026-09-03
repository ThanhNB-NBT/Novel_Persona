# Bàn giao sang session mới — 30/08/2026 (chiều)

Dán nguyên phần dưới vào session mới.

---

Tiếp tục dự án dịch truyện Trung→Việt ở `~/code/Novel_Project`. Trả lời tiếng Việt, gọi tôi
"đạo hữu", tự xưng "tại hạ". Đọc `AGENTS.md` + `CLAUDE.md` trước khi sửa gì.

**Đọc trước khi làm bất cứ điều gì:** `worker/hachimi/docs/train-scratch-v7.md` — 20 mục, ghi
toàn bộ số đo và quyết định của vòng v7. Bàn giao này chỉ là bản tóm để định hướng.

## Đang chạy nền

- **Crawl 357 truyện** trên box (`ssh thanhnb@100.80.88.43`), trong container:
  `docker exec worker-crawler-1 sh -lc "wc -l < /app/zh_raw_v7.jsonl; tail -1 /app/anchor_v7.log"`
  Lúc bàn giao: ~220/357 truyện, ~4.200 chương. Nhịp 3,7 s/chương là **cố ý** (một IP công cộng).
  Xong thì `docker cp worker-crawler-1:/app/zh_raw_v7.jsonl ~/anchor/` rồi kéo về máy dev.
- Kaggle: **trống**, không có kernel nào chạy.

## Trạng thái data

| thứ | số | chỗ |
|---|---|---|
| Corpus kaihe sạch | **5.766.394 cặp / 117 giọng dịch** | `~/hachimi-work/scratch/corpus12m.jsonl` |
| SPM 24k nấu lại | zh −9,3% token/câu | `~/hachimi-work/scratch/spm24k_clean/` |
| Truyện Trung tải từ CNovels | 3.333 truyện · 17 GB | `~/hachimi-work/cnovels/` |
| Cặp chương đã ghép + lọc | 162.752 cặp / 1.762 truyện | `~/hachimi-work/scratch/paired_clean.jsonl` |

## BỐN KẾT LUẬN LỚN — đừng làm lại

### 1. Kiến trúc đã chốt, có bằng chứng (mục 20)

`preset v7` = **12 enc / 2 dec, ffn 2048 cả hai** (58,4M). Theo Kasai et al. ICLR 2021
(arXiv 2006.10369), đo trên WMT17 EN↔ZH. Giữ 2 layer decoder chứ không xuống 1 vì **cán cân
rủi ro**: encoder sâu là món gần như miễn phí, còn decoder cạn đổi chất lượng lấy tốc độ mà ta
đang thiếu chất lượng chứ không thiếu tốc độ. `v7-fast` (12/1) để dành thí nghiệm sau.

### 2. Probe KHÔNG kết luận được gì về ngữ cảnh (mục 20.3)

Ba lượt probe đã chạy, **kết quả không dùng được**: probe train 2 epoch ≈ 10k bước, trong khi
Popel & Bojar đo 16M cặp cần ~10 epoch mới hội tụ và Kasai train 300k bước — **kém 30 lần**.
Bằng chứng nhiễu: cùng thiết lập, lượt 1 đo `P1−P0 = +0,07`, lượt 2 đo `−1,32`.

⇒ **Đừng chạy thêm probe ngắn.** Dồn quota vào MỘT bản train dài, rồi bật/tắt ngữ cảnh so ở mức
hội tụ. Ba thứ gần như miễn phí đang bỏ sót: **trung bình 5 checkpoint tốt nhất**, **batch tính
theo TOKEN không theo câu** (Popel đo ảnh hưởng 2,6 BLEU), `max_length` giữ 384.

### 3. Hướng epub × CNovels ĐÃ CẠN (mục 19 + đo 30/08 chiều)

Ghép được 1.762 truyện nhưng đo mật độ hư từ (thước của `docs/epub-anchor.md`: convert 4-6,
dịch tay 17-22, kaihe 18,5):

| | |
|---|---|
| Trung vị của 1.726 truyện ghép được | **7,2** |
| Ngưỡng ≥14 (dịch tay) | còn **41 truyện — 2%** |

**~98% là convert máy.** Tệ hơn: toàn kho epub đạt 13,2% ở ngưỡng đó, tập ghép được chỉ 2% —
tức **tương quan nghịch**: truyện tìm được nguyên tác trong CNovels chính là truyện ít được
dịch tay nhất (CNovels toàn tiên hiệp dài tập, thể loại đó ở VN chủ yếu là convert).

Đã tách thêm nhóm: 60% convert thô, 40% "trôi chảy + giọng cổ" (hư từ 9,5 — vẫn dưới người),
**6 truyện** nghi Google Translate. GT không phải vấn đề ở kho này.

**XÁC NHẬN LẦN HAI (đo 30/08 tối, tập ĐỘC LẬP):** 357 truyện crawl từ DB box cũng cho
**trung vị 7,0**, đạt ngưỡng ≥14 chỉ **12/357 truyện (3%)**. Hai tập độc lập ra cùng con số ⇒
kết luận "kho epub ~98% convert" là chắc, không phải suy từ một mẫu.

⚠ **SAI THỨ TỰ ĐÃ MẮC:** cuộc crawl 357 truyện chạy mất **7 giờ box** để lấy nguyên tác Trung
cho những truyện *tưởng là* có bản dịch tay — nhưng phép đo mật độ hư từ chỉ mất **8 phút** và
làm được từ đầu (bản dịch Việt nằm sẵn trong kho epub trên đĩa). **Đo trước, crawl sau.** Đây
đúng là bước sàng số 1 mà `docs/epub-anchor.md` ghi rõ mà vẫn bị bỏ qua hai lần.

Kết quả crawl vẫn dùng được nhưng theo cách KHÁC: **6.400+ chương tiếng Trung** là nguồn tốt cho
đường Gemini (cái hỏng là vế Việt, không phải vế Trung) — nhập chung với 100k câu văn xuôi.

⇒ Data người dịch **thực sự khan hiếm**. Đã quét hết: HuggingFace (CNovels là tốt nhất, đã
dùng), MNBVC (không có chỉ mục theo tên), ModelScope Novel-Collection 173GB (**1% truyện mới**
→ bỏ), ghép mờ (+45 nhưng sai gần hết), bổ sung bảng Hán-Việt (chỉ thiếu 19 chữ).

### 4. Chuyển hướng: LLM làm THẦY — và vì sao kết luận cũ đã lỗi thời

Kết luận cũ *"đừng chưng cất từ model free"* là kết luận về **gemma-4-31b** (ngang trình v5),
**không phải** về chuyện data do người hay máy. Chưng cất từ thầy mạnh hơn trò là kỹ thuật
chuẩn — Kasai áp dụng KD cho mọi model và ghi rõ model tự hồi quy cũng hưởng lợi. "Model
collapse" (Shumailov 2024) nói về train ĐỆ QUY nhiều đời, không phải chưng cất một lần.

**Điều duy nhất còn giữ: thầy phải hơn trò, và phải ĐO. Thước phải neo vào bản dịch NGƯỜI.**

Đã đo sơ bộ trên NIM (key sẵn trong `worker/.env`, 40 model free endpoint):

| model | kết quả |
|---|---|
| `moonshotai/kimi-k3` | **dịch tốt** — tên Hán-Việt đúng, giọng cổ, văn trôi chảy. Nhưng **4,3 tok/s** → 15-25 phút/chương |
| `nvidia/nemotron-3.5-lightning-30b-a3b` | **42,9 tok/s** nhưng xuất ra "thinking process" thay vì bản dịch |
| `nvidia/riva-translate-4b-instruct-v2` | dịch ra **tiếng Anh**, tên pinyin → bỏ |
| `meta/muse-glimmer-30b` | trả rỗng |
| `opencode/nemotron-3.5-lightning-free` | **sai tên riêng**: `南宫正雄` → "Nông Cung Chính Hùng" (đúng: Nam Cung Chính Hùng) |

⚠ Mã model NIM phải lấy từ https://build.nvidia.com/models?filters=nimType%3Anim_type_preview
(lọc Free Endpoint). Mã kiểu `nvidia/llama-3.1-nemotron-ultra-253b-v1` trả **404 not found for
account** — không thuộc gói free.

## VIỆC TIẾP THEO

### A. ĐÃ ĐO XONG — Gemini 3.7 Flash (Antigravity) THẮNG v6

**Vòng 1** (60 câu ngẫu nhiên, 4 trục): gemini đại từ hiện đại 1,67/100 câu vs v6 **5,00**.
Ba cột kia hoà. ⚠ Dòng "bản dịch người" trong bảng đó **HỎNG** — ghép `vi_human` theo vị trí
dòng, mà chương Việt có watermark (`read.st`) và dòng gộp/tách nên lệch. Đừng tin dòng đó.

**Vòng 2** (chọn ĐỐI NGHỊCH — quét 800 câu bằng v6, giữ đúng 45 câu v6 làm hỏng + 30 bài thơ):

| trên 45 câu v6 đã hỏng | gemini | v6 |
|---|---|---|
| đại từ hiện đại/100 câu | **13,33** | 24,44 |
| lint/100 câu | **55,56** | 82,22 |

| 30 bài thơ | bịa chủ ngữ | đại từ hiện đại | Hán sót | lint | ký tự lạ |
|---|---|---|---|---|---|
| gemini | 0,00 | 0,00 | 0,00 | 0,00 | **0,00** |

Đo được luôn: **v6 hỏng 6% câu văn xuôi** (45/800).

### A2. ĐÃ SINH DATA THẬT — 10.500 bài thơ

Chạy qua **Antigravity desktop** (Gemini 3.7 Flash), tốc độ **469 bài/phút** — nhanh hơn API
NIM cả trăm lần (kimi-k3 chỉ 4,3 tok/s). Nút thắt thông lượng nêu ở mục B **đã được gỡ** bằng
đường desktop, không phải bằng API.

| lô | bài | thiếu | lệch số câu | ký tự lạ | **phiên âm thô** |
|---|---|---|---|---|---|
| `scratch/poem_batch/` | 2.500 | 0 | 0% | 0% | **2,4%** |
| `scratch/poem_batch2/` (80/312 lô) | 8.000 | 0 | 0,60% | 0,01% | **2,4%** |
| bộ gemma cũ (đối chứng) | 3.228 | — | — | — | **33,7%** |

⇒ **Tốt hơn bộ booster thơ hiện tại 14 lần.** Đây là data dùng được ngay, không phải thí nghiệm.
Thơ là trục v6 yếu nhất (23% phiên âm thô).

**Thước phiên âm thô** (tự viết, không có sẵn): tỉ lệ âm trong bản dịch trùng với phiên âm
Hán-Việt của chính câu nguồn (dùng `novelworker.translator.hanviet._load()`). Cao = dịch thô.
Đối chứng bằng bộ gemma cũ nên con số có nghĩa.

### A3. CÒN DỞ — chạy tiếp bằng ĐÚNG prompt cũ

Cơ chế tiếp tục **dựa trên FILE, không dựa trên phiên chat** — prompt dặn bỏ qua lô đã có
`out_XXX.jsonl`. Nên đổi tài khoản / phiên mới / công cụ khác đều chạy tiếp được.

**Cả hai việc dưới đây ĐÃ XONG** — xem [`ban-giao-2026-09-01-prose.md`](ban-giao-2026-09-01-prose.md).

| việc | trạng thái |
|---|---|
| ~~Thơ~~ | **XONG** — 312/312 lô, 33.699 bài → `data/poem_vi.jsonl` 33.200 bài |
| ~~Văn xuôi~~ | **XONG 01/09** — 100.004 câu / 401 lô → 76.771 cặp vào corpus |

Văn xuôi lấy từ **nguyên tác Trung của 1.667 truyện epub** — truyện kaihe KHÔNG có, nên thêm từ
vựng/tình tiết mới. Tối đa 60 câu mỗi truyện (đa dạng thắng khối lượng). Đã khử trùng câu.

Kiểm tiến độ: `ls ~/hachimi-work/scratch/poem_batch2/out_*.jsonl | wc -l`  (312 = xong)

### A4. Việc phải làm sau khi sinh xong

1. Lọc bỏ bài lệch số câu / lọt ký tự lạ (~0,6%) rồi **thay bộ booster thơ cũ** trong pack —
   33,7% phiên âm thô là data đang dạy model làm sai.
2. Nemotron (OpenCode) **không dùng được**: bản free sai tên riêng (`南宫正雄` → "Nông Cung
   Chính Hùng"), và `opencode run` mất 127 giây/lần vì khởi động cả phiên agent.

### A5. Bài kiểm (giữ lại để đo model mới)

Bài kiểm đã dựng sẵn: `worker/hachimi/eval/llm_probe.py`.

```bash
cd ~/code/Novel_Project/worker
hachimi/.venv/bin/python hachimi/eval/llm_probe.py --make          # 60 câu, 4 trục
hachimi/.venv/bin/python hachimi/eval/llm_probe.py --prompt <ten>  # sinh prompt cho 1 công cụ
# user dán prompt vào OpenCode/Antigravity desktop, model tự đọc & ghi file
hachimi/.venv/bin/python hachimi/eval/llm_probe.py --score <reply> --label <ten>
```

60 câu chia đều **4 trục** (chọn theo trục chứ không ngẫu nhiên, vì ngẫu nhiên thì toàn câu dễ):
`subject_drop` (bịa chủ ngữ — lỗi nặng nhất của v6), `gender`, `names` (Hán-Việt trọn cụm),
`dialogue` (ta-ngươi).

Ba file tách bạch **có chủ ý**: `llm_probe_src.jsonl` (cho model đọc, CHỈ có n + zh),
`llm_probe_key.jsonl` (**giữ lại**, có bản dịch người), `llm_probe_reply_<ten>.txt`.
Đưa nhầm file key cho model là tự tay làm rò bộ chấm.

Prompt đã sinh sẵn ở `~/hachimi-work/scratch/PROMPT_opencode.txt` và `PROMPT_antigravity.txt`.

**Chưa có kết quả nào.** User dịch tay qua app desktop (không có CLI để tự động hoá:
Antigravity là app Electron thuần GUI, `opencode run` mất 127 giây/lần vì khởi động cả phiên
agent).

### B. Nếu LLM qua cổng: nút thắt là THÔNG LƯỢNG, không phải chất lượng

kimi-k3 ở 4,3 tok/s thì sinh 100k câu mất ~260 giờ. Phải tìm model **vừa đúng định dạng vừa đủ
nhanh**, hoặc chấp nhận dùng LLM cho **booster nhỏ có trọng điểm** (như đã làm với thơ:
31%→23%) chứ không sinh hàng loạt.

### C. Train bản thật

Chỉ chạy sau khi chốt được nguồn data. Kiến trúc đã có (`--preset v7`), script
`pipeline/train_scratch.py` đã vá xong ba bug lớn (xem mục 18 + `encode_rows`).

## BẪY ĐÃ DÍNH TRONG PHIÊN NÀY

- **`pkill -f <chuỗi>` / `pgrep -f <chuỗi>` khớp CHÍNH shell đang gọi nó** → tự giết mình hoặc
  báo "vẫn chạy" sai. Dính **3 lần**. Dùng `ps -eo pid,cmd | awk '/[p]attern/'` rồi kill theo pid.
- **Kaggle trả bản dataset CŨ ngay sau khi upload.** `datasets status` báo `ready` không có
  nghĩa bản mới đã lên — **phải so kích thước file** bằng `kaggle datasets files` trước khi push
  kernel. Đã mất một lượt chạy 3 giờ vì chuyện này.
- **Monitor chỉ bắt sự kiện KẾT THÚC thì lúc treo sẽ im lặng**, mà im lặng trông y hệt đang
  chạy. Đặt monitor in tiến độ định kỳ.
- **Test xanh không có nghĩa là đúng nếu test không chạm vùng có lỗi.** Hàm đọc số Hán sai từ
  hàng trăm trở lên mà test chỉ thử tới 99 nên lọt.
- **Đừng chạy binary GUI từ Bash** — tại hạ chạy `antigravity --help`, nó bật cả app Electron
  rồi timeout giết giữa chừng, làm hiện hộp thoại lỗi EPIPE trên màn hình user.
- **Số đẹp bất thường ⇒ nghi THƯỚC trước, nghi model sau.** `eval_register` ra `invented: 0`
  cho MỌI model kể cả v6 — thước không chạy chứ không phải model hoàn hảo. Luôn chạy một model
  đối chứng đã biết tính nết qua cùng cái thước, và luôn dựng **đối chứng âm** trước khi tin
  một ngưỡng.

## MÔI TRƯỜNG

- `worker/hachimi/.venv` (Python 3.11 qua uv). Chạy script từ `worker/` để import được
  `novelworker`.
- Antigravity: đã cài ở `~/.local/opt/antigravity`, có shortcut trong menu.
  **Bắt buộc `--no-sandbox`** (cài trong thư mục nhà nên `chrome-sandbox` thiếu setuid root).
- OpenCode CLI: `~/.opencode/bin/opencode`, đã đăng nhập, thấy 6 model free.
- ⚠ `~/.gemini/config/hooks.json` có **BOM ở đầu** nên không parse được → 0 hook được nạp.
- ⚠ `app/pubspec.yaml` đang **staged** và bị hỏng mã hoá (comment tiếng Việt encode 2 lần).
  Có task riêng đang chạy để sửa, đừng đụng.
