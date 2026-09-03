"""Bài kiểm chất lượng LLM dịch tay qua app — dựng đề dán vào, rồi chấm bản trả về.

Dùng khi muốn thử một model trên OpenCode desktop (hoặc bất kỳ giao diện chat nào): script
sinh MỘT khối văn bản dán thẳng vào phiên chat, model trả về các dòng đánh số, rồi script
chấm bằng đúng thước của dự án và đặt cạnh BẢN DỊCH NGƯỜI.

    python llm_probe.py --make                      # sinh đề → llm_probe_input.txt
    python llm_probe.py --score reply.txt --label "nemotron-3-ultra"
    python llm_probe.py --self-check

Vì sao chọn câu theo TRỤC chứ không lấy ngẫu nhiên: bốn trục dưới đây là chỗ các model hay
hỏng và cũng là chỗ dự án quan tâm. Lấy ngẫu nhiên thì phần lớn rơi vào câu dễ, model nào cũng
qua, không phân biệt được.

  1. `subject_drop` — nguồn LƯỢC CHỦ NGỮ (lời kể không có 他/她). Model hay tự bịa "Hắn/Nàng"
     rồi đoán giới sai. Đây là lỗi v6 nặng nhất.
  2. `gender`      — nguồn CÓ 他/她 rõ. Kiểm có giữ đúng giới không.
  3. `names`       — câu nhiều tên riêng. Kiểm phiên âm Hán-Việt TRỌN CỤM
                     (南宫正雄 → Nam Cung Chính Hùng). Model nhỏ hay ra "Nông Cung Chính Hùng".
  4. `dialogue`    — thoại có 我/你. Kiểm xưng hô ta-ngươi thay vì tôi-bạn.

Bản dịch NGƯỜI của chính những câu đó được giữ trong `llm_probe_key.jsonl` để so — bộ test
`clean_testset.jsonl` đã bị chặn khỏi corpus train nên không có chuyện học thuộc.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
DEFAULT_TESTSET = Path.home() / "hachimi-work/clean_testset.jsonl"
ZH_PRONOUN = re.compile(r"[他她它]")
ZH_NAME_HINT = re.compile(r"[一-鿿]{2,4}(?=道|说|问|看|走|笑)")
DIALOGUE = re.compile(r"[“「].*?[”」]", re.DOTALL)

HEADER = """Dịch từng dòng tiểu thuyết tiên hiệp Trung Quốc dưới đây sang tiếng Việt.

LUẬT BẮT BUỘC:
- Lời kể ngôi ba dùng "hắn" (nam) / "nàng" (nữ) / "y". TUYỆT ĐỐI CẤM: tôi, mình, cậu, anh ấy,
  cô ấy, anh ta, cô ta, ông ta, bà ta.
- Lời thoại: nhân vật tự xưng "ta", gọi đối phương "ngươi".
- Tên người / môn phái / công pháp / bảo vật: phiên âm Hán-Việt TRỌN CỤM.
  Ví dụ 南宫正雄 → Nam Cung Chính Hùng (KHÔNG phải "Nông Cung Chính Hùng"),
  九阳神功 → Cửu Dương Thần Công. Không dịch nghĩa, không dùng pinyin.
- Nếu dòng nguồn KHÔNG có chủ ngữ thì bản dịch cũng ĐỪNG tự thêm chủ ngữ.
- Văn phải là tiếng Việt trôi chảy, KHÔNG dịch máy móc từng chữ.

ĐỊNH DẠNG TRẢ VỀ (bắt buộc, sai định dạng là không chấm được):
- Mỗi dòng một bản dịch, giữ nguyên số thứ tự, dạng: `12. <bản dịch>`
- Không thêm lời mở đầu, không giải thích, không ghi lại nguyên văn tiếng Trung.

