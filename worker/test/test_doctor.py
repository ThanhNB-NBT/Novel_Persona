"""Self-check doctor: khung HTML phải sạch chữ, bóc theo thẻ lồng nhau, và ĐẶC BIỆT
là chốt chặn verify() — đề xuất sai của LLM không được lọt xuống production.

Không gọi LLM thật: mọi ca đều bơm sẵn danh sách đề xuất, nên chạy được trong CI.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")

from novelworker.crawler.doctor import diagnose, extract_by, html_skeleton, verify

VAN = "\n".join([
    "他缓缓睁开双眼，周身灵气涌动不息，仿佛整片天地都在为之震颤。",
    "这一刻，他终于明白了师父当年留下的那句话究竟是什么含义。",
    "山门之外，风雪未歇，来者何人尚且不得而知，只闻马蹄声声。",
    "殿中烛火摇曳，映着墙上斑驳的剑痕，那是百年前留下的旧迹。",
    "他起身推门，寒气扑面而来，衣袖被风吹得猎猎作响。",
    "远处山脊之上，隐约立着一道人影，久久不曾移动分毫。",
    "少年握紧手中长剑，眼神里再无半分犹疑之色。",
    "既然已经踏出这一步，便再没有回头的道理了。",
])  # cố tình > 200 ký tự: đó là ngưỡng thật của verify(), fixture phải vượt được

# Bẫy thật hay gặp: khối "đề cử" ở sidebar DÀI và toàn chữ Hán, qua được mọi ngưỡng
# độ dài/tỷ lệ Hán — chỉ luật rác điều hướng mới chặn được. Nếu bỏ luật đó, LLM rất
# dễ chỉ nhầm vào đây vì nó cũng là một khối chữ lớn.
_SIDEBAR = "推荐本书\n" + "\n".join(
    f"第{i}名 剑来风云录 作者不详 此书讲述少年入山求道之事迹十分精彩值得一读再读" for i in range(1, 9))

CHUONG_HTML = (
    "<html><body>"
    f'<div class="tuijian">{_SIDEBAR.replace(chr(10), "<br />")}</div>'
    '<div class="nav"><a>上一章</a><a>下一章</a><a>返回目录</a></div>'
    '<div class="txtnav">'
    "  <h1>第一章 出山</h1>"
    '  <div class="txtinfo"><span>2026-04-26</span></div>'
    "  <script>loadAdv(2,0);</script>"
    f"  {VAN.replace(chr(10), '<br />')}"
    '  <div class="contentadv"><script>loadAdv(7,3);</script></div>'
    "</div>"
    '<div class="footer">笔趣阁 手机阅读</div>'
    "</body></html>"
)


def main() -> None:
    # --- khung HTML: giữ thẻ, XOÁ chữ (rào an toàn: LLM không được thấy nội dung) ---
    sk = html_skeleton(CHUONG_HTML)
    assert "txtnav" in sk and "contentadv" in sk, "phải giữ được thẻ + thuộc tính"
    assert "睁开双眼" not in sk and "第一章 出山" not in sk, f"chữ bị lọt vào khung: {sk[:200]}"
    assert "ký tự]" in sk, "phải đánh dấu độ dài khối để LLM biết khối nào nhiều chữ"
    assert "loadAdv" not in sk, "script phải bị bóc khỏi khung"

    # --- bóc theo thẻ LỒNG NHAU: </div> đầu tiên không phải điểm dừng đúng ---
    got = extract_by(CHUONG_HTML, "class", "txtnav")
    assert "少年握紧手中长剑" in got, f"mất đoạn cuối do dừng sớm ở div con: {got!r}"
    assert "loadAdv" not in got, "script lọt vào text"

    # --- verify: 4 kiểu đề xuất sai đều phải bị chặn ---
    ok, _ = verify(VAN)
    assert ok, "văn thật phải qua"
    assert not verify("短")[0], "quá ngắn phải trượt"
    assert not verify("abc def ghi\n" * 40)[0], "không phải chữ Hán phải trượt"
    assert not verify(VAN + "\n上一章 下一章")[0], "dính rác điều hướng phải trượt"
    # đủ dài + toàn chữ Hán nhưng CHỈ 1 dòng → phải trượt vì lý do số dòng, không
    # phải vì độ dài (nhân 20 cho chắc chắn vượt ngưỡng 200 ký tự)
    mot_dong = "他睁开双眼，灵气涌动不息，天地为之震颤而已。" * 20
    assert len(mot_dong) > 200 and not verify(mot_dong)[0], "1 dòng phải trượt"

    # --- diagnose: đề xuất sai bị loại, đề xuất đúng được chọn, có nhật ký đã thử ---
    res = diagnose(CHUONG_HTML, candidates=[
        {"kind": "class", "value": "tuijian"},  # dài + toàn Hán, chỉ luật rác chặn được
        {"kind": "class", "value": "footer"},   # quá ngắn
        {"kind": "class", "value": "txtnav"},   # đúng
    ])
    assert res["ok"] and res["value"] == "txtnav", res
    assert len(res["da_thu"]) == 3, res["da_thu"]
    # sidebar phải bị loại ĐÚNG VÌ rác, không phải nhờ ăn may ngưỡng độ dài
    assert res["da_thu"][0]["ket_qua"].startswith("dính rác"), res["da_thu"][0]
    assert res["da_thu"][0]["so_ky_tu"] > 200, "bẫy phải đủ dài mới có giá trị test"
    assert "少年握紧手中长剑" in res["text"]

    # --- không đề xuất nào đạt → ok=False, KHÔNG được đoán bừa ---
    bad = diagnose(CHUONG_HTML, candidates=[{"kind": "class", "value": "nav"}])
    assert bad["ok"] is False and "text" not in bad, bad

    # --- đề xuất méo (thiếu trường / kind lạ) không được làm sập ---
    weird = diagnose(CHUONG_HTML, candidates=[
        {"kind": "xpath", "value": "//div"}, {"value": "thieu-kind"}, {},
        {"kind": "class", "value": "txtnav"},
    ])
    assert weird["ok"] and weird["value"] == "txtnav", weird

    # --- selector không tồn tại → chuỗi rỗng, không ném lỗi ---
    assert extract_by(CHUONG_HTML, "id", "khong-co-dau") == ""


if __name__ == "__main__":
    main()
    print("OK — doctor test pass")
