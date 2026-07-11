-- Q1 dịch thuật (docs/toi-uu-worker.md): style bible theo truyện + narrator reference
-- theo nhân vật. Worker tự sinh style bible MỘT lần từ metadata + đầu chương 1 rồi
-- tái dùng mọi chương; narrator_term do user/app chỉnh, worker không tự ghi đè.
alter table novels add column if not exists translation_style jsonb;
alter table glossary_terms add column if not exists narrator_term text;

comment on column novels.translation_style is
  'Style bible JSON {pov, setting, han_viet, tone, rules[]} — sinh 1 lần, chỉnh tay trong app';
comment on column glossary_terms.narrator_term is
  'Cách NGƯỜI KỂ gọi nhân vật (hắn/nàng/y/lão/tên riêng) — tách khỏi tự xưng trong thoại';
