"""Map template (sources.template) → class adapter. Thêm khuôn mới = 1 dòng."""
from __future__ import annotations

from .base import SourceAdapter
from .biquge import BiqugeAdapter, XinBiqugeAdapter
from .dingdian import DingdianAdapter
from .faloo import FalooAdapter
from .piaotia import PiaotiaAdapter
from .shuba import ShubaAdapter

TEMPLATE_REGISTRY: dict[str, type[SourceAdapter]] = {
    "biquge": BiqugeAdapter,
    "dingdian": DingdianAdapter,
    "faloo": FalooAdapter,
    "piaotia": PiaotiaAdapter,
    "shuba": ShubaAdapter,
    "xinbiquge": XinBiqugeAdapter,
}
