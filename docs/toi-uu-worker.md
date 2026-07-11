# Kế hoạch tối ưu worker crawl và translate

**Ngày lập:** 2026-07-11  
**Phạm vi:** `worker/novelworker`, cấu hình Docker và các RPC phục vụ worker  
**Trạng thái:** Kế hoạch, chưa triển khai

## 1. Mục tiêu

Tối ưu theo thứ tự:

1. Bản dịch phải tự nhiên, đúng văn phong và nhất quán xưng hô trong toàn truyện.
2. Lời thoại phải giữ đúng vai vế, quan hệ và cách tự xưng theo từng cảnh; không làm mất các cách xưng như “lão”, “lão phu”, “lão tử”.
3. Sau khi đạt chất lượng mới tăng tốc độ crawl/dịch và giảm chi phí API.
4. Chương người dùng đang chờ phải được crawl và dịch trước tác vụ nền.
5. Giữ kiến trúc phù hợp app cá nhân 1–3 người; không fine-tune model và chưa thêm hạ tầng trả phí.

## 1.1. Vấn đề chất lượng hiện tại

Hệ thống đang giải bài toán cấp toàn truyện bằng ngữ cảnh quá cục bộ:

- `REGISTER_LINE` áp một luật lời dẫn chung cho mọi truyện: nam “hắn”, nữ “nàng”. Luật này chặn được một số lỗi nhưng không mô tả văn phong riêng của từng truyện.
- Glossary lưu tên, giới tính và một phần vai vế, nhưng chưa biểu diễn quan hệ **có hướng** giữa người nói và người nghe. Cùng một nhân vật có thể gọi sư phụ, đệ tử, kẻ thù và người yêu bằng bốn hệ xưng hô khác nhau.
- Hệ thống chưa có **narrator reference** theo nhân vật: người kể nên gọi nhân vật là “hắn”, “nàng”, “y”, “gã”, “lão”, “ông ta”, tên riêng hay chức danh trong từng ngữ cảnh. Regex hiện chỉ cấm một số từ nên có thể tạo sự đồng nhất giả trong một chương, nhưng chương sau model lại chọn cách gọi khác.
- Lời thoại đang được cho “linh hoạt theo bối cảnh”, nhưng pipeline không xác định chắc ai đang nói với ai. Model phải tự đoán lại ở mỗi chunk.
- Chỉ truyền summary và khoảng 350 ký tự đuôi bản dịch trước. Thông tin này không đủ giữ giọng nhân vật và quy ước xưng hô qua hàng chục chương.
- Quality fuse chủ yếu bắt lỗi bề mặt: còn chữ Hán, cụt, mất đoạn và một số đại từ sai trong lời dẫn. Nó không biết “ta”, “lão phu”, “lão tử”, “bổn tọa”, “vãn bối” có đúng người và đúng cảnh hay không.
- Regex sửa đại từ sau dịch có thể làm câu đúng hình thức nhưng gượng văn phong. Nó không thể sửa quan hệ ngữ dụng trong hội thoại.

Vì vậy, thêm nhiều câu cấm vào prompt chung sẽ sớm mâu thuẫn và không giải quyết được tính nhất quán dài hạn.

## 1.2. Hướng nghiên cứu phù hợp API

Nghiên cứu về document-level translation cho thấy context-aware prompting giúp tăng tính mạch lạc, đặc biệt ở dịch văn học và hiện tượng lược đại từ. Tuy nhiên, chỉ đưa thêm context thô không bảo đảm model thật sự dùng đúng ngữ cảnh; cần chọn đúng thông tin liên quan và kiểm tra constraint sau dịch.

Hướng áp dụng cho repo:

1. **Novel style bible:** một hồ sơ ngắn, bền vững theo truyện, mô tả ngôi kể, thời đại, mức Hán-Việt, nhịp câu, độ trang trọng, quy tắc lời dẫn và các cách dịch phải tránh.
2. **Narrator reference card:** mỗi nhân vật có cách người kể gọi mặc định và các biến thể được phép, tách khỏi đại từ trong lời thoại.
3. **Character voice card:** mỗi nhân vật có giới tính, tuổi/vai vế, tính khí, cách tự xưng mặc định, cách gọi người khác và vài câu mẫu đã được chấp nhận.
4. **Directed relationship:** lưu quy tắc theo hướng `speaker → addressee`, có phạm vi thời gian/chapter vì quan hệ có thể thay đổi sau khi bái sư, kết thù hoặc thân thiết hơn.
5. **Scene contract:** trước khi dịch một chunk có hội thoại khó, LLM trả JSON ngắn xác định người nói, người nghe, sắc thái và cặp xưng hô cần dùng. Đây là bản mở rộng của pass phân tích tên hiện có.
6. **Translate with constraints:** prompt dịch chỉ nhận style bible, narrator reference, voice card và relationship liên quan đến chunk; không nhét toàn bộ dữ liệu truyện.
7. **Validate then revise:** checker xác định constraint nào bị vi phạm. Chỉ khi có lỗi mới gọi LLM sửa đúng các câu liên quan, thay vì dịch lại cả chunk hoặc luôn chạy hai pass cho mọi đoạn.
8. **Human correction becomes memory:** góp ý của người đọc phải cập nhật narrator reference/voice/relationship/style rule để chương sau dùng lại, không chỉ string-replace chương cũ.

Đây là kiến trúc “translate → kiểm tra constraint → sửa có mục tiêu”, không phải self-reflection chung chung. Lượt sửa phải nhận danh sách lỗi cụ thể, câu nguồn liên quan và quy tắc bắt buộc.

## 2. Luồng hiện tại

### Crawl

`novelworker.main crawl` dựng adapter từ bảng `sources`, sau đó chạy vòng lặp 10 giây:

1. Ghi heartbeat.
2. Xử lý yêu cầu tìm truyện từ app.
3. Đồng bộ TOC lazy mà người dùng đang chờ.
4. Tải `content_zh` cho chương đã queued.
5. Đến chu kỳ discovery thì quét ranking/latest, truyện được theo dõi và canonical refresh.
6. Cập nhật sức khỏe từng nguồn.

Điểm tốt cần giữ:

- Adapter theo template và config trong DB; không tạo một class cho mỗi mirror.
- Ưu tiên tác vụ do người đọc kích hoạt trước discovery nền.
- TOC lazy và chỉ tạo stub cần thiết cho truyện chưa có người đọc.
- Ranking-first, lọc truyện mỏng, blacklist và canonical dedup.
- Retry HTTP và theo dõi sức khỏe nguồn đã có sẵn.

