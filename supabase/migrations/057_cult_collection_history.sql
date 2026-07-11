-- Ghi nhận vật phẩm từng thu thập, kể cả sau khi đã dùng hoặc luyện hóa hết.
create table if not exists user_cult_collection (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id int not null references cult_items(id),
  first_collected_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

alter table user_cult_collection enable row level security;

drop policy if exists read_own_cult_collection on user_cult_collection;
create policy read_own_cult_collection on user_cult_collection
  for select to authenticated using (user_id = auth.uid());

-- Khôi phục lịch sử chắc chắn từ quà chương và giữ cả đồ đang có do nguồn khác cấp.
insert into user_cult_collection (user_id, item_id, first_collected_at)
select user_id, item_id, min(claimed_at)
from cult_claims
group by user_id, item_id
on conflict (user_id, item_id) do nothing;

insert into user_cult_collection (user_id, item_id)
select user_id, item_id from user_cult_items where qty > 0
on conflict (user_id, item_id) do nothing;

create or replace function cult_remember_collected_item() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.qty > 0 then
    insert into user_cult_collection (user_id, item_id)
    values (new.user_id, new.item_id)
    on conflict (user_id, item_id) do nothing;
  end if;
  return new;
end $$;

drop trigger if exists remember_cult_item on user_cult_items;
create trigger remember_cult_item
after insert or update of qty on user_cult_items
for each row execute function cult_remember_collected_item();
