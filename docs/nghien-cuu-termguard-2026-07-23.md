# Nghiên cứu termguard Hachimi CT2

Ngày đo: 2026-07-23. Đây là nghiên cứu và thử nghiệm độc lập, chưa sửa pipeline
production, chưa deploy và không ghi dữ liệu vào Supabase.

## Kết luận ngắn

JWZF hiện tại không đủ tin cậy: trong 1.074 lần placeholder thật đi vào model,
chỉ 1.028 lần còn nhận diện được để restore (95,72%); 46 lần mất/hỏng
(4,28%), kèm 12 lần model sinh thừa mã. Sau khi bỏ các mã còn nguyên khỏi
output thô, vẫn có 34 token giống mảnh JWZF bị băm.

Đổi hình dạng mã chỉ giảm lỗi, không giải quyết gốc:

- mã chữ+số `ZX001Q`: tốt nhất trong nhóm placeholder, nhưng vẫn mất 34/1.074
  (3,17%);
- ngoặc+số `⟦001⟧`: mất 35/1.074 và sinh thừa 26 lần;
- ký tự Private Use: mất 100%;
- từ hiếm có sẵn như một SentencePiece: gần như mất 100%;
- nhét thẳng `correct_vi` vào nguồn: chỉ giữ nguyên 106/1.098 (9,65%) và làm
  câu hỏng nặng.

Phép đo bổ sung trên toàn bộ 193 chương đã dịch của truyện `novel_id=1380`
cho thấy có thể khắc phục trực tiếp failure mode mất tên mà không cần LLM:
dùng `ZX001Q` ở lượt đầu, kiểm đếm marker theo từng dòng, rồi chỉ dịch lại dòng
lỗi bằng JWZF. Trên 588 lần `睚眦` thật, lượt đầu giữ đủ 582/588 (98,98%);
lượt retry cứu đủ 6/6 còn lại, tổng cộng **588/588, không mất tên**.

**Khuyến nghị chính đã cập nhật:** giữ placeholder nhưng biến nó thành giao
thức có kiểm chứng và fallback, không cleanup mù. Dùng mã chữ+số ở lượt đầu;
nếu số marker đích khác số term nguồn thì bỏ output lỗi và dịch lại đúng dòng
đó bằng một họ mã khác. Chỉ restore khi cardinality khớp. Nếu mọi marker đều
thất bại, dùng bản dịch thường cộng exact variant đã duyệt, tuyệt đối không xoá
mã thành khoảng trống. Đồng thời chỉ cưỡng chế term đã duyệt và áp longest-match
trên tập đã duyệt để gợi ý glossary sai không lấn term đúng.

## 1. Cơ chế hiện tại

Luồng production hiện tại:

1. `_translate_hachimi` lấy glossary.
2. `termguard.protect` thay term dài trước bằng mã tạo từ `JWZF`, bọc khoảng
   trắng.
3. `hachimi_engine.translate_text` tách chương theo dòng và dịch batch bằng
   MarianMT/CT2.
4. `termguard.restore` nhận cả mã nguyên và mã bị chèn khoảng trắng, thay về
   `correct_vi`.
5. Regex dọn token `JWZF` 1–3 ký tự bị sót.

Điểm yếu không nằm ở regex restore nữa. Model đã thay đổi hoặc xoá thông tin
trước khi restore nhìn thấy nó; cleanup sau đó chỉ biến lỗi “mã hỏng” thành lỗi
“tên biến mất”.

## 2. Thiết kế phép đo

### Mẫu dữ liệu

- 30 chương thật, đều có `content_zh` và `content_vi`.
- 3 truyện: `novel_id` 282, 1256, 1380; mỗi truyện 10 chương.
- Lấy trải đều theo dải chương có term, không chỉ chọn chương dày term nhất.
- 72.131 ký tự Trung, 2.570 dòng nguồn.
- 247 dòng glossary đã duyệt được nạp cho ba truyện.
- 1.074 lần term thực sự được thay bằng placeholder trong tập so sánh.

Danh sách chapter ID và chapter index nằm trong
`worker/experiments/termguard_results.json`.

### Môi trường

- `ctranslate2==4.8.1`
- model `worker/models/hachimi-ct2/model.bin`
- `beam_size=4`
- `HACHIMI_CPU_THREADS=2`
- model dịch theo từng dòng đúng như production
- mọi truy vấn DB đều chỉ đọc

