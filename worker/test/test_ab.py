"""Self-check bo A/B; khong goi DB hay LLM."""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.translator.ab import V2_DIRECTIVE, _self_check, render_html


def main() -> None:
    _self_check()
    assert "Không phóng tác" in V2_DIRECTIVE
    html = render_html([{"chapter_index": 1, "content_zh": "原文", "results": [
        {"variant": "current", "text": "Bản A", "model": "a"},
        {"variant": "v2", "text": "Bản B", "model": "b"},
        {"variant": "reference", "text": "Bản C", "model": "c"},
    ]}])
    assert "Bản A" in html and "Bản B" in html and "Bản C" in html and "原文" in html
    print("OK — test_ab pass")


if __name__ == "__main__":
    main()