CÁC DÒNG CẦN DỊCH:
"""


def _metrics():
    spec = importlib.util.spec_from_file_location("epm", HERE / "eval_project_metrics.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["epm"] = module
    spec.loader.exec_module(module)
    return module


def classify(zh: str) -> str | None:
    """Xếp câu nguồn vào trục cần thử. None = câu thường, không dùng."""
    if len(zh) < 12 or len(zh) > 120:
        return None
    narration = DIALOGUE.sub("", zh)
    if DIALOGUE.search(zh) and re.search(r"[我你]", zh):
        return "dialogue"
    if ZH_PRONOUN.search(narration):
        return "gender"
    if len(ZH_NAME_HINT.findall(zh)) >= 1:
        return "names"
    if narration.strip():
        return "subject_drop"
    return None


def pick(rows: list[dict], per_axis: int) -> list[dict]:
    """Lấy đều cho MỖI trục; đi qua nhiều chương để không dồn vào một truyện."""
    epm = _metrics()
    buckets: dict[str, list[dict]] = {"subject_drop": [], "gender": [], "names": [], "dialogue": []}
    for row in rows:
        zh_lines = [m.group(0).strip() for line in row["zh"].split("\n") if line.strip()
                    for m in epm.SENT.finditer(line) if m.group(0).strip()]
        vi_lines = [line.strip() for line in (row.get("vi_human") or "").split("\n") if line.strip()]
        for index, zh in enumerate(zh_lines):
            axis = classify(zh)
            if not axis or len(buckets[axis]) >= per_axis:
                continue
            human = vi_lines[index] if index < len(vi_lines) else ""
            buckets[axis].append({"zh": zh, "vi_human": human, "axis": axis,
                                  "novel": row.get("novel_id"), "chapter": row.get("chapter_index")})
    out: list[dict] = []
    for axis in ("subject_drop", "gender", "names", "dialogue"):
        out.extend(buckets[axis])
    return out


def make(args) -> None:
    rows = [json.loads(line) for line in
            args.testset.read_text(encoding="utf-8").splitlines() if line.strip()]
    items = pick(rows, args.per_axis)
    lines = [f"{i}. {item['zh']}" for i, item in enumerate(items, 1)]
    args.out.write_text(HEADER + "\n".join(lines) + "\n", encoding="utf-8")
    # File NGUỒN cho agent đọc: CHỈ có n + zh. Đáp án người dịch nằm ở file key riêng —
    # đưa nhầm file key cho model là tự tay làm rò bộ chấm.
    src = args.out.with_name("llm_probe_src.jsonl")
    src.write_text("".join(json.dumps({"n": i, "zh": item["zh"]}, ensure_ascii=False) + "\n"
                           for i, item in enumerate(items, 1)), encoding="utf-8")
    key = args.out.with_name("llm_probe_key.jsonl")
    key.write_text("".join(json.dumps({**item, "n": i}, ensure_ascii=False) + "\n"
                           for i, item in enumerate(items, 1)), encoding="utf-8")
    counts: dict[str, int] = {}
    for item in items:
        counts[item["axis"]] = counts.get(item["axis"], 0) + 1
    print(f"{len(items)} dòng · {counts}")
    print(f"→ ĐỀ dạng dán tay      : {args.out}")
    print(f"→ NGUỒN cho agent đọc  : {src}  (chỉ có n + zh)")
    print(f"→ đáp án người dịch: {key}")


RULES = """===== LUẬT DỊCH (bắt buộc) =====

VĂN PHONG: tiểu thuyết tiên hiệp/huyền huyễn, giọng cổ phong.

1. XƯNG HÔ TRONG LỜI KỂ (ngôi ba): dùng "hắn" (nam), "nàng" (nữ), "y".
   TUYỆT ĐỐI CẤM: tôi, mình, cậu, bạn, anh ấy, cô ấy, anh ta, cô ta, ông ta, bà ta.

2. XƯNG HÔ TRONG LỜI THOẠI: nhân vật tự xưng "ta", gọi đối phương "ngươi".
   Áp dụng cho MỌI thể loại, kể cả tình cảm — không dùng anh/em.

3. TÊN RIÊNG: phiên âm Hán-Việt TRỌN CỤM, viết hoa từng chữ.
   南宫正雄  -> Nam Cung Chính Hùng     (KHÔNG phải "Nông Cung Chính Hùng")
   黄礼严    -> Hoàng Lễ Nghiêm
   九阳神功  -> Cửu Dương Thần Công
   苍茫大荒  -> Thương Mang Đại Hoang
   Không dịch nghĩa tên riêng. Không dùng pinyin. Không giữ nguyên chữ Hán.