### Translate

`novelworker.main translate` tạo nhiều consumer thread:

1. Claim job qua RPC.
2. Gia hạn lease trong lúc LLM đang chạy.
3. Dịch metadata, chapter hoặc chạy patch/audit.
4. Với chapter: lấy glossary và ngữ cảnh chương trước, chia chunk, tùy trạng thái mà phân tích tên riêng trước, rồi dịch.
5. Quality fuse chặn bản dịch cụt, còn quá nhiều chữ Hán, mất đoạn hoặc lệch xưng hô.
6. Lưu bản dịch, xóa `content_zh`, cập nhật số chương và glossary.
7. Housekeeping requeue job kẹt, reset orphan, đổi priority theo hoạt động đọc và chạy audit định kỳ.

Điểm tốt cần giữ:

- Lease/reaper bảo vệ job khi worker chết hoặc LLM chạy lâu.
- Selective glossary injection thay vì gửi toàn bộ glossary.
- Model được pin theo truyện để giữ giọng dịch.
- Adaptive two-pass và quality fuse nằm ngay trong đường dịch.
- Cầu chì số chương/ngày và ưu tiên truyện đang được đọc.

## 3. Điểm nghẽn cần kiểm chứng

| Ưu tiên | Điểm nghẽn | Tác động dự kiến | Cách kiểm chứng |
|:--|:--|:--|:--|
| P0 | Không có baseline throughput đầy đủ | Dễ tối ưu nhầm chỗ | Ghi latency, queue age, request/chapter và token/chapter |
| P1 | Chapter chưa có `content_zh` vẫn có thể bị translator claim rồi defer | Tăng RPC và churn hàng đợi | Đếm số lần `MissingContentError` mỗi giờ |
| P1 | `bump_translated_count()` đếm lại mọi chapter done sau từng chương | Tải DB tăng theo kích thước truyện | Đo latency query theo số chương |
| P1 | Reprioritize tải toàn bộ pending job về Python mỗi phút | Nhiều dữ liệu và request thừa | Ghi số row đọc/cập nhật mỗi vòng |
| P1 | Lưu glossary và patch chapter theo từng row | Nhiều round-trip Supabase | Đếm request DB trên một chapter/job patch |
| P2 | Adapter và tác vụ dài chạy tuần tự | Một nguồn chậm chặn nguồn khác | Ghi thời gian mỗi source/cycle |
| P2 | Danh sách cần fetch giới hạn 200 row nhưng chưa có ordering rõ | Chapter ưu tiên có thể nằm ngoài batch | So queue priority với thời gian nhận `content_zh` |
| P2 | Retry HTTP chưa phân biệt 429, 5xx, lỗi parse và chương chưa sẵn sàng | Hammer nguồn hoặc retry sai loại lỗi | Thống kê lỗi theo HTTP status/source |
| P3 | Pass phân tích tên có thể tạo thêm một LLM call cho mỗi chunk | Giảm mạnh throughput dịch | Đo LLM calls/chapter và thời gian từng pass |
| P3 | Chunk dựa trên ký tự, trong khi giới hạn model theo token | Có thể chia quá nhiều hoặc chạm `max_tokens` | Ghi chunk count và finish reason |

Các mục trên là giả thuyết cần số liệu xác nhận, không phải lý do để refactor hàng loạt ngay.

## 4. Kế hoạch triển khai

### Pha Q0 — Bộ mẫu lỗi và chuẩn chất lượng

Trước khi đổi prompt/model, lấy 20–30 đoạn thật từ các truyện đang có, ưu tiên:

- Lời dẫn đang dùng lẫn “hắn/nàng” với “anh/cậu/cô”.
- Câu có 老夫, 老子, 本座, 本尊, 在下, 晚辈 và các tự xưng đặc thù.
- Hội thoại đổi người nghe hoặc đổi vai vế trong cùng chương.
- Một quan hệ thay đổi theo tiến triển truyện.
- Đoạn đúng nghĩa nhưng đọc gượng, quá sát chữ hoặc sai văn phong thể loại.

Mỗi case lưu:

- Đoạn Trung gốc và vài đoạn ngữ cảnh trước/sau.
- Bản dịch hiện tại.
- Lỗi cụ thể, không chỉ ghi “chưa hay”.
- Bản sửa mong muốn hoặc quy tắc cần tuân thủ.
- Nhân vật nói, người nghe, quan hệ và sắc thái nếu biết.

Chấm theo năm trục, mỗi trục 1–5:

1. Đúng nghĩa và không bỏ ý.
2. Xưng hô đúng trong lời dẫn.
3. Xưng hô đúng trong hội thoại.
4. Nhất quán với các chương trước.
5. Tự nhiên và đúng văn phong.

Không dùng BLEU làm tiêu chí chính. Metric tự động hiện có tiếp tục bắt lỗi kỹ thuật; quyết định chất lượng văn học dựa trên bộ case cố định và đánh giá người đọc.

**Hoàn thành khi:** có bộ regression chứa đúng các lỗi người dùng đang gặp và chạy lại được với mọi prompt/model ứng viên.

### Pha Q1 — Style bible và bộ nhớ xưng hô theo truyện

Thêm dữ liệu tối thiểu, tránh thiết kế knowledge graph tổng quát:

- `novels.translation_style`: JSON style bible ngắn.
- Mở rộng glossary hoặc bảng nhỏ cho `character_voice`, gồm `narrator_term`, `narrator_aliases_allowed` và `narrator_terms_forbidden`.
- Bảng/quy ước `speaker_id`, `addressee_id`, `self_term`, `address_term`, `valid_from_chapter`, `evidence` cho quan hệ có hướng.

Khởi tạo style bible một lần từ metadata + 1–3 chương đầu, sau đó chỉ cập nhật khi có bằng chứng mới. Không cho model tự ghi đè quy tắc đã được người dùng duyệt.

Style bible cần trả lời ngắn gọn:

- Ngôi kể và đại từ lời dẫn.
- Bối cảnh: cổ trang, tu tiên, đô thị, võ hiệp hoặc pha trộn.
- Mức dùng từ Hán-Việt và độ trang trọng.
- Nhịp văn: gọn, hài, lạnh, trang trọng, khẩu ngữ…
- Các quy tắc tuyệt đối và các ví dụ câu đã được duyệt.

Character voice/relationship phải phân biệt:

