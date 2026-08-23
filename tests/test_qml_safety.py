"""QML safety tests for BarWidget.qml (review 53185066:775-785).

Remote video titles/descriptions are untrusted and must never be rendered
with QML Text's default AutoText (which interprets HTML and can load remote
resources via <img src>). All Text/TextEdit elements that display external
content must use textFormat: Text.PlainText / TextEdit.PlainText.
"""

import pathlib
import re

QML_PATH = pathlib.Path(__file__).resolve().parents[1] / "BarWidget.qml"


def parse_qml_text_blocks(qml_text: str):
    """Yield (start_line, block_text) for each Text { ... } and TextEdit { ... }."""
    pattern = re.compile(r"\bText(?:Edit)?\s*\{")
    for m in pattern.finditer(qml_text):
        start = m.start()
        depth = 0
        end = None
        for i in range(m.end() - 1, len(qml_text)):
            ch = qml_text[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        block = qml_text[start : end + 1] if end is not None else qml_text[start : start + 800]
        line_no = qml_text[:start].count("\n") + 1
        yield line_no, block


def test_all_text_elements_use_plain_text():
    qml = QML_PATH.read_text(encoding="utf-8")
    missing = []
    for line_no, block in parse_qml_text_blocks(qml):
        # Extract first text: line for diagnostics
        first_text = next((l.strip() for l in block.splitlines() if "text:" in l), "?")[:80]
        has_plain = "textFormat" in block and "PlainText" in block
        if not has_plain:
            missing.append(f"L{line_no}: {first_text}")
    assert not missing, (
        "These Text/TextEdit blocks lack textFormat: Text.PlainText / TextEdit.PlainText "
        "(AutoText would interpret HTML and fetch remote <img>). Missing:\n" + "\n".join(missing)
    )


def test_popup_title_uses_plain_text():
    """Regression for the exact review range 775-785 (popupTitle)."""
    qml = QML_PATH.read_text(encoding="utf-8")
    # Find the block that renders root.popupTitle
    found = False
    for line_no, block in parse_qml_text_blocks(qml):
        if "root.popupTitle" in block:
            found = True
            assert "Text.PlainText" in block, (
                f"popupTitle at L{line_no} must use Text.PlainText to avoid AutoText HTML handling; "
                f"block:\n{block[:500]}"
            )
            assert "textFormat" in block
            break
    assert found, "Could not find Text block rendering root.popupTitle — has the QML been refactored?"


def test_description_textedit_uses_plain_text():
    """The description popup must render remote content as plain text."""
    qml = QML_PATH.read_text(encoding="utf-8")
    found = False
    for line_no, block in parse_qml_text_blocks(qml):
        if "id: descriptionText" in block:
            found = True
            assert "TextEdit.PlainText" in block or "Text.PlainText" in block, (
                f"descriptionText TextEdit at L{line_no} must use textFormat: TextEdit.PlainText; block:\n{block[:600]}"
            )
            break
    assert found, "Could not find TextEdit id: descriptionText"


def test_no_rich_text_on_untrusted_fields():
    """Ensure no Text rendering title or description uses RichText."""
    qml = QML_PATH.read_text(encoding="utf-8")
    for line_no, block in parse_qml_text_blocks(qml):
        lower = block.lower()
        # If block renders untrusted fields, it must not use RichText/StyledText/AutoText
        untrusted_tokens = ("popuptitle", "modeldata.title", "modeldata.description", "meta_description")
        if any(tok in lower for tok in untrusted_tokens):
            assert "RichText" not in block, f"L{line_no} renders untrusted data with RichText: {block[:300]}"
            assert "StyledText" not in block
            assert "AutoText" not in block


def test_bracket_sanity_no_auto_text_default():
    """Count Text blocks vs PlainText occurrences — every Text should have an explicit format."""
    qml = QML_PATH.read_text(encoding="utf-8")
    blocks = list(parse_qml_text_blocks(qml))
    plain_count = sum(1 for _, b in blocks if "PlainText" in b)
    # All blocks must be plain; allow no exceptions
    assert plain_count == len(blocks), f"{len(blocks)-plain_count} Text block(s) lack PlainText"
