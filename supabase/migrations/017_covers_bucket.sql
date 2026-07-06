-- Cache bìa: bucket Storage công khai để không phụ thuộc hotlink CDN nguồn (nguồn/CDN
-- chết hoặc chặn hotlink → Khám phá mất bìa hàng loạt). Worker (service_role) upload,
-- ai cũng đọc được qua public URL. public=true đủ cho đọc; service_role bỏ qua RLS khi ghi.
insert into storage.buckets (id, name, public)
values ('covers', 'covers', true)
on conflict (id) do nothing;