- Cách nhân vật tự xưng với từng nhóm người.
- Cách gọi đối phương.
- Cách người kể gọi nhân vật phải là trường riêng, không suy ra từ cách nhân vật tự xưng.
- Trạng thái tạm thời của cảnh: giả trang, nổi giận, công khai thân phận, nói mỉa…

Narrator reference cần có các quy tắc:

- Mỗi nhân vật chính có một cách gọi mặc định xuyên truyện, ví dụ `hắn`, `nàng`, `y` hoặc tên riêng.
- Biến thể như `gã`, `lão`, `thiếu niên`, `nữ tử` chỉ dùng khi đó là góc nhìn/sắc thái có chủ ý, không được model đổi ngẫu nhiên để “đa dạng câu chữ”.
- Khi một đoạn có nhiều nhân vật cùng giới, ưu tiên tên/chức danh để tránh đại từ mơ hồ; không ép mọi câu đều thành `hắn/nàng`.
- Cách gọi có thể thay đổi theo POV. Nếu truyện đổi điểm nhìn, scene contract phải ghi rõ người kể đang bám góc nhìn của ai.
- Tên riêng và đại từ phải được luân phiên tự nhiên; mục tiêu là nhất quán về định danh, không phải lặp máy móc cùng một đại từ.

**Hoàn thành khi:** cùng một chapter dịch lại nhiều lần vẫn giữ cặp xưng hô chính; chương sau không phải đoán lại các quan hệ đã biết.

### Pha Q2 — Scene contract và prompt dịch mới

Tái sử dụng pass `_analyze_names` hiện có. Khi chunk có hội thoại hoặc thực thể chưa rõ, pass phân tích trả JSON gồm:

```json
{
  "speakers": [
    {
      "speaker": "Nhân vật A",
      "addressee": "Nhân vật B",
      "self_term": "lão phu",
      "address_term": "tiểu tử",
      "tone": "khinh miệt",
      "evidence_zh": "老夫...小子"
    }
  ],
  "narrator_references": [
    {
      "character": "Nhân vật A",
      "term": "hắn",
      "allowed_variants": ["tên riêng", "chức danh"],
      "forbidden": ["anh", "cậu"]
    }
  ],
  "point_of_view": "ngôi ba giới hạn — bám Nhân vật A",
  "new_facts": [],
  "uncertain": []
}
```

Nguyên tắc:

- Giữ nguyên nghĩa của các tự xưng có dụng ý; `老夫`, `老子` không được tự động rút thành “ta”.
- Không lấy cách tự xưng trong thoại làm đại từ của người kể. Nhân vật tự xưng “lão tử” vẫn có thể được người kể gọi là “hắn”, tên riêng hoặc chức danh.
- Không hardcode rằng một chữ Trung luôn có một bản Việt. Cách dịch phụ thuộc người nói, người nghe, thời đại và sắc thái.
- Nếu không xác định được người nói/nghe, đánh dấu `uncertain`; prompt dịch phải ưu tiên cách trung tính, không tự tạo quan hệ.
- Chỉ đưa các voice/relationship liên quan đến chunk vào prompt.
- Thêm 2–4 example tốt lấy từ chính các chương đã được người dùng chấp nhận của truyện đó; đây là retrieval nhỏ theo nhân vật/quan hệ, không cần vector DB ở quy mô hiện tại.

Prompt dịch tách rõ bốn khối:

1. Style bible của truyện.
2. Nhân vật và quan hệ liên quan.
3. Scene contract của chunk.
4. Nội dung cần dịch và output contract hiện tại.

**Hoàn thành khi:** bộ case Q0 cải thiện rõ ở hội thoại và văn phong, parser `SUMMARY/GLOSSARY_JSON` vẫn hoạt động.

### Pha Q3 — Kiểm tra và sửa có mục tiêu

Sau lượt dịch, checker chạy theo hai tầng:

1. Python bắt constraint chắc chắn: thiếu bản dịch của tự xưng quan trọng, dùng đại từ lời dẫn bị cấm, glossary sai, còn chữ Hán, mất đoạn.
2. Chỉ khi case mơ hồ về speaker/style mới gọi LLM reviewer với source, translation và scene contract.

Reviewer không được viết lại tùy ý. Nó trả JSON:

- Câu vi phạm.
- Quy tắc bị vi phạm.
- Bản sửa tối thiểu.
- Confidence.

Chỉ áp dụng tự động lỗi confidence cao và có thể đối chiếu source/constraint. Lỗi style mơ hồ được ghi để người dùng duyệt hoặc dùng khi đánh giá prompt, tránh “LLM tự chấm rồi tự khen”.

**Hoàn thành khi:** giảm lỗi xưng hô mà không làm tăng hallucination/bỏ ý; lượt reviewer chỉ phát sinh cho case khó.

### Pha Q4 — Benchmark model/prompt qua cùng API

Chạy cùng bộ Q0 trên các model API miễn phí/đang có quyền dùng. Không chọn model bằng một chương đẹp nhất; so median và lỗi tệ nhất.

So sánh:

- Prompt hiện tại.
- Style bible + relationship context.
- Style bible + scene contract.
- Translate + targeted revision.

Chốt một cấu hình chính theo chất lượng; throughput và token là tiêu chí phụ. Model pinning theo truyện vẫn được giữ. Chỉ đổi model cho truyện sau khi benchmark và retranslate một đoạn nối để kiểm tra giọng.

### Pha P0 — Baseline hiệu năng và metric tối thiểu

Không cài thêm hệ thống monitoring. Tận dụng log, `worker_heartbeat`, `model_health` và RPC tổng hợp.

Ghi được các số sau:

- Queue depth theo `type`, `status` và nhóm priority.
- Tuổi job pending/running cũ nhất.
- Thời gian từ enqueue đến có `content_zh`, và từ enqueue đến dịch xong.
- Crawl request/phút và chương crawl thành công/phút theo source.
- Chương dịch/giờ theo model/key slot.
- LLM latency, request/chapter, token/chapter và chunk/chapter.
- Số lần retry, defer vì thiếu raw content và requeue vì stale lease.
- Tỷ lệ fail theo source, HTTP status, model và loại quality fuse.

Baseline tối thiểu nên chạy 24 giờ hoặc đủ một chu kỳ có cả discovery, đọc thật và dịch nhiều chunk.

**Hoàn thành khi:** có một bảng trước tối ưu với p50/p95 latency và throughput; xác định được ba nút thắt lớn nhất.

