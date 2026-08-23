"""CLI/config tests for the metadata-only pipeline."""
import json
import pathlib
import subprocess
import sys

import pytest

BIN_PATH = pathlib.Path(__file__).resolve().parents[1] / "bin" / "omarchy-youtube-suggester"


def run_bin(*args, env=None):
    proc = subprocess.run(
        [sys.executable, str(BIN_PATH), *args],
        capture_output=True,
        text=True,
        timeout=15,
        env=env,
    )
    return proc


def test_config_has_no_ai_summary_setting(tmp_path):
    # Redirect HOME so config/state go to tmp
    import os

    config_path = tmp_path / ".config" / "youtube-suggester" / "config.json"
    config_path.parent.mkdir(parents=True)
    config_path.write_text(
        json.dumps(
            {
                "enable_ai_summary": True,
                "transcribe_whisper": True,
                "whisper_model": "base.en",
            }
        ),
        encoding="utf-8",
    )
    env = {**os.environ, "HOME": str(tmp_path)}
    proc = run_bin("config", "get", env=env)
    assert proc.returncode == 0, proc.stderr
    cfg = json.loads(proc.stdout)
    assert "enable_ai_summary" not in cfg


@pytest.mark.parametrize("command", ["summarize", "transcribe"])
def test_transcription_commands_removed(tmp_path, command):
    import os

    env = {**os.environ, "HOME": str(tmp_path)}
    proc = run_bin(command, "video-id", env=env)
    assert proc.returncode != 0
    assert "invalid choice" in proc.stderr


def test_config_default_interests_preserved(tmp_path, monkeypatch):
    import os

    monkeypatch.setenv("HOME", str(tmp_path))
    env = {**os.environ, "HOME": str(tmp_path)}
    proc = run_bin("config", "get", env=env)
    assert proc.returncode == 0
    cfg = json.loads(proc.stdout)
    # Default interests should still be present
    assert "interests" in cfg
    assert isinstance(cfg["interests"], list)
