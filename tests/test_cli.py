"""CLI/config tests for enable_ai_summary toggle and basic pipeline safety."""
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile

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


def test_config_enable_ai_summary_roundtrip(tmp_path, monkeypatch):
    # Redirect HOME so config/state go to tmp
    import os

    monkeypatch.setenv("HOME", str(tmp_path))
    # Need XDG config/cache dirs inside tmp HOMEDIR - bin uses Path.home()
    # Reload module after HOME change: just exercise CLI via subprocess with HOME override
    env = {**os.environ, "HOME": str(tmp_path)}
    proc = run_bin("config", "get", env=env)
    assert proc.returncode == 0, proc.stderr
    cfg = json.loads(proc.stdout)
    assert "enable_ai_summary" in cfg

    proc = run_bin("config", "set", "--enable-ai-summary", "false", env=env)
    assert proc.returncode == 0, proc.stderr
    cfg = json.loads(proc.stdout)
    assert cfg["enable_ai_summary"] is False

    proc = run_bin("config", "get", env=env)
    assert proc.returncode == 0
    cfg = json.loads(proc.stdout)
    assert cfg["enable_ai_summary"] is False

    proc = run_bin("config", "set", "--enable-ai-summary", "true", env=env)
    assert proc.returncode == 0
    cfg = json.loads(proc.stdout)
    assert cfg["enable_ai_summary"] is True


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