### Pha P1 — Giảm tải DB và churn hàng đợi

Thực hiện lần lượt, đo lại sau từng mục:

1. Sửa RPC claim để job chapter chỉ được claim khi chapter đã có `content_zh`, hoặc biểu diễn rõ trạng thái `waiting_content`.
2. Sắp thứ tự chương cần fetch theo priority và thời gian enqueue.
3. Gộp lưu translation, hoàn tất job và cập nhật translated count trong một RPC transaction.
4. Thay việc đếm lại toàn bộ chapter bằng cập nhật atomic hoặc trigger DB.
5. Chuyển reprioritize sang một RPC SQL thay vì kéo toàn bộ pending jobs về Python.
6. Batch insert glossary terms và batch update khi patch nhiều chương.

Migration mới phải dùng số tiếp theo trong `supabase/migrations/`; không sửa migration đã push và không tự `db push`.

**Hoàn thành khi:** không còn claim/defer lặp vì thiếu raw content; số request DB/chapter giảm; trạng thái chapter/job không lệch khi một bước ghi thất bại.

### Pha P2 — Cô lập và tăng throughput crawl

1. Giữ request trong mỗi source tuần tự để không hammer site, nhưng cho mỗi source có worker/loop độc lập.
2. Duy trì bốn tầng ưu tiên:
   - TOC và chapter người dùng đang chờ.
   - Truyện được theo dõi hoặc đang đọc.
   - Canonical refresh.
   - Discovery nền.
3. Thêm rate limit và exponential backoff riêng từng source; tôn trọng `Retry-After` khi có 429.
4. Circuit breaker tạm nghỉ source lỗi liên tiếp rồi tự probe lại; không yêu cầu restart chỉ để nguồn được thử lại.
5. Với adapter hỗ trợ được, refresh TOC từ watermark/chapter cuối thay vì tải lại toàn mục lục.
6. Giữ session riêng theo adapter/source; không dùng chung session giữa các thread nếu thư viện không bảo đảm thread-safe.

Không thêm async framework ở pha này. Thread hiện có đủ vì tác vụ chủ yếu chờ mạng và số source nhỏ.

**Hoàn thành khi:** một source timeout không làm tăng latency của source khác; chapter ưu tiên không phải chờ discovery dài; số request TOC giảm mà không bỏ sót chương mới.

### Pha P3 — Tăng throughput translate sau khi chất lượng đạt chuẩn

Chuẩn bị một tập benchmark cố định gồm:

- Chương ít tên riêng.
- Chương mở đầu có nhiều nhân vật/thuật ngữ.
- Chương dài nhiều chunk.
- Chương ngôi thứ nhất và chương nhiều hội thoại.
- Chương từng bị fuse/audit đánh lỗi.

So sánh ba chế độ:

1. Two-pass hiện tại.
2. One-pass dùng glossary hiện có.
3. Adaptive: chỉ phân tích tên khi glossary còn nghèo hoặc chunk có dấu hiệu chứa nhiều thực thể mới.

Metric bắt buộc:

- Thời gian/chapter.
- LLM calls/chapter.
- Prompt và completion tokens/chapter.
- Tỷ lệ còn chữ Hán, mất đoạn, lặp cụm và lệch glossary.
- Tỷ lệ retry do quality fuse.
- Độ ổn định tên riêng/xưng hô qua các chương liên tiếp.

Chỉ triển khai adaptive one/two-pass nếu giảm ít nhất 20% request hoặc thời gian mà không làm xấu các quality metric. Sau đó mới cân nhắc:

- Chia chunk theo ước lượng token nếu dữ liệu cho thấy chạm trần output hoặc chia thừa.
- Tăng concurrency nếu NVIDIA key còn RPM và p95 latency không tăng mạnh.
- Rút gọn context chỉ khi benchmark chứng minh summary/tail hiện tại tốn token đáng kể.

Không mở fallback sang model khác một cách âm thầm vì sẽ làm đổi giọng trong cùng truyện.

**Hoàn thành khi:** throughput tăng có số đo, quality gate không giảm và model pinning vẫn được giữ.

### Pha P4 — Độ bền và regression check

Mỗi logic không tầm thường để lại một test nhỏ, tập trung vào:

- Claim không lấy chapter chưa có raw content.
- Hoàn tất translation/job/count là atomic.
- Priority đúng khi có người đang đọc.
- Source chậm không chặn source khác.
- 429 dùng đúng thời gian backoff.
- Adaptive two-pass giảm call nhưng vẫn tuân thủ glossary.
- Parser vẫn giữ contract `SUMMARY` và `GLOSSARY_JSON`.
- Reaper không lấy lại job còn đang gia hạn lease.

Sau mỗi pha:

```powershell
$env:PYTHONIOENCODING='utf-8'
E:\Novel_Project\.venv\Scripts\python.exe -m py_compile <cac-file-python-da-sua>
E:\Novel_Project\.venv\Scripts\python.exe -m pytest worker\test
```

Nếu sửa adapter, chạy thêm smoke test với nguồn thật. Nếu sửa translate, dịch thử một chương ngắn và một chương nhiều chunk, rồi kiểm tra trực tiếp output thay vì chỉ nhìn trạng thái `done`.

Khi triển khai worker lên VPS cần chạy lại:

```bash
git pull
cd worker
docker compose up -d --build
docker compose logs -f crawler translator
```

Container `Up` chưa đủ để kết luận worker khỏe; phải kiểm tra log và `worker_heartbeat`.

## 5. Thứ tự ưu tiên đề xuất

1. Q0: dựng bộ mẫu lỗi thật và thang chấm chất lượng.
2. Q1: style bible + character voice + quan hệ có hướng.
3. Q2: scene contract và prompt dịch mới.
4. Q3: kiểm tra/sửa có mục tiêu.
5. Q4: benchmark model và chốt pipeline chất lượng.
6. P0–P4: chỉ bắt đầu tối ưu hiệu năng sau khi pipeline vượt chuẩn Q0.

Không làm ngay: Redis/message broker, Kubernetes, crawler browser-based đại trà, framework async mới hoặc hệ metrics riêng. Chỉ xem xét khi quy mô thực tế vượt giới hạn của loop + Supabase queue hiện tại.

## 6. Thông tin cần chốt trước khi triển khai

