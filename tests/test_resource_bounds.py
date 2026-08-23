"""Regression tests for bounded remote output and persisted state."""

import importlib.machinery
import importlib.util
import json
import os
import pathlib
import sys


BIN_PATH = pathlib.Path(__file__).resolve().parents[1] / "bin" / "omarchy-youtube-suggester"
SERVICE_PATH = BIN_PATH.parents[1] / "Service.qml"


def load_engine():
    loader = importlib.machinery.SourceFileLoader("youtube_suggester_engine", str(BIN_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


def test_child_output_is_drained_into_bounded_buffers():
    engine = load_engine()
    proc, limited = engine.run_bounded(
        [
            sys.executable,
            "-c",
            "import sys; sys.stdout.write('o' * 1000000); sys.stderr.write('e' * 1000000)",
        ],
        timeout=10,
        stdout_limit=1024,
        stderr_limit=512,
    )

    assert limited
    assert len(proc.stdout) <= 1024
    assert len(proc.stderr) <= 512


def test_persisted_json_is_rejected_before_unbounded_parse(tmp_path):
    engine = load_engine()
    path = tmp_path / "state.json"
    path.write_bytes(b"{" + b"x" * engine.MAX_PERSISTED_JSON_BYTES)

    assert engine.load_json(path, {"safe": True}) == {"safe": True}


def test_remote_metadata_strings_are_capped_before_state_retention():
    engine = load_engine()
    item = engine._base_item(
        {
            "id": "a" * 11,
            "title": "t" * 10000,
            "channel": "c" * 10000,
            "duration": 30,
            "views": 1,
        },
        {
            "tags": ["g" * 10000] * 100,
            "description": "d" * 100000,
        },
        ["tag"],
    )

    assert len(item["title"]) <= engine.MAX_TITLE_CHARS
    assert len(item["channel"]) <= engine.MAX_CHANNEL_CHARS
    assert len(item["meta_description"]) <= engine.MAX_DESCRIPTION_CHARS
    assert len(item["tags"]) <= engine.MAX_TAGS
    assert all(len(tag) <= engine.MAX_TAG_CHARS for tag in item["tags"])


def test_state_serialization_has_an_aggregate_ceiling():
    engine = load_engine()
    item = {
        "id": "a" * 11,
        "title": "title",
        "channel": "channel",
        "meta_description": "d" * engine.MAX_DESCRIPTION_CHARS,
        "description": "s" * 1000,
        "tags": ["tag"],
        "keyword_scores": {"tag": 1},
    }
    state = engine.bound_state(
        {
            "stage": "done",
            "recommendations": [item] * engine.MAX_STATE_RECORDS,
            "pool": [item] * engine.MAX_STATE_RECORDS,
        }
    )

    payload = json.dumps(state, indent=2, ensure_ascii=False).encode("utf-8")
    assert len(payload) <= engine.MAX_STATE_BYTES
    assert all(
        len(record["meta_description"]) <= engine.MAX_DESCRIPTION_CHARS
        for record in state["recommendations"] + state["pool"]
    )


def test_qml_process_output_is_not_collected_without_a_bound():
    source = SERVICE_PATH.read_text(encoding="utf-8")

    assert "StdioCollector" not in source
    assert "appendBoundedOutput" in source
    assert "maxStatusOutputChars" in source
    assert "maxErrorOutputChars" in source


def test_cookie_export_is_private_and_scoped(tmp_path, monkeypatch):
    engine = load_engine()
    monkeypatch.setattr(engine, "CONFIG_DIR", tmp_path / "config")
    monkeypatch.setattr(engine, "CACHE_DIR", tmp_path / "cache")
    monkeypatch.setattr(
        engine, "LEGACY_COOKIES_FILE", tmp_path / "cache" / "cookies.txt"
    )

    exported = engine._write_secure_cookie_file(["secret-cookie"])
    assert stat_mode(exported) == 0o600
    assert exported.read_text(encoding="utf-8") == "secret-cookie\n"

    monkeypatch.setattr(engine, "_AES", object())
    monkeypatch.setattr(engine, "export_browser_cookies", lambda _browser: exported)
    with engine.cookie_args("chromium") as args:
        assert args == ["--cookies", str(exported)]
        assert exported.exists()
    assert not exported.exists()


def test_legacy_cookie_file_is_removed_on_startup(tmp_path, monkeypatch):
    engine = load_engine()
    cache_dir = tmp_path / "cache"
    legacy = cache_dir / "cookies.txt"
    monkeypatch.setattr(engine, "CONFIG_DIR", tmp_path / "config")
    monkeypatch.setattr(engine, "CACHE_DIR", cache_dir)
    monkeypatch.setattr(engine, "LEGACY_COOKIES_FILE", legacy)
    cache_dir.mkdir()
    legacy.write_text("old-secret", encoding="utf-8")

    engine.ensure_dirs()

    assert not legacy.exists()


def stat_mode(path):
    return os.stat(path).st_mode & 0o777
