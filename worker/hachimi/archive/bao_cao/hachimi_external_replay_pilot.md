# Pilot fine-tune Hachimi với replay văn học ngoài repo

## Kết luận

**Không dùng checkpoint C cho production và không trộn thêm corpus ngoài ở vòng kế tiếp.**

Checkpoint C tăng độ gần tham chiếu, nhưng làm xưng hô kém ổn định hơn và vẫn lỗi
dấu thoại. Đây là lỗi người đọc nhận ra ngay, nên mức tăng similarity không đủ để
được coi là thắng.

## Dữ liệu ngoài đã kiểm tra

### `moa/Chinese-Vietnamese-literature`

- Giấy phép khai báo: `CC-BY-SA-4.0`.
- 396.307 dòng gốc; 244.105 dòng qua gate hình thức.
- Có lệch alignment thật. Ví dụ nguồn
  `掌柜的知道遇到硬茬儿了，连声说道：“值值值！”` bị ghép với câu Việt nói về
  chủ quán làm ăn, trong khi bản dịch tương ứng nằm ở các hàng phía sau.
- Không đủ sạch để làm gold.

Đã dịch chéo 5.000 cặp bằng Hachimi gốc, giữ 2.000 cặp có similarity cao nhất
(`>= 0,7642`) làm replay thử nghiệm. Gate của trainer tiếp tục loại 15 nguồn trùng
gold/eval, còn 1.985 cặp.

### `kaihe/chinese_vietnamese_bilingual_wangwen`

- Giấy phép khai báo: `Apache-2.0`.
- Đúng domain truyện mạng, có dữ liệu theo chương và câu.
- Mẫu chapter đầu đã có câu Việt thêm thông tin không tồn tại trong nguồn và bỏ
  thông tin nguồn. Vì mục tiêu hiện tại là dịch đủ, corpus này không đạt chuẩn
  để làm gold hoặc replay tự động.

## Cấu hình pilot C

- Base: `ngocdang83/HachimiMT-60-zh-vi`.
- Gold đã duyệt: 200 cặp, trọng số `x1`.
- Replay ngoài đã sàng: 1.985 cặp.
- Tổng train: 2.185 cặp; 1 epoch; learning rate `1e-5`; batch hiệu dụng 32.
- 69 bước; thời gian train 433,5 giây; eval loss 1,437.
- Tổng thời gian gồm tải/cache và xuất CT2: 578,4 giây trên máy local.

## Kết quả 60 cảnh khóa

Similarity dùng `SequenceMatcher(..., autojunk=False)`. Bản cũ bật `autojunk`
làm sai điểm ở câu dài; đây vẫn chỉ là chỉ báo ký tự, không thay cho đọc nghĩa.

| Model | Similarity TB | Quote lỗi | Số lỗi | Hán sót | Đại từ hiện đại | Đệm thừa |
|---|---:|---:|---:|---:|---:|---:|
| Hachimi gốc | 0,7050 | 6 | 0 | 0 | 15 | 3 |
| Production hiện tại | 0,7107 | 2 | 0 | 0 | 15 | 2 |
| A — gold x1 | 0,7085 | 5 | 0 | 0 | 15 | 2 |
| B — gold x3 | 0,7149 | 6 | 0 | 0 | 15 | 1 |
| C — replay ngoài | **0,7192** | 5 | 0 | 0 | **21** | 3 |

C so với Hachimi gốc: thắng/hòa/thua similarity `38/6/16`.

C so với production hiện tại: thắng/hòa/thua similarity `39/2/19`.

### Theo nhóm

| Nhóm | Base | Current | A | B | C |
|---|---:|---:|---:|---:|---:|
| `dialogue_register` | 0,6677 | 0,6695 | 0,6597 | **0,6797** | 0,6707 |
| `domain_terms` | 0,7453 | 0,7538 | 0,7536 | **0,7673** | 0,7650 |
| `natural_vi` | 0,6674 | 0,6717 | 0,6730 | 0,6748 | **0,6834** |
| `number_negation` | 0,7484 | 0,7588 | 0,7609 | 0,7622 | **0,7738** |
| `quote_author` | 0,6871 | 0,7004 | 0,6883 | 0,6958 | **0,7012** |
| `semantic_context` | 0,7142 | 0,7099 | 0,7154 | 0,7094 | **0,7211** |

## Lỗi đọc tay khiến C bị loại

Nguồn:

> 二叔虽然实力不强，给你搞不到那种血脉珍稀的妖兽，但是精英级血脉的妖兽幼崽还是能搞到的，你喜欢什么妖兽，我去给你找？

Tham chiếu đúng quan hệ:

> “Thực lực của nhị thúc tuy không mạnh... Ngươi thích loại yêu thú nào?
> Ta sẽ đi tìm cho ngươi.”

C làm đảo chủ thể và quan hệ:

> “... Cháu thích yêu thú gì, để cháu đi tìm cho cháu nhé?”

C còn sinh `cậu`, `tôi`, `cháu`, dùng lẫn dấu `“...”` và `"..."`, và có năm
cảnh quote không cân. Vì vậy checkpoint này không giải quyết đúng lỗi người dùng
đang ưu tiên.

## Quyết định dữ liệu vòng kế tiếp

1. Không gọi corpus ngoài là gold; không tiếp tục tăng lượng replay.
2. Giữ 200 gold hiện tại làm nền, nhưng không tăng trọng số mù.
3. Tập trung duyệt thêm các cảnh thật trong DB, ưu tiên:
   - quan hệ người nói/người nghe và chủ thể hành động;
   - một lượt thoại dài có câu dẫn;
   - cảnh nhiều nhân vật;
   - câu dài cần giữ đủ ý, phủ định và số;
   - dấu thoại và lời tác giả.
4. Chỉ train lại khi có tối thiểu 600–1.200 cặp gold dài đã đọc tay. Mục tiêu
   chấp nhận: không tăng đại từ hiện đại, quote lỗi không cao hơn production hiện
   tại, rồi mới xét similarity và độ tự nhiên.

