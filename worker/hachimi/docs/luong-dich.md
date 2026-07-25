# Luồng dịch một chương — từng bước

Cập nhật 25/07/2026. Mã nguồn: `worker/novelworker/translator/worker.py::handle_chapter`.

## 0. Trước khi có gì để dịch

Crawler tải chương về, lưu `chapters.content_zh` (nguồn Trung) và tạo job `translate` trong
hàng đợi. Worker `claim_next_job` lấy job theo `(priority, created_at)`, mỗi truyện chỉ một
job chạy cùng lúc.

## 1. Chuẩn bị (mọi engine dùng chung)

| Bước | Việc | Ghi chú |
|---|---|---|
| 1.1 | Đọc chương, chặn nếu chưa có `content_zh` | job fail có lý do rõ, không dịch rỗng |
| 1.2 | `clean_source(content_zh)` | bỏ quảng cáo nguồn, ký tự lạ, chuẩn hoá dòng |
| 1.3 | Đánh dấu `translation_status = translating` | để UI biết đang chạy |
| 1.4 | `db.get_glossary(novel_id)` | term đã duyệt (toàn cục + truyện) **và** term gợi ý `approved=false` của truyện — đây là thứ giữ tên riêng nhất quán giữa các chương |
| 1.5 | Đọc `novels.translation_provider` | quyết định engine: `hachimi` (mặc định) hay LLM |

## 2. Nhánh Hachimi (đường chính, `_translate_hachimi`)

### 2.1 Trích tên — chỉ chương ≤ 20

Gọi LLM **một lần** với `SYSTEM_ANALYZE`, chỉ để **liệt kê tên riêng**, không dịch. Tên
được đối chiếu bảng Hán-Việt rồi ghi vào glossary dạng gợi ý. Chương 21 trở đi không gọi
LLM nữa — glossary lúc đó đã đủ, và đây là chỗ chặn chi phí khi dịch lại cả kho.

### 2.2 Termguard — cưỡng chế thuật ngữ

`termguard.translate_text(content, terms, engine)` chạy ba nhịp:

1. **Dịch thường trước.** Cả chương một lượt.
2. **Soát từng dòng**: dòng nào thiếu term chuẩn (tên riêng, số) thì đánh dấu.
3. **Chỉ dòng hỏng mới dịch lại** với thuật ngữ đã thay bằng mã (`ZX001Q`, `JWZF`, `⟦001⟧` —
   thử lần lượt ba họ mã). Dịch xong thay mã ngược lại thành bản dịch chuẩn.
   Mã nào không sống sót nguyên vẹn thì **giữ bản dịch thường** — thà tên lệch còn hơn mất câu.

Vì sao phải thế: model 57M đoán tên bừa (睚眦 → Mộ Tắc/Mão Tí/Mô Tễ trong cùng chương).
Mã số thì nó copy nguyên vẹn 100%.

### 2.3 Engine CT2 dịch

`hachimi_engine.translate_text` — giữ khung dòng của chương, dịch **theo từng dòng**:

1. **Chia nguồn**: dòng dài cắt ở `。！？；`, còn quá dài thì cắt tiếp ở `，、：`; không bao giờ
   xé một lượt thoại trong ngoặc kép.
2. **Dịch**: SentencePiece → CT2, `beam_size=6`, `max_decoding_length=180`, thêm `</s>` cuối
   nguồn (thiếu là model dịch xong không biết dừng, lặp tới trần).
3. **Chọn trong n-best** *(mới 25/07)*: beam đã tính sẵn 6 giả thuyết; chấm cả 6 bằng cổng
   chất lượng của dự án — phạt đại từ hiện đại ×10, Hán sót ×10, số sai ×5, ngoặc kép lệch ×3
   (chỉ khi nguồn cân), danh xưng thân tộc hiện đại ×5, cụm lặp ×4, lệch nhịp câu ×1 — rồi lấy
   bản ít điểm phạt nhất thay vì bản xác suất cao nhất.
4. **Cứu dòng hỏng**: bản dịch còn chữ Hán hoặc chạm trần token → tự chia nhỏ dòng, dịch lại.
5. **Ghép lại**: nối các mảnh, hạ chữ hoa đầu mảnh khi mảnh trước chưa kết câu (giữ tên riêng,
   ALL-CAPS, mã placeholder).

### 2.4 Hậu xử lý (không gọi LLM)

| Bước | Sửa gì |
|---|---|
| `_clean_output` | gộp nói lắp ("Cốc cốc cốc cốc" → "Cốc cốc"), bỏ rác model chèn |
| `_hanviet_fallback` | chữ Hán sót lẻ → tra bảng `hanviet.tsv` (13.6k chữ), không đoán |
| `_fix_soft_style` | vá văn convert máy móc |
| `_fix_register` | vá đại từ kể sai **ngoài ngoặc kép** ("cô ấy/anh ta" → nàng/hắn) |

### 2.5 Tiêu đề chương

Dịch riêng qua đúng đường trên. Còn trơ chữ Hán thì phiên âm Hán-Việt bằng bảng tra.

## 3. Nhánh LLM (chỉ khi truyện được ghim tay)

1. Cắt chương thành chunk theo ranh giới đoạn văn.
2. Mỗi chunk: gọi LLM với prompt gồm **luật xưng hô + luật văn phong + nội dung**. Không
   chèn glossary, không tóm tắt chương trước, không nối đuôi chương trước.
3. Bóc phần thừa model quen tay xuất ra (SUMMARY/GLOSSARY_JSON), `_clean_output`, rồi
   `_fix_han_residue` (glossary → bảng tra → LLM chỉ khi thật sự cần).
4. Ghép chunk, `_fix_register`, `_fix_soft_style`, bóc tiêu đề.

## 4. Lưu kết quả

| Bước | Việc |
|---|---|
| 4.1 | Nguồn quá ngắn (<100 ký tự) → chèn ghi chú cho người đọc biết là lỗi nguồn |
| 4.2 | `finalize_chapter_job` — lưu bản dịch + đóng job trong MỘT transaction |
| 4.3 | `lint_score` — chấm lỗi văn phong để màn Quét lỗi xếp hạng |
| 4.4 | Ghi tên riêng mới phát hiện vào glossary dạng gợi ý (chương sau dùng lại ngay) |

`content_zh` **không bị xoá** sau khi dịch để lần dịch lại không phải chờ crawler.

## 5. Những tầng chịu trách nhiệm cho từng loại lỗi

| Loại lỗi | Sửa ở đâu | Vì sao không phải chỗ khác |
|---|---|---|
| Tên riêng lệch giữa các chương | glossary + termguard | model 57M không bao giờ tự nhất quán, train thêm cũng vô ích |
| Thuật ngữ cố định (冷却时间→CD, 高校) | glossary global | đã thử booster, model không học nổi |
| Xưng hô, nhịp câu, giọng văn | data finetune + chọn n-best | đây là phân bố, không phải ánh xạ |
| Chữ Hán sót | bảng `hanviet.tsv` | 0 chi phí, không đoán |
| Sai trật tự câu dài | **chưa có** | trần của model 57M (đã đo) |
