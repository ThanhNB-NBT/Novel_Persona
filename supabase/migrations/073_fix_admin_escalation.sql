-- FIX [CRITICAL] leo thang admin: guard_is_admin (011) chỉ chạy BEFORE UPDATE, nhưng
-- policy own_profile (001) là FOR ALL → user tự DELETE rồi INSERT lại hàng của mình với
-- is_admin=true, trigger không chạy khi INSERT nên qua mặt. Cho trigger chạy cả INSERT.
create or replace function guard_is_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Chỉ SQL console (auth.uid() null) hoặc service_role mới đặt/đổi được cờ.
  if tg_op = 'INSERT' then
    if new.is_admin
       and auth.uid() is not null
       and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
      new.is_admin := false; -- chèn hàng mới với cờ bật trái phép → ép về false
    end if;
  elsif new.is_admin is distinct from old.is_admin
     and auth.uid() is not null
     and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    new.is_admin := old.is_admin; -- nuốt thay đổi trái phép
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_is_admin on profiles;
create trigger trg_guard_is_admin before insert or update on profiles
  for each row execute function guard_is_admin();
