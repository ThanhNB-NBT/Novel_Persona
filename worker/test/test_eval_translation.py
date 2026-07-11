from eval_translation import _dialogue_self_minh, _self_reference_omissions, lint, narrator_terms


def test_self_reference_omission():
    assert _self_reference_omissions("老夫不答应。", "Ta không đồng ý.")
    assert not _self_reference_omissions("老夫不答应。", "Lão phu không đồng ý.")


def test_narrator_terms_ignore_dialogue():
    assert narrator_terms('Hắn quay đi. “Lão tử không sợ!” Nàng im lặng.') == {
        "hắn": 1,
        "nàng": 1,
    }


def test_convertese_warning():
    assert any("không khỏi" in problem for problem in lint("他笑了。", "Hắn không khỏi bật cười."))


# feedback user 2026-07-11 (bộ Q0 đầu tiên)

def test_mot_dau_measure_word():
    assert any("một đầu" in p for p in lint("一头魔龙。", "Một đầu ma long kinh khủng."))
    assert not any("một đầu" in p for p in lint("首先。", "Một đầu tiên là vậy."))


def test_pinyin_leak():
    assert any("pinyin" in p for p in lint("狼牙棒。", "Cây lāng yá bàng."))


def test_chang_density():
    assert any("'chẳng'" in p for p in lint("。", "Chẳng ai. Chẳng thể. Chẳng còn. Chẳng biết."))
    assert not any("'chẳng'" in p for p in lint("。", "Chẳng ai tin nổi."))


def test_dialogue_self_minh():
    assert _dialogue_self_minh('“Mình chắc chắn đã bỏ lỡ điều gì đó.”')
    assert not _dialogue_self_minh('“Chúng mình đi thôi, của mình đây.”')
    assert not _dialogue_self_minh("Nàng nghĩ về chính mình đã từng.")


def test_gia_toc_style():
    assert any("gia tộc" in p for p in lint("洛家。", "Gia tộc Lạc không đồng ý."))