4. LƯỢC CHỦ NGỮ: nếu dòng nguồn KHÔNG có chủ ngữ (không có 他/她/我/你),
   thì bản dịch cũng ĐỪNG tự thêm chủ ngữ. Ví dụ:
   开口说道：\u201c你来了。\u201d  ->  Mở miệng nói: "Ngươi đến rồi."
   (KHÔNG dịch thành "Hắn mở miệng nói..." vì nguồn không nói ai)

5. GIỚI TÍNH: nguồn ghi 他 thì dịch "hắn", 她 thì dịch "nàng". Không đảo.

6. VĂN PHẢI TRÔI CHẢY. Không dịch máy móc từng chữ theo kiểu "convert".
   Sai:  他的肌肉鼓动 -> "hắn đích cơ nhục cổ động"
   Đúng: 他的肌肉鼓动 -> "cơ bắp của hắn rung động"

7. Không bỏ sót ý, không thêm ý không có trong nguồn.

===== HẾT LUẬT ====="""

AGENT_PROMPT = """Bạn có quyền đọc/ghi file trên máy này. Làm đúng ba việc sau, không hỏi lại.

1. ĐỌC file: {src}
   Mỗi dòng là JSON: {{"n": <số thứ tự>, "zh": "<câu tiếng Trung>"}}
   Có đúng {count} dòng.

2. DỊCH từng câu sang tiếng Việt theo LUẬT bên dưới.

3. GHI ra file: {reply}
   Mỗi dòng đúng dạng:  <n>. <bản dịch>
   Đủ {count} dòng, giữ nguyên số thứ tự, KHÔNG kèm nguyên văn tiếng Trung,
   KHÔNG thêm tiêu đề hay lời bình.

{rules}

