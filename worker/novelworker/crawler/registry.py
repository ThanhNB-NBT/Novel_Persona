"""Map template (sources.template) → class adapter. Thêm khuôn mới = 1 dòng."""
from __future__ import annotations

from .base import SourceAdapter
from .biquge import BiqugeAdapter, XinBiqugeAdapter
from .dingdian import DingdianAdapter

TEMPLATE_REGISTRY: dict[str, type[SourceAdapter]] = {
    "biquge": BiqugeAdapter,
    "dingdian": DingdianAdapter,
    "xinbiquge": XinBiqugeAdapter,
}
