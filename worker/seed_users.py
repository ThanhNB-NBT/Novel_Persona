"""Seed tài khoản demo + admin. Chạy 1 lần: python seed_users.py (idempotent).

Sau khi seed xong, tắt đăng ký trên Dashboard:
Authentication > Sign In / Providers > tắt "Allow new users to sign up".
"""
from novelworker.db import sb

# ponytail: password chung cho demo, đổi trên Dashboard nếu cần
ACCOUNTS = [
    ("demo1@novel.demo", "Demo@123", "Demo 1", None),
    ("demo2@novel.demo", "Demo@123", "Demo 2", None),
    ("demo3@novel.demo", "Demo@123", "Demo 3", None),
    ("demo4@novel.demo", "Demo@123", "Demo 4", None),
    ("admin@novel.demo", "Admin@Novel#2026", "admin_system", {"role": "admin"}),
]


def main() -> None:
    for email, password, name, app_meta in ACCOUNTS:
        try:
            sb().auth.admin.create_user(
                {
                    "email": email,
                    "password": password,
                    "email_confirm": True,
                    "user_metadata": {"full_name": name},
                    **({"app_metadata": app_meta} if app_meta else {}),
                }
            )
            print(f"OK  {email}")
        except Exception as e:
            if "already" in str(e).lower():
                print(f"SKIP {email} (đã tồn tại)")
            else:
                raise


if __name__ == "__main__":
    main()
