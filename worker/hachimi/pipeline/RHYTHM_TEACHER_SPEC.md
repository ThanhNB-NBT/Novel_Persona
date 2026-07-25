# Spec cho thầy dịch — gold NHỊP CÂU

## Bối cảnh (đọc trước khi làm)

Model MT 57M của dự án dịch **1:1 theo dấu câu tiếng Trung**: nguyên một chuỗi phẩy dài
của câu Trung được bê nguyên thành một câu tiếng Việt lê thê. Đo trên 60 cảnh khóa: bản
tham chiếu tốt có 4,3 câu/cảnh và 0,93 dấu phẩy mỗi câu, bản model có 2,7 câu và 3,0 dấu
phẩy — cùng lượng nội dung, khác nhịp. Vòng train này dạy model **ngắt câu như tiếng Việt**.

Vì vậy giá trị của mỗi dòng anh viết ra nằm ở chỗ nó **tách được chuỗi phẩy**, không phải
ở chỗ nó "sát nghĩa hơn".

## Đầu vào / đầu ra

- Đầu vào: `dataset/rhythm_pool.jsonl`, mỗi dòng `{zh, vi_model, novel_id, chapter_index, line_index}`.
  `vi_model` là bản model hiện tại, chỉ để tham khảo và để biết cần sửa gì.
- Đầu ra: `dataset/rhythm_labeled.jsonl`, **giữ nguyên mọi trường của dòng gốc và thêm `vi`**
  = bản viết lại. Ghi nối tiếp (append) theo lô để không mất tiến độ.
- Không sửa `zh`. Không đổi thứ tự dòng. Không bỏ dòng nào (dòng nào không cứu được thì
  vẫn ghi ra với `vi` tốt nhất có thể, cổng sẽ tự loại).

## Luật viết

1. **Ngắt câu**: chuỗi phẩy tiếng Trung phải thành **nhiều câu tiếng Việt**. Mục tiêu là
   mỗi dấu 。 của nguồn cho ra khoảng 2 câu tiếng Việt. Câu tiếng Việt hiếm khi nên dài
   quá 140 ký tự.
2. **Xưng hô cố định**: lời kể ngôi ba nam = `hắn`, nữ = `nàng`; ngôi nhất = `ta`; đối
   thoại xưng `ta` — gọi `ngươi`. **TUYỆT ĐỐI KHÔNG** dùng `tôi, mình, bạn, cậu, cháu,
   anh ta, cô ta, cô ấy, ông ta, bà ta` — kể cả trong lời thoại, kể cả khi nhân vật đang
   nói với người trên (二叔 vẫn là "nhị thúc", nhưng người nói xưng `ta` và gọi `ngươi`).
3. **Giữ nguyên**: mọi con số (kể cả số trong tên kỹ năng/vật phẩm), mọi tên riêng đã có
   trong `vi_model` (giữ đúng cách đọc Hán-Việt của bản đó — đừng tự đổi cách phiên).
4. **Không thêm không bớt ý**, không tự đệm hư từ cảm thán (`nhé, nha, đấy, đâu`) nếu
   nguồn không có.
5. **Văn phong cổ phong/tiên hiệp**, thuật ngữ Hán-Việt giữ như bản model (khô lâu, linh
   khí, đan điền...). Từ gốc Tây phiên qua Trung thì trả về Tây (哥布林 = goblin, 丧尸 =
   zombie). 枪 trong bối cảnh cổ trang là **thương**, chỉ bối cảnh hiện đại/bắn súng mới là
   **súng**.
6. Dấu ngoặc kép phải cân đôi. Không để sót chữ Hán trong bản Việt.

## Tự kiểm trước khi báo xong

```bash
python 09_gate_rhythm_gold.py
```

In ra số dòng đạt, tỷ lệ `câu VI / dấu 。 ZH` (mục tiêu ≈ 2,0) và lý do loại. Nếu lý do
`chưa tách chuỗi phẩy thành câu` chiếm nhiều thì viết lại các dòng đó — đó là chính mục
tiêu của vòng này, không được bỏ qua. File loại nằm ở `dataset/rhythm_rejects.jsonl`.