JWZF chạy đủ toàn bộ 30 chương qua
`protect → translate_text → restore`. Các phương án placeholder khác chỉ dịch
814 dòng có term trên cùng 30 chương. Điều này tương đương đối với output của
model vì engine hiện tại dịch từng dòng độc lập.

### Chỉ số

- `expected`: số placeholder có biên hợp lệ thật sự đi vào model.
- `exact`: sống nguyên byte-for-byte.
- `restorable`: còn khớp quy tắc restore, kể cả model chèn khoảng trắng.
- `lost`: expected nhưng không còn placeholder nhận diện được.
- `overgenerated`: model sinh nhiều placeholder nhận diện được hơn đầu vào.

Mẫu số JWZF dùng đúng regex biên production. Không dùng `str.count`, vì mã
ngắn như `JW` là tiền tố của mã dài như `JWJ`.

## 3. Kết quả placeholder

| Cách | Sống nguyên | Restore được | Mất/hỏng | Sinh thừa | Nhận xét |
|---|---:|---:|---:|---:|---|
| JWZF hiện tại | 1.019/1.074 (94,88%) | 1.028/1.074 (95,72%) | 46 | 12 | 9 ca cứu được nhờ cho phép space |
| `ZX001Q` | 1.040/1.074 (96,83%) | 1.040/1.074 (96,83%) | 34 | 1 | tốt nhất trong nhóm mã |
| `⟦001⟧` | 1.039/1.074 (96,74%) | 1.039/1.074 (96,74%) | 35 | 26 | model hay nhái/sinh thừa |
| Private Use U+E000… | 0/1.074 | 0/1.074 | 1.074 | 0 | byte fallback không giúp copy |
| từ Latin hiếm, một piece | 0/1.074 | 1/1.074 (0,09%) | 1.073 | 0 | model coi đó là nội dung cần dịch |
| nhét thẳng `correct_vi` | 106/1.098 (9,65%) | 106/1.098 | 992 | 0 | phá câu, đổi tên thành rác |

Mã chữ+số giảm số mất từ 46 xuống 34, tức giảm 12 ca, nhưng 3,17% vẫn quá cao
cho tên riêng. Đây chỉ là phương án đỡ tệ hơn nếu buộc giữ kiến trúc cũ.

Ví dụ nhét thẳng tiếng Việt vào nguồn làm model trả:

- `林子洛` → `Lâm Tử Lạc` trong nguồn nhưng output thành `Ê-ngươi`;
- `魔都大学` → `Ma Đô Đại Học` trong nguồn nhưng output thành `Maraghts`;
- nhiều dòng bị rút còn số hoặc mất cả mệnh đề.

Kết luận: SentencePiece “biết token” không có nghĩa Marian đã học thao tác copy
token đó.

## 4. Dịch bình thường rồi hậu sửa

### 4.1 Attention có tìm được vùng tên không?

CT2 trả attention thật cho 814 dòng:

- 1.074 lần term;
- cách chọn span đơn giản theo argmax attention tìm được vùng ở 1.055/1.074
  lần (98,23%);
- không có collision trong bản thử đầu.

Nhưng “tìm được một vùng” không đồng nghĩa “biên vùng đúng”. Các lỗi thật:

- `末日游戏` → chỉ bắt `trò chơi tận`, để lại chữ `thế`;
- `储物空间` → bắt `không gian trữ`, để lại chữ `vật`;
- `丧尸` → chỉ bắt chữ `Z` trong `Zombie`, thay xong thành `zombieombie`;
- `魔都大学` có thể nuốt thêm `ký túc xá`;
- cụm đảo thứ tự Việt như `Đại học Ma Đô` làm biên không trùng thứ tự nguồn.

### 4.2 Thêm gate có đủ an toàn không?

Gate thứ hai:

1. nếu `correct_vi` đã có trong output (không phân biệt hoa/thường), không sửa;
2. chỉ attention 249 ca còn sai;
3. gộp attention xuôi+ngược;
4. bỏ span confidence thấp, span quá rộng và collision.

Kết quả:

- 825/1.074 ca (76,82%) vốn đã đúng, không cần sửa;
- trong nhóm `person/place/sect`: 616/704 ca (87,50%) vốn đã đúng;
- còn 249 ca cần sửa, trong đó 88 ca là `person/place/sect`;
- 227/249 qua các gate số học.

