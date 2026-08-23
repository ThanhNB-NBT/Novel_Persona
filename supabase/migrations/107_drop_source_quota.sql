-- Dọn tính năng quota theo nguồn: trùng lặp với discover_new_per_cycle có sẵn
-- (user nhầm lẫn khi yêu cầu) → gỡ cột để khỏi thừa hai chỗ chỉnh một ý nghĩa.
alter table sources drop column if exists discover_quota;

-- Bổ sung số liệu cho màn Theo dõi VPS: swap + mạng (tổng tích luỹ + tốc độ giữa
-- 2 lần đẩy do worker tự tính).
alter table host_metrics add column if not exists swap_used_mb int;
alter table host_metrics add column if not exists net_rx_gb numeric;
alter table host_metrics add column if not exists net_tx_gb numeric;
alter table host_metrics add column if not exists net_rx_kbps numeric;
alter table host_metrics add column if not exists net_tx_kbps numeric;
