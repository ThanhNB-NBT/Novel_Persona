-- P1-4 (docs/toi-uu-worker.md mục 13): bộ nhớ quan hệ xưng hô XUYÊN TRUYỆN.
-- Scene contract chỉ sống trong một chunk — cặp nhân vật đã chốt cách xưng hô ở
-- chương 3 có thể bị analyzer đoán khác ở chương 40. Bảng này ghi lại cặp
-- speaker→addressee kèm self/address term lần đầu chốt; worker ưu tiên bản đã lưu
-- (luật user: một cặp giữ NGUYÊN một kiểu xưng hô suốt truyện, chỉ đổi khi quan hệ đổi
-- — đổi thì sửa tay dòng tương ứng).
create table if not exists speaker_relations (
  novel_id bigint not null references novels(id) on delete cascade,
  speaker text not null,
  addressee text not null,
  self_term text,
  address_term text,
  tone text,
  last_chapter int,
  updated_at timestamptz not null default now(),
  primary key (novel_id, speaker, addressee)
);

comment on table speaker_relations is
  'Cách xưng hô đã chốt giữa từng cặp nhân vật (speaker nói với addressee) — worker ghi lần đầu gặp, đọc lại mọi chương sau';

alter table speaker_relations enable row level security;
-- worker dùng service key (bỏ qua RLS); client app chỉ cần đọc nếu sau này làm UI chỉnh
create policy "speaker_relations_read" on speaker_relations for select using (true);