Tuy vậy, kiểm tra thủ công 30 candidate patch đầu tiên cho thấy **19/30** vẫn
thừa/thiếu từ hoặc làm hỏng ngữ pháp. Confidence cao không bảo đảm biên đúng.
Vì thế không nên dùng attention để tự cắt và thay text trong hot path.

### 4.3 Attention hữu ích ở đâu?

Attention rất hữu ích để **khai thác ứng viên offline**. Với `睚眦 → Nhai Tý`,
31 ca model dịch sai trong mẫu tạo ra:

- `Xương Tí`: 15
- `Đồng Tí`: 6
- `Hậu Tí`: 2
- các ứng viên lẻ: `Hề Tí`, `Xã Tí` và một số span nhiễu

Người duyệt có thể chốt các biến thể thật, bỏ span nhiễu, rồi runtime chỉ thay
exact string. Cơ chế này không cần LLM và không có thao tác xoá placeholder.

`wrong_vi` hiện tại chưa đủ cho cách này: trên mẫu chỉ exact-match được 2/249
ca cần sửa, và 0/88 ca tên `person/place/sect`. Cần lưu **nhiều biến thể đã
duyệt cho một term**, không chỉ một `wrong_vi`.

## 5. Constrained decoding trong CTranslate2

API CT2 4.8.1 có:

- `target_prefix`: ép chuỗi ở **đầu** output;
- `prefix_bias_beta`: bias cho prefix;
- `suppress_sequences`: cấm chuỗi, không ép chuỗi dương;
- `return_attention`;
- `return_logits_vocab`, nhưng là dữ liệu trả về, không phải hook sửa beam;
- callback chỉ dùng khi `beam_size=1` và chỉ có thể dừng.

Thử 20 dòng với `target_prefix`:

- 20/20 output bắt đầu bằng term bị ép;
- 14/20 term không nằm đầu nguồn, nên bị đặt sai vị trí ngay lập tức.

CTranslate2 hiện không cung cấp positive lexical constraints ở vị trí bất kỳ.
Muốn Grid Beam Search/DBA phải đổi runtime hoặc tự viết decoder. Các thuật toán
này tồn tại trong nghiên cứu, nhưng thêm độ phức tạp decoder và có rủi ro lặp/
đặt sai nếu thiếu alignment tốt; không hợp mục tiêu VPS 2 core và diff tối
thiểu.

Tài liệu:

