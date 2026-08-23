"""Regression tests for the metadata-only, description-only experience."""

import pathlib


BIN_PATH = pathlib.Path(__file__).resolve().parents[1] / "bin" / "omarchy-youtube-suggester"


def test_engine_has_no_transcription_or_agent_path():
    source = BIN_PATH.read_text(encoding="utf-8")
    for removed_symbol in (
        "fetch_captions",
        "fetch_whisper",
        "cmd_summarize",
        "_build_summary_prompt",
        "opencode",
        "grok",
        "crush",
        "_agent_reply",
        "AI_AGENT_COMMANDS",
    ):
        assert removed_symbol not in source


def test_metadata_items_keep_description_fields():
    source = BIN_PATH.read_text(encoding="utf-8")
    assert '"meta_description": description' in source
    assert '"description": ""' in source
    assert "No description available." in source
