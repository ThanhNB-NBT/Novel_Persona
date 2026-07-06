-- Job 'patch': vá chương đã dịch bằng string-replace khi glossary có term sửa (wrong_vi → correct_vi)
alter type job_type add value if not exists 'patch';
