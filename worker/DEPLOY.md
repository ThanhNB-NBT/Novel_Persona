# Deploy worker lên VPS

Worker chỉ cần ~1GB RAM (chủ yếu chờ mạng). Gói VPS bé nhất là dư.

## 1. Mua VPS

- **Vultr / DigitalOcean** — $5-6/tháng, chọn region **Singapore** (gần VN + cào site TQ ổn). Đăng ký dễ, nhận thẻ VN + PayPal.
- **Hetzner** — ~€3.8/tháng (CX22: 2 vCPU/4GB), rẻ nhất nhưng server ở EU.

Chọn OS: **Ubuntu 24.04 LTS**.

## 2. Setup lần đầu (SSH vào VPS, chạy 1 lần)

```bash
# Cài docker
curl -fsSL https://get.docker.com | sh

# Lấy code (dùng deploy key hoặc HTTPS + token nếu repo private)
git clone <repo-url> ~/Novel_Project
cd ~/Novel_Project/worker

# Tạo .env — copy nội dung từ file worker/.env trên máy local
nano .env

# Chạy
docker compose up -d --build
```

`restart: unless-stopped` đã có trong compose → worker tự dậy sau khi VPS reboot.

## 3. Vận hành

```bash
docker compose logs -f            # xem log
docker compose logs -f translator # log 1 service
git pull && docker compose up -d --build   # cập nhật code
```

## 4. Bảo mật tối thiểu

```bash
# Tắt login bằng password, chỉ dùng SSH key (làm sau khi đã add key)
sudo sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# Firewall: chỉ mở SSH (worker không nhận kết nối vào)
sudo ufw allow OpenSSH && sudo ufw --force enable
```