Bắt đầu ngay. Xong thì chỉ báo "đã ghi N dòng"."""


def write_prompt(label: str, src: Path, out_dir: Path) -> tuple[Path, Path]:
    """Sinh prompt cho MỘT công cụ, ghi reply ra file riêng — chạy song song khỏi đè nhau."""
    count = sum(1 for line in src.read_text(encoding="utf-8").splitlines() if line.strip())
    reply = out_dir / f"llm_probe_reply_{label}.txt"
    prompt = out_dir / f"PROMPT_{label}.txt"
    prompt.write_text(AGENT_PROMPT.format(src=src, reply=reply, count=count, rules=RULES),
                      encoding="utf-8")
    return prompt, reply


REPLY_LINE = re.compile(r"^\s*(\d+)[.):]\s*(.+?)\s*$")


def parse_reply(text: str) -> dict[int, str]:
    """Bóc `12. bản dịch`. Bỏ dòng không đúng dạng thay vì đoán thứ tự."""
    out: dict[int, str] = {}
    for line in text.split("\n"):
        match = REPLY_LINE.match(line)
        if match:
            out[int(match.group(1))] = match.group(2).strip()
    return out


def score(pairs: list[tuple[str, str]], label: str) -> dict:
    epm = _metrics()
    from novelworker.translator import lint

    invents = modern = han = lint_hits = 0
    for zh, vi in pairs:
        invents += epm._invents_subject(zh, vi)
        modern += len(epm.MODERN.findall(vi))
        han += len(epm.HAN.findall(vi))
        lint_hits += lint.lint_score(None, vi)
    n = max(1, len(pairs))
    return {"model": label, "câu": len(pairs),
            "bịa chủ ngữ/100 câu": round(invents / n * 100, 2),
            "đại từ hiện đại/100 câu": round(modern / n * 100, 2),
            "Hán sót/100 câu": round(han / n * 100, 2),
            "lint/100 câu": round(lint_hits / n * 100, 2)}


def do_score(args) -> None:
    key = {json.loads(line)["n"]: json.loads(line) for line in
           args.key.read_text(encoding="utf-8").splitlines() if line.strip()}
    reply = parse_reply(args.score.read_text(encoding="utf-8"))
    matched = [(key[n]["zh"], vi) for n, vi in reply.items() if n in key]
    missing = sorted(set(key) - set(reply))
    print(f"bóc được {len(reply)}/{len(key)} dòng"
          + (f" · THIẾU: {missing[:12]}{'…' if len(missing) > 12 else ''}" if missing else ""))
    if not matched:
        raise SystemExit("Không bóc được dòng nào — kiểm định dạng trả về `12. bản dịch`")
    results = [score(matched, args.label)]
    human = [(key[n]["zh"], key[n]["vi_human"]) for n in reply if n in key and key[n]["vi_human"]]
    if human:
        results.append(score(human, "BẢN DỊCH NGƯỜI (mốc)"))
    keys = [k for k in results[0] if k not in ("model", "câu")]
    width = max(len(r["model"]) for r in results) + 2
    print(f"\n{'model':{width}}" + " ".join(f"{k:>26s}" for k in keys))
    for row in results:
        print(f"{row['model']:{width}}" + " ".join(f"{row[k]:26.2f}" for k in keys))
    print("\nThấp hơn là tốt hơn ở cả bốn cột.")
    print("\n— vài dòng để đọc tay —")
    for n in sorted(reply)[:5]:
        if n in key:
            print(f"  [{key[n]['axis']}] zh : {key[n]['zh'][:64]}")
            print(f"          ra : {reply[n][:74]}")
            print(f"          gốc: {key[n]['vi_human'][:74]}")


def _self_check() -> None:
    assert classify("他走进房间，环视四周，然后坐了下来。") == "gender"
    assert classify("开口说道，声音低沉而缓慢，令人心生寒意。") in ("subject_drop", "names")
    assert classify("短") is None
    got = parse_reply("1. Hắn bước vào phòng.\nlung tung\n2) Nàng cười.\n12: Ba.")
    assert got == {1: "Hắn bước vào phòng.", 2: "Nàng cười.", 12: "Ba."}, got
    clean = score([("他走进房间。", "Hắn bước vào phòng.")], "sạch")
    assert clean["đại từ hiện đại/100 câu"] == 0 and clean["Hán sót/100 câu"] == 0, clean
    dirty = score([("他走进房间。", "Anh ấy bước vào 房间.")], "bẩn")
    assert dirty["đại từ hiện đại/100 câu"] > 0 and dirty["Hán sót/100 câu"] > 0, dirty
    assert "Nam Cung Chính Hùng" in HEADER and "12. <bản dịch>" in HEADER
    # Prompt cho agent: mỗi nhãn ghi ra file KHÁC nhau, chạy song song khỏi đè.
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        src = tmp / "llm_probe_src.jsonl"
        src.write_text('{"n": 1, "zh": "他走。"}\n{"n": 2, "zh": "她笑。"}\n', encoding="utf-8")
        p1, r1 = write_prompt("opencode", src, tmp)
        _p2, r2 = write_prompt("gemini", src, tmp)
        assert r1 != r2, (r1, r2)
        body = p1.read_text(encoding="utf-8")
        assert str(src) in body and str(r1) in body and "đúng 2 dòng" in body, body[:200]
        assert "Nam Cung Chính Hùng" in body and "hắn đích cơ nhục" in body
    print("llm_probe OK")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--make", action="store_true")
    ap.add_argument("--score", type=Path, help="file chứa bản trả về của model")
    ap.add_argument("--label", default="model")
    ap.add_argument("--testset", type=Path, default=DEFAULT_TESTSET)
    ap.add_argument("--out", type=Path,
                    default=Path.home() / "hachimi-work/scratch/llm_probe_input.txt")
    ap.add_argument("--key", type=Path,
                    default=Path.home() / "hachimi-work/scratch/llm_probe_key.jsonl")
    ap.add_argument("--per-axis", type=int, default=15)
    ap.add_argument("--prompt", metavar="LABEL",
                    help="sinh prompt cho một công cụ (opencode/antigravity/...), reply ghi riêng")
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args(argv)
    if args.self_check:
        _self_check()
    elif args.prompt:
        src = args.out.with_name("llm_probe_src.jsonl")
        prompt, reply = write_prompt(args.prompt, src, args.out.parent)
        print(f"→ prompt: {prompt}")
        print(f"→ model sẽ ghi ra: {reply}")
        print(f"chấm: llm_probe.py --score {reply} --label {args.prompt}")
    elif args.score:
        do_score(args)
    else:
        make(args)


if __name__ == "__main__":
    main()
