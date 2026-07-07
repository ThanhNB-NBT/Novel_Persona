-- Trả đĩa sau khi 033 xoá ~840k stub: bảng chapters còn 18k dòng nhưng file vẫn 202MB.
-- db push chạy từng statement ngoài transaction nên vacuum full chạy được ở đây.
vacuum full chapters;