- [x] Mục tiêu ưu tiên: chất lượng dịch, văn phong và xưng hô nhất quán toàn truyện.
- [ ] Chọn 2–3 truyện đại diện và cung cấp khoảng 20 đoạn đang dịch lỗi/gượng để dựng bộ Q0.
- [ ] Với từng đoạn, nếu có thể ghi bản sửa mong muốn hoặc ít nhất chỉ rõ ai nói với ai.
- [ ] Có muốn cho phép người dùng duyệt/chỉnh style bible và quan hệ nhân vật trong app, hay giai đoạn đầu chỉ quản trị trong DB?
- [ ] VPS hiện có bao nhiêu CPU/RAM?
- [ ] Có bao nhiêu NVIDIA API key đang hoạt động và quota thực của từng key?
- [ ] Mục tiêu chapter dịch/ngày và số nguồn crawl là bao nhiêu?
- [ ] Có chấp nhận tạo migration/RPC mới để tối ưu DB không? Agent chỉ tạo file, không tự push DB.

## 7. Bảng ghi kết quả

| Metric | Baseline | Sau P1 | Sau P2 | Sau P3 | Mục tiêu |
|:--|--:|--:|--:|--:|--:|
| Enqueue → có `content_zh` p50/p95 | | | | | |
| Enqueue → dịch xong p50/p95 | | | | | |
| Chương crawl thành công/giờ | | | | | |
| Chương dịch/giờ | | | | | |
| DB requests/chapter | | | | | |
| LLM calls/chapter | | | | | |
| Tokens/chapter | | | | | |
| Retry/defer mỗi 100 chapter | | | | | |
| Quality fuse fail rate | | | | | |
| Glossary adherence | | | | | |

## 8. Tài liệu nghiên cứu tham khảo