- [CTranslate2 Translator API](https://opennmt.net/CTranslate2/python/ctranslate2.Translator.html)
- [Grid Beam Search, ACL 2017](https://aclanthology.org/P17-1141/)
- [Terminology constraints có alignment, NAACL 2018](https://aclanthology.org/N18-2081.pdf)
- [Dynamic Beam Allocation, NAACL 2018](https://aclanthology.org/N18-1119/)

## 6. Fine-tune

Fine-tune trực tiếp các tên hiếm không phải hướng chính:

- tên truyện mới, item và kỹ năng là tập mở;
- học được vài tên trong train không tạo bảo đảm cho tên chưa thấy;
- có nguy cơ học sai một phiên âm và phát tán toàn bộ;
- vẫn phải giữ glossary và hậu kiểm.

Fine-tune đáng thử theo hướng khác: dạy model **giao thức copy sentinel tổng
quát**, bằng nhiều cặp train có marker ở vị trí/cấu trúc đa dạng. Tuy nhiên:

- phải train từ model Transformers/Marian gốc rồi export lại CT2; `model.bin`
  là artifact inference, không phải checkpoint để fine-tune trực tiếp;
- muốn thêm `user_defined_symbols` thật sự phải đổi tokenizer/vocabulary và
  embedding; không thể chỉ thêm symbol vào SentencePiece đã train;
- cần benchmark riêng về survival, fidelity và register trước khi cân nhắc
  production;
- dù đạt 99% vẫn phải có cardinality gate, không được cleanup mù.

Repo đã có đường train/export ở `worker/hachimi_finetune/kaggle_train.py`.
Tài liệu nền:

- [CTranslate2 model conversion](https://opennmt.net/CTranslate2/conversion.html)
- [CTranslate2 hỗ trợ MarianMT/Transformers](https://opennmt.net/CTranslate2/guides/transformers.html)
- [Hugging Face: fine-tune bài toán translation](https://huggingface.co/docs/transformers/tasks/translation)
- [SentencePiece: control/user-defined symbols được quyết định lúc train](https://github.com/google/sentencepiece/issues/667)

## 7. Khuyến nghị để quyết định

### Hướng nên làm nhất: placeholder có cardinality gate + retry theo dòng

Phép thử tập trung dùng toàn bộ dữ liệu đã dịch của truyện `novel_id=1380`:

- 193 chương có cả `content_zh` và `content_vi`;
- 556 dòng nguồn chứa `睚眦`, tổng cộng 588 lần xuất hiện;
- DB hiện chỉ có 529 lần `Nhai Tý`;
- 27 chương thiếu so với nguồn, tổng thiếu trong các chương này là 68 lần;
- hiệu số ròng toàn truyện là 59 vì một số chương có số tên đích nhiều hơn
  nguồn.

Chạy lại đúng 556 dòng bằng model local:

| Lượt | Dòng thử | Dòng đủ marker | Lần xuất hiện được bảo toàn |
|---|---:|---:|---:|
| `ZX001Q` | 556 | 551 | 582/588 (98,98%) |
| JWZF, chỉ retry dòng lỗi | 5 | 5 | 6/6 |
| Tổng cascade | 556 + 5 | 556 | **588/588 (100%)** |

Năm dòng lỗi lượt đầu gồm các dạng model đổi `ZX001Q` thành `ZX01Q`,
`XX001Q`, hoặc xoá hẳn. JWZF lại sống nguyên trên cả năm dòng này. Điều quan
trọng không phải JWZF tốt tuyệt đối, mà hai kiểu mã có lỗi không trùng nhau
trên tập này và cardinality gate phát hiện được mọi lỗi trước restore.

Luồng đề xuất:

1. Chỉ lấy glossary đủ điều kiện cưỡng chế: `approved=true`, có `correct_vi`,
   và loại term có ghi chú nghi sai.
2. Chọn longest-match trên chính tập đã duyệt.
3. Dịch toàn bộ dòng bằng mã chữ+số.
4. Trước restore, đếm từng marker trong từng dòng. Chỉ nhận dòng có đúng số
   lượng mong đợi.
5. Retry riêng dòng thiếu/thừa bằng họ mã JWZF; nếu cần có thể thêm lượt
   `⟦001⟧`.
6. Nếu tất cả lượt marker vẫn lỗi, dịch dòng gốc bình thường rồi chỉ thay exact
   variant đã duyệt. Không có variant thì giữ output và ghi unresolved.
7. Không chạy regex cleanup xoá mảnh trên output chưa qua cardinality gate.

Chi phí retry trong phép đo là 5/556 dòng, tức 0,90% số dòng có term. Tổng lượt
placeholder mất 35,25 giây trên CPU hai luồng; đây là cùng bậc với lượt dịch
thường 44,75 giây trong lần chạy kế bên, không phải nhân đôi toàn chương.

### Lỗi dữ liệu glossary phải khóa cùng lúc

Trong 588 lần `睚眦`, có 8 lần nằm trong `睚眦必报` và 2 lần nằm trong
`睚眦之怨必报`. DB có term dài hơn cho các cụm này, nhưng chúng chưa được duyệt
và bản Việt đang dùng `Tí` thay vì `Tý`. Production hiện tại lấy cả gợi ý
`approved=false`; `_eligible` chỉ bỏ term có ghi chú `nghi sai`. Vì vậy một
gợi ý dài chưa duyệt có thể lấn term ngắn đã duyệt.

Cardinality cascade giải quyết việc model băm/xoá marker, nhưng không thể sửa
glossary sai. Gate `approved=true` và longest-match chỉ trong tập đã duyệt là
điều kiện bắt buộc để 100% survival không biến thành 100% cưỡng chế sai nghĩa.

### Vai trò còn lại của normal MT + source-gated variant post-edit

Luồng đề xuất:

1. Dịch dòng gốc bình thường, không protect.
2. Với mỗi `term_zh` có trong đúng dòng nguồn:
   - nếu `correct_vi` đã có trong đích: giữ nguyên;
   - nếu đích chứa một biến thể sai **đã duyệt** của term: thay exact biến thể
     đó bằng `correct_vi`;
   - nếu không khớp: giữ nguyên output, ghi unresolved để duyệt; không đoán
     span, không xoá gì.
3. Tool offline dùng attention để đề xuất biến thể theo tần suất.
4. Người dùng duyệt danh sách `term_zh | variant_vi | correct_vi`.
5. Lưu nhiều variant cho mỗi term; ưu tiên match dài trước, source-gate theo
   dòng để tránh thay nhầm từ Việt ở chỗ khác.

Hướng này phù hợp làm fallback cuối và công cụ sửa dữ liệu cũ. Trên đúng 588
lần `睚眦`, normal MT không tự sinh lần nào đúng `Nhai Tý`; bộ 19 biến thể đã
duyệt sửa được 543/588 (92,35%), còn 45 lần unresolved. Vì vậy nó không đủ làm
đường chính cho tên hiếm, nhưng an toàn hơn việc xoá marker lỗi.

Ưu điểm:

- không còn failure mode “tên biến mất”;
- runtime chỉ là exact string replacement, rất nhẹ trên 2 core;
- không gọi LLM;
- một biến thể duyệt sửa được toàn truyện;
- lỗi chưa biết vẫn nhìn thấy và sửa được, không phá dữ liệu.

Nhược điểm:

- cần bootstrap variant cho mỗi truyện;
- biến thể mới vẫn có thể lọt cho tới lần audit tiếp theo;
- attention mining cần duyệt tay, không tự động áp.

### Chỉ fine-tune khi nào?

Chỉ thử fine-tune copy-sentinel nếu variant post-edit tạo quá nhiều công duyệt.
Không fine-tune danh sách tên/item cụ thể. Gate nghiệm thu tối thiểu:

- marker survival trên tập giữ lại phải cao hơn phương án chữ+số rõ rệt;
- 0 silent loss nhờ cardinality fallback;
- không giảm fidelity câu thường;
- không tăng thời gian dịch VPS quá mức chấp nhận.

## 8. Hiệu năng và giới hạn phép đo

- JWZF đủ 2.570 dòng: 119,34 giây, 21,53 dòng/giây trên 2 threads.
- Attention 814 dòng: 34,41 giây, 23,66 dòng/giây.
- Exact variant replacement chưa benchmark riêng vì chi phí chỉ là quét chuỗi,
  nhỏ hơn rất nhiều so với CT2.

Giới hạn:

- mẫu 30 chương/3 truyện, không đại diện tuyệt đối cho toàn kho;
- chỉ model và cấu hình hiện tại;
- số survival đo độ bền protocol, không phải BLEU/fidelity;
- `content_vi` chỉ dùng để chọn chương thật, không dùng làm gold tự động;
- đánh giá 19/30 attention patch là kiểm tra thủ công trên 30 candidate đầu của
  output xác định, chưa phải blind review nhiều người.

## 9. Artifact và cách chạy lại

- Script: `worker/experiments/termguard_research.py`
- Placeholder: `worker/experiments/termguard_results.json`
- Attention + variant mining: `worker/experiments/termguard_attention_v5.json`
- Nhét thẳng `correct_vi`: `worker/experiments/termguard_direct_vi.json`
- Đối chiếu DB + khai thác biến thể: `worker/experiments/termguard_db_yazi_repaired.json`
- Cascade 588 lần `睚眦`: `worker/experiments/termguard_db_yazi_cascade.json`

Trong file `termguard_direct_vi.json`, `raw` là output Hachimi sau khi nguồn
Trung đã bị thay trực tiếp bằng `correct_vi`; `restored` là output đó sau bước
restore thử nghiệm. Hai trường này không phải `chapters.content_vi` trong DB,
và cũng không phải output JWZF production.

PowerShell:

```powershell
cd E:\Novel_Project\worker
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONPATH = "."
$env:HACHIMI_CPU_THREADS = "2"
..\.venv\Scripts\python.exe experiments\termguard_research.py `
  --chapters 30 --novels 3 `
  --output experiments\termguard_results.json
```

Self-check:

```powershell
..\.venv\Scripts\python.exe -m py_compile experiments\termguard_research.py
..\.venv\Scripts\python.exe experiments\termguard_research.py --self-check
```
