-- Model LLM + timeout chỉnh được từ tab Crawl, khỏi sửa .env rồi build + deploy.
--
-- Lý do: 2026-07-27 NVIDIA khai tử qwen/qwen3-next-80b không báo trước (410 Gone), mọi
-- job LLM chết cho tới khi có người ssh vào VPS đổi .env và build lại image. Model NIM
-- free đến rồi đi liên tục, nên thử con thay thế phải mất vài giây chứ không phải một
-- vòng deploy. Worker soi worker_settings mỗi 60s, tự dựng lại chain khi giá trị đổi.
--
-- Đo ngày 2026-07-27 để khỏi thử lại:
--   z-ai/glm-5.2                  Hán-Việt đúng ("Lâm Phong") nhưng 70-105s/call
--   openai/gpt-oss-120b           6-12s nhưng ra pinyin ("Lin Feng") + 3/4 chương lỗi JSON
--   minimaxai/minimax-m3          11s, sai chính tả Hán-Việt
--   deepseek-ai/deepseek-v4-flash 503/timeout, không gọi được
--   nvidia/nemotron-3-nano-30b    trả reasoning thay vì JSON

insert into worker_settings (key, value, note) values
  ('llm_model', 'z-ai/glm-5.2',
   'DỊCH · Model NVIDIA cho 3 việc phụ (trích tên, vá chữ Hán sót, dịch metadata). '
   'Đổi xong worker tự nhận trong 60s. Bản dịch chương do Hachimi lo, không ảnh hưởng.'),
  ('llm_timeout_sec', '90',
   'DỊCH · Timeout 1 call LLM (giây). Model chậm như glm-5.2 cần 150-180, con nhanh để 90.')
on conflict (key) do nothing;
