"""Sinh file đầu vào benchmark Hy-MT2 từ các cặp chương đã lấy sẵn.

python make_hymt2_bench_input.py <pairs.json> <ra.jsonl>
"""
import io
import json
import sys


def main(pairs_path: str, out_path: str) -> None:
    pairs = json.load(io.open(pairs_path, encoding='utf-8'))
    rows = []
    for p in pairs:
        zh = (p.get('content_zh') or '').strip()
        ref = (p.get('content_vi') or '').strip()
        if len(zh) < 500 or len(ref) < 500:
            continue  # chương cụt không đủ đo tốc độ thực
        rows.append({
            'novel': p['title'],
            'novel_id': p['novel_id'],
            'chapter_index': p['index'],
            'title_vi': p['title_vi'],
            'zh': zh,
            'ref_vi': ref,  # bản Hachimi v5 đang production — chuẩn đối chiếu
        })
    with io.open(out_path, 'w', encoding='utf-8') as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
    print(f'{len(rows)} chương -> {out_path}')
    for r in rows:
        print(f"  {r['novel']} ch{r['chapter_index']}: zh={len(r['zh'])} ref_vi={len(r['ref_vi'])}")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
