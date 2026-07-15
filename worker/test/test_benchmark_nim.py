import json
from urllib.parse import parse_qs, urlsplit

from benchmark_nim import _catalog_url, _parse_preview_models


def test_parse_preview_models_keeps_catalog_order_and_api_name():
    page = json.dumps({"resultTotal": 2, "results": [{"resources": [
        {"displayName": "llama-3.3-70b-instruct",
         "labels": [{"key": "publisher", "values": ["meta"]}]},
        {"displayName": "mistral-small-4-119b-2603",
         "labels": [{"key": "publisher", "values": ["mistralai"]}]},
    ]}]})

    models, total = _parse_preview_models(page)

    assert total == 2
    assert models == [
        "meta/llama-3.3-70b-instruct",
        "mistralai/mistral-small-4-119b-2603",
    ]


def test_catalog_url_preserves_requested_filter():
    url = _catalog_url(page=2, page_size=100)
    query = json.loads(parse_qs(urlsplit(url).query)["q"][0])

    assert query["filters"] == [{"field": "nimType", "value": "nim_type_preview"}]
    assert query["orderBy"] == [{"field": "weightPopular", "value": "DESC"}]
    assert query["page"] == 2
    assert query["pageSize"] == 100