- [Document-Level Machine Translation with Large Language Models — EMNLP 2023](https://aclanthology.org/2023.emnlp-main.1036/): context-aware prompt và đánh giá hiện tượng diễn ngôn ở cấp tài liệu.
- [Efficiently Exploring Large Language Models for Document-Level Machine Translation with In-context Learning — ACL 2024](https://aclanthology.org/2024.findings-acl.646/): chọn context liên quan, summary và demonstration giúp tính mạch lạc, lược đại từ và dịch văn học.
- [Context-Aware or Context-Insensitive? — MT Summit 2025](https://aclanthology.org/2025.mtsummit-1.10/): cảnh báo LLM có context dài nhưng không nhất thiết dùng đúng context cho đại từ.
- [Terminology-Aware Translation with Constrained Decoding and LLM Prompting — WMT 2023](https://arxiv.org/abs/2310.05824): kiểm tra constraint rồi refine giúp tăng tuân thủ thuật ngữ.
- [Translate-and-Revise: Boosting LLMs for Constrained Translation — 2024](https://arxiv.org/abs/2407.13164): lượt revision có constraint cụ thể cải thiện độ chính xác constraint so với prompt dịch thông thường.
- [How Good Are LLMs for Literary Translation, Really? — NAACL 2025](https://aclanthology.org/2025.naacl-long.548/): bản dịch LLM thường sát chữ và kém đa dạng hơn bản dịch người; metric tự động đơn lẻ không đủ đánh giá văn học.

## 9. Kết quả rà Internet và Hugging Face

### 9.1. Model và dataset có thể tận dụng

#### Mistral Small 4 trên NVIDIA NIM — giữ làm model chính để benchmark

Model đang cấu hình trong worker là `mistralai/mistral-small-4-119b-2603`. Model card hiện công bố:

- Context 262.144 token.
- Native JSON output/function calling.
- Có instant/reasoning mode và `reasoning_effort`.
- Free prototype endpoint đang khả dụng.

Repo hiện mới dùng chat completion dạng text, chưa khai thác structured output cho pass phân tích. Việc nên làm:

1. Probe endpoint hosted xem có nhận `guided_json` hoặc `response_format=json_schema` không.
2. Nếu có, dùng JSON schema cho scene contract, style extraction và reviewer; không dùng regex bóc JSON từ output tự do.
3. Benchmark `reasoning_effort=high` cho pass phân tích khó, nhưng dùng instant/low reasoning cho lượt dịch để tránh chậm và tránh model giải thích dài.
4. Không gửi context 256k chỉ vì model hỗ trợ. Context dài phải được chọn lọc theo nhân vật/quan hệ/cảnh.

Nguồn: [NVIDIA model card](https://build.nvidia.com/mistralai/mistral-small-4-119b-2603), [NVIDIA structured generation](https://docs.nvidia.com/nim/large-language-models/1.15.0/structured-generation.html).

#### Model Hugging Face chạy local — không triển khai

Đã khảo sát HachimiMT, VP-MT và MoxhiMT nhưng quyết định không dùng: các model chuyên Trung→Việt này phải tải về tự host, context ngắn và không giải quyết bài toán nhất quán toàn truyện. Dự án tiếp tục dùng NVIDIA API để tránh thêm runtime, RAM, dependency và nghĩa vụ vận hành model local.

#### Dataset Trung→Việt web novel — dùng cho evaluation/retrieval, không fine-tune

Các nguồn đáng xem:

- `ngocdang83/tran-vi-teacher`: khoảng 350k cặp strict-clean, đúng domain web novel nhưng là dữ liệu synthetic từ teacher model và có gated access.
- `kaihe/chinese_vietnamese_bilingual_wangwen`: dữ liệu song ngữ web novel cấp câu/chương, dung lượng khoảng 10,5 GB.

Ứng dụng cho repo:

- Lấy một tập nhỏ có kiểm tra license/provenance làm benchmark hoặc few-shot candidate.
- Không đưa thẳng hàng trăm nghìn mẫu vào app.
- Không coi bản synthetic là “ground truth” cho xưng hô; phải kiểm tra thủ công các case dùng làm demonstration.
- Ưu tiên example do chính người dùng sửa trong app vì đúng gu văn phong hơn dữ liệu đại trà.

Nguồn: [tran-vi-teacher dataset card](https://huggingface.co/datasets/ngocdang83/tran-vi-teacher), [Chinese–Vietnamese bilingual wangwen](https://huggingface.co/datasets/kaihe/chinese_vietnamese_bilingual_wangwen/tree/main).

### 9.2. Tối ưu pipeline dịch sau rà soát

#### Làm

1. Structured JSON cho analyzer/reviewer nếu NVIDIA hosted endpoint hỗ trợ.
2. Tách bốn loại memory:
   - thuật ngữ/tên;
   - narrator reference;
   - character voice;
   - directed relationship theo chapter range.
3. Retrieval không cần vector DB:
   - lọc theo novel;
   - khớp nhân vật/quan hệ xuất hiện trong chunk;
   - lấy tối đa 2–4 đoạn người dùng đã sửa gần nhất.
4. Giữ source span/evidence cho mỗi fact do LLM trích xuất. Fact không có evidence không được tự nâng thành rule bền vững.
5. Tách confidence:
   - `confirmed`: người dùng duyệt;
   - `observed`: suy ra rõ từ source;
   - `uncertain`: chỉ dùng trong scene hiện tại, không ghi đè memory.
6. Kiểm tra omission của các marker quan trọng như 老夫/老子/本座/本尊/在下/晚辈 bằng source-target constraint trước khi lưu.
7. Tạo targeted revision chỉ cho câu lỗi; giữ nguyên các câu đã đạt để tránh reviewer làm đổi giọng toàn đoạn.
8. Đánh giá văn phong bằng pairwise A/B mù trên bộ Q0, không yêu cầu người dùng chấm điểm tuyệt đối quá nhiều tiêu chí mỗi lần.

#### Benchmark trước

- Mistral current prompt vs scene-contract prompt.
- Instant vs reasoning cho analyzer; lượt dịch ưu tiên instant.
- 350 ký tự tail vs context retrieval theo nhân vật/quan hệ.
- One-pass vs targeted revision.

#### Không làm lúc này

- Fine-tune model.
- Vector database cho vài truyện.
- Gửi toàn bộ các chương trước vào context.
- Dùng một LLM khác để review mọi chunk bất kể có lỗi.
- Regex tự sửa toàn bộ xưng hô hội thoại.
- Tự động tin mọi quan hệ do model suy ra.

### 9.3. Tối ưu crawler sau rà soát

#### HTTP client

Giữ `curl_cffi`: thư viện hỗ trợ browser TLS fingerprint, HTTP/2/3, session và async; phù hợp các nguồn hiện tại hơn việc đổi sang `requests`. Không chuyển framework chỉ để có concurrency.

Nguồn: [curl_cffi documentation](https://curl-cffi.readthedocs.io/en/stable/).

#### Chính sách theo nguồn

Mỗi source cần state riêng:

- `next_allowed_at`.
- delay tối thiểu và delay hiện tại.
- số lỗi liên tiếp theo nhóm timeout/429/5xx/parser/not-ready.
- `Retry-After` gần nhất.
- circuit trạng thái closed/open/half-open.
- ETag/Last-Modified cho trang ranking/TOC nếu nguồn cung cấp.

Retry matrix:

| Lỗi | Xử lý |
|:--|:--|
| Connect/read timeout | Retry tối đa 2–3 lần, exponential backoff + jitter |
| 429 | Tôn trọng `Retry-After`; tạm dừng riêng source |
| 500/502/503/504 | Retry có backoff; không đánh parser hỏng |
| 404 chapter mới | `ChapterNotReady`, thử lại thưa hơn |
| 403/anti-bot | Mở circuit, không hammer; đánh dấu cần kiểm tra nguồn |
| 200 nhưng selector mất | Parser failure; lưu mẫu HTML/rút gọn hash để chẩn đoán, không retry dồn dập |
| 304 | Giữ dữ liệu cũ, không parse/upsert lại |

HTTP `Retry-After` và conditional request là cơ chế chuẩn; nếu site không hỗ trợ thì fallback về watermark hiện tại. Nguồn: [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html), [RFC 7232 conditional requests](https://www.rfc-editor.org/rfc/rfc7232.html).

#### Concurrency

- Một lane tuần tự cho mỗi source; nhiều source được chạy độc lập.
- Concurrency mặc định mỗi domain = 1.
- TOC/chapter người đọc được quyền chen trước discovery nhưng không phá delay của source.
- Mỗi adapter giữ session riêng. Không chia một session mutable cho nhiều thread khi chưa có test thread-safety.
- Chỉ cân nhắc `AsyncSession` sau khi source count/concurrency thực tế chứng minh thread loop không đủ.

#### Crawl ít hơn thay vì crawl nhanh hơn

1. Ranking/TOC gửi `If-None-Match` hoặc `If-Modified-Since` khi có validator.
2. Ưu tiên sitemap/feed nếu source có và được phép dùng.
3. Refresh canonical theo `last_checked_at`, activity và trạng thái ongoing.
4. Truyện completed không refresh thường xuyên.
5. Chỉ fetch full TOC khi watermark/incremental parse không đủ hoặc user yêu cầu.
6. Cache negative result ngắn hạn cho chapter chưa sinh, search rate-limited và truyện bị blacklist.
7. Tuân thủ `robots.txt` và lưu kết quả theo source; RFC 9309 quy định crawler phải áp dụng các rule parse được.

Nguồn: [RFC 9309 Robots Exclusion Protocol](https://www.rfc-editor.org/rfc/rfc9309.html).

#### Parser và dữ liệu

- Giữ template adapter hiện tại; selector/site config nằm ở bảng `sources` khi có thể.
- Với mỗi template, lưu 2–3 HTML fixture đã rút gọn cho meta, TOC, chapter nhiều trang và trang lỗi.
- Parser phải trả lỗi có loại, không chỉ `ValueError` chung.
- So content hash để tránh ghi lại chapter/metadata không đổi.
- Batch upsert và chỉ update field thực sự đổi.
- Cover fetch dùng conditional header/cache riêng, không tính vào source health.

#### Queue và Supabase

Queue table + RPC hiện tại đủ cho 1–3 người. PostgreSQL xác nhận `SKIP LOCKED` phù hợp cho nhiều consumer trên queue-like table; Supabase cũng có PGMQ nhưng chuyển queue lúc này không mang lại lợi ích tương xứng.

Việc cần làm:

- Atomic claim với priority + `FOR UPDATE SKIP LOCKED`.
- Không claim chapter chưa có `content_zh`.
- Visibility/lease và retry schedule nằm trong DB.
- Index theo điều kiện claim thật: status, available_at, priority, created_at.
- Batch heartbeat/metrics nếu round-trip trở thành bottleneck.

Không migrate sang PGMQ trừ khi queue hiện tại mất job, duplicate không kiểm soát hoặc cần nhiều loại consumer độc lập. Nguồn: [PostgreSQL `SKIP LOCKED`](https://www.postgresql.org/docs/18/sql-select.html), [Supabase Queues](https://supabase.com/docs/guides/queues).

## 10. Roadmap chốt một lần

| Thứ tự | Gói việc | Kết quả bắt buộc | Điều kiện qua cổng |
|:--|:--|:--|:--|
| 1 | Q0 corpus lỗi thật | 20–30 case xưng hô/văn phong có expected rule | Chạy lại tự động được |
| 2 | Probe API/model | Biết JSON schema, reasoning mode, token/rate limit thực | Có bảng capability, không đoán từ docs |
| 3 | Translation memory v2 | Style + narrator + voice + directed relationship + evidence | Rule confirmed không bị model ghi đè |
| 4 | Scene analyzer | JSON có speaker/addressee/POV/self/address term | Parse 100%, case uncertain không thành rule |
| 5 | Prompt dịch v2 | Context chọn lọc + few-shot do user sửa | Q0 tốt hơn prompt cũ |
| 6 | Validator/reviser | Bắt omission/xưng hô và sửa đúng câu lỗi | Không làm giảm fidelity/văn phong |
| 7 | Model/prompt benchmark | Các chế độ prompt/reasoning của Mistral qua NVIDIA API | Chọn một pipeline chính |
| 8 | Crawler resilience | Retry matrix, per-source circuit/rate state | Source lỗi không chặn source khác |
| 9 | Incremental crawl | Conditional GET/watermark/hash | Giảm fetch/upsert không đổi |
| 10 | DB/queue atomic | Claim đúng, không defer raw-missing, batch write | Không lệch job/chapter |
| 11 | Throughput tuning | Điều chỉnh chunk/concurrency sau cùng | Quality Q0 không giảm |

### Phạm vi bản triển khai đầu tiên

Để tránh làm một hệ thống quá lớn, bản đầu chỉ cần:

1. Một migration nhỏ cho style/narrator/voice/relationship.
2. Một JSON schema scene contract.
3. Một prompt dịch v2.
4. Một validator omission + narrator/dialogue constraints.
5. Một script benchmark Q0.
6. Retry classification và per-source cooldown trong crawler.

Sau khi sáu mục này có số liệu mới quyết định conditional GET, targeted reviewer và concurrency cao hơn.

## 11. Baseline thực tế ngày 2026-07-11

### 11.1. Dữ liệu đã dịch trong Supabase

Chạy `eval_translation.py --existing 12` trên 12 chương đầu thuộc 12 truyện, đều được dịch bởi `mistralai/mistral-small-4-119b-2603`.

Kết quả: **11 vấn đề máy bắt được / 12 chương**.

| Nhóm lỗi | Số case | Ví dụ |
|:--|--:|:--|
| Mất tự xưng có sắc thái | 4 | `老子` không còn “lão tử/ông đây/…”, `在下` không còn “tại hạ” |
| Đại từ người kể bị cấm | 3 | `cô ta`, `cô ấy` trong lời dẫn |
| Convert/cấu trúc gượng | 1 | “đối với hắn mà nói” |
| Lặp `hắn` dày trong câu | 2 | một câu có ít nhất ba lần `hắn` |
| Quá nhiều dấu cảm thán | 1 | một đoạn có hơn hai dấu `!` |

Tín hiệu narrator reference cũng cho thấy một số truyện trộn nhiều cách gọi:

- Novel 1033: `hắn=57`, `gã=33`.
- Novel 1030: `anh=7` trong lời dẫn.
- Novel 962: `hắn=15`, `y=7`, `anh=1`.
- Novel 969: `hắn=30`, `nàng=13`, `gã=1`, `cô=1`.

Các con số này chưa đủ kết luận mọi biến thể đều sai vì một chương có nhiều nhân vật. Chúng là tín hiệu để Q0/người đọc kiểm tra, không được auto-replace.

Artifact local: `worker/eval_out_baseline/report.json` và các cặp `n*_c*.txt`.

### 11.2. Tiêu chí evaluator đã bổ sung

`eval_translation.py` hiện kiểm tra thêm:

- Omission của `老夫`, `老子`, `本座`, `本尊`, `在下`, `晚辈`, `贫道`, `贫僧`, `哀家`, `朕`, `臣`.
- Thống kê đại từ người kể sau khi loại phần hội thoại.
- Một số dấu hiệu convert/gượng: “không khỏi”, “căn bản là”, “rốt cuộc là”, “trực tiếp + động từ”.
- Report JSON ghi `narrator_terms` từng chương.
- `--self-check` để kiểm tra evaluator mà không gọi DB/API.

Các rule mới là warning/evidence. Riêng văn phong vẫn cần đọc A/B; không dùng regex làm tiêu chuẩn cuối.

### 11.3. Benchmark NVIDIA bằng mẫu tổng hợp

Để không gửi chương riêng trong DB tới hàng loạt model, benchmark dùng một đoạn Trung văn tự tạo 291 ký tự, chứa:

- `老夫`, `老子`, `在下`, `本座`.
- Nam/nữ trong lời dẫn.
- Hai nhân vật nam cùng cảnh để thử mơ hồ đại từ.
- Thay đổi speaker/addressee và sắc thái kính trọng/khinh miệt.

Một số model được chạy lại do endpoint/runner warm-up. Kết quả vẫn chỉ để loại model hỏng rõ ràng; chưa đủ để đổi model production.

| Model | Latency quan sát | Kết quả lint |
|:--|--:|:--|
| `mistralai/mistral-small-4-119b-2603` | 6,1–9,2s | Sạch cơ học nhưng lần lượt bỏ `老夫` hoặc `老子` |
| `qwen/qwen3.5-397b-a17b` | 6,6–10,7s | Có lượt dùng `ông ta` trong lời kể; có lượt bỏ `本座` |
| `qwen/qwen3.5-122b-a10b` | 2,8–51,3s | Một lượt output rỗng; các lượt khác bỏ `本座`, latency dao động lớn |
| `qwen/qwen3-next-80b-a3b-instruct` | 20,8s | Bỏ `本座` |
| `google/gemma-4-31b-it` | 14,8–22,0s | Bỏ `本座` |
| `google/diffusiongemma-26b-a4b-it` | 2,0–3,5s | Không ổn định: một lượt còn 16,9% chữ Hán, lượt khác bỏ `老夫` |
| `deepseek-ai/deepseek-v4-pro` | 50,9s | Bỏ `本座`; quá chậm so với Mistral ở mẫu này |

Kết luận tạm thời:

- Chưa có ứng viên nào chứng minh tốt hơn Mistral hiện tại.
- Qwen 397B đáng giữ trong shortlist để chạy lại sau khi có prompt v2, nhưng hiện chưa vượt gate narrator reference và chưa nhanh hơn Mistral một cách ổn định.
- Gemma 4, DiffusionGemma, Qwen 122B/Next và DeepSeek V4 Pro không có lợi thế ở mẫu này.
- Không đổi production model từ kết quả một lượt.
- Các model còn lại trong shortlist chưa chạy vì phiên công cụ chạm giới hạn gọi ngoài; phải ghi là `not_run`, không xếp hạng.

Artifact local: các file JSON trong `worker/benchmark_out/` (batch1, batch1a, deepseek_pro, synthetic_one, qwen397, qwen122, gemma4, diffusiongemma...).

## 12. Bộ Q0 đầu tiên — feedback người đọc 2026-07-11

User đã đọc 7/12 file baseline (`worker/eval_out_baseline/feedback_user_2026-07-11.txt`, giữ local). Nhóm lỗi theo tần suất:

| Nhóm lỗi | Ví dụ | Đã xử lý |
|:--|:--|:--|
| "tôi/mình" trong lời kể ngôi nhất + độc thoại kỳ ảo (nhiều nhất, n962/n967) | "mình chết ngay lập tức" → "ta/lược" | Prompt + REGISTER_LINE: ngôi nhất/độc thoại kỳ ảo xưng "ta"; lint `mình` tự xưng trong thoại |
| "anh/chị/em/mày" trong thoại cổ trang (n967/n969/n974) | chị→tỷ, em→muội, mày→ngươi | Prompt + REGISTER_LINE: cấm trong thoại cổ trang; chửi mắng vẫn "ngươi" |
| "chẳng" rải khắp nơi (n969/n972/n974) | "chẳng thể sống nổi" → "không thể" | Prompt: mặc định "không"; lint đếm ≥4 lần/chương |
| Chữ đệm thừa "kia/chứ" (n967) | "chọn hết đi chứ" | Prompt: không rải chữ đệm gốc không nhấn |
| Lượng từ 一头 bê nguyên (n967) | "một đầu tam đầu ma long" | Prompt: 一头/一只→"một con"; lint "một đầu" |
| Tiếng Anh thường lọt (n967 "all-in") | → "tất tay/dốc hết" | Prompt: thêm ví dụ all-in |
| "Gia tộc Lạc" (n969) | → "Lạc Gia/Lạc thị" | Prompt + lint |
| Pinyin lọt (n987) | | Lint bắt macron/caron; dạng sắc/huyền trùng tiếng Việt phải đọc tay |
| Đảo thứ tự âm Hán-Việt (n967 "Hồn Võ Đại lục") | phải "Võ Hồn Đại Lục" | Prompt: giữ đúng thứ tự; tên đã sai trong glossary phải sửa glossary + patch |
| Người kể đổi cách gọi cùng nhân vật (n972 ông↔hắn) | | CHƯA — đúng bài narrator reference pha Q1 |
| Tên nhân vật dịch dính liền (n967 "Lạc A Phiêu Phàm Trần"), câu vô nghĩa (n987 d.258) | | CHƯA — lỗi cấp glossary/chương, sửa bằng patch/dịch lại chương đó |

Lưu ý vận hành: prompt mới chỉ ăn vào chương dịch MỚI; chương cũ muốn sạch phải dịch lại. pytest đã cài local (không đưa vào requirements worker — VPS không cần).

### 12.1. Lỗi tự tìm ở 5 file user chưa chấm (2026-07-12)

**Nặng nhất — n1052 (Lạc thị Tiên tộc): toàn bộ chương là PHIÊN ÂM Hán-Việt từng chữ**, không phải tiếng Việt ("chủ phong cao sủng nhập vân, thường niên vân vụ liễu nhiễu"). Fuse cũ lọt hoàn toàn vì 0% chữ Hán, độ dài/xuống dòng chuẩn. Đã thêm detector mật độ hư từ Hán-Việt (đích/chi/hữu/tắc/giai/nhi/liễu... đã loại từ ghép Việt) vào `check_translation`: đo trên 12 chương thật n1052 = 6,8%, các chương sạch ≤0,2%, ngưỡng 2%. Truyện 1052 cần **dịch lại toàn bộ** sau khi deploy.

Các lỗi khác đã vá vào prompt/lint:

| Lỗi | File | Xử lý |
|:--|:--|:--|
| 咳咳 → "Cough cough" (tượng thanh tiếng Anh) | n1007 | Prompt + lint |
| 呼 → "Hổ", 唉 → "Hừ" (sai loại âm) | n1033, n1030 | Prompt thêm ví dụ 呼→phù, 唉→haiz |
| "hắn" nhét vào lời tự nhủ ("Xem ra hắn thật sự đã tái sinh") | n1033 | Prompt |
| Chữ Hán sót lẻ dưới ngưỡng fuse 5% ("truyền来", "本该被永远囚禁在天牢") | n1007, n1033, n1030 | Lint bắt mọi chữ Hán còn sót |
| "Tổng cảm thấy" (总感觉) | n1007 | Lint + đã có luật convert |

Lỗi cấp glossary/truyện — không sửa được bằng prompt, cần sửa term + patch/dịch lại từng truyện:

- n1030: 叶凌 dịch "Hiệp Lăng" (phải **Diệp Lăng**); 魔物 → "mã vật" (phải **ma vật**); lời kể dùng "anh" xuyên suốt.
- n1043: 二娃子 (cậu bé chăn bò ~13 tuổi) dịch thành "**Lão Nhị**" + người kể gọi "lão" cả chương — sai tuổi nhân vật chính; 兰青 → "Lãm Thanh" (phải **Lan Thanh**); 狗蛋 → "Đồ Đản" (phải Cẩu Đản).
- n1007: 棒梗 và 傻柱 (hai nhân vật khác nhau) cùng bị dịch "**Thằng Trụ**"; 一大爷 → "Dượng" (phải "ông cả/Nhất đại gia"); lời kể dùng "cô ta" cho bà già (nên "mụ/bà ta" — chờ narrator reference Q1).
- n1033: "điện hạ công chúa" (phải "công chúa điện hạ"); "càn khôn phạm thượng" (以下犯上 = "phạm thượng").
- n1043: dịch ngược nghĩa "tiên sinh khó xử" thành "tiên sinh thương tình" (bịa ý) — loại lỗi chỉ người đọc/reviewer bắt được.
