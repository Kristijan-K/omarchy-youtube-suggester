"""Security regression tests for browser cookie and history access."""

import hashlib
import importlib.machinery
import importlib.util
import os
import pathlib
import sqlite3
import subprocess
import sys
import time

import pytest


BIN_PATH = pathlib.Path(__file__).resolve().parents[1] / "bin" / "omarchy-youtube-suggester"


def load_engine():
    loader = importlib.machinery.SourceFileLoader("youtube_suggester_security", str(BIN_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


@pytest.mark.parametrize(
    ("url", "expected"),
    [
        ("https://www.youtube.com/watch?v=abcdefghijk", "abcdefghijk"),
        ("https://m.youtube.com/shorts/abcdefghijk", "abcdefghijk"),
        ("https://youtu.be/abcdefghijk?t=2", "abcdefghijk"),
        ("https://evil.test/youtube.com/watch?v=abcdefghijk", None),
        ("https://youtube.com.evil.test/watch?v=abcdefghijk", None),
        ("https://youtube.com@evil.test/watch?v=abcdefghijk", None),
        ("https://youtu.be.evil.test/abcdefghijk", None),
        ("javascript:https://youtube.com/watch?v=abcdefghijk", None),
        ("file://youtube.com/watch?v=abcdefghijk", None),
        ("https://youtube.com/watch?v=abcdefghijé", None),
    ],
)
def test_video_id_requires_real_youtube_origin(url, expected):
    assert load_engine().video_id_from_url(url) == expected


def test_browser_file_open_is_nofollow_regular_owned_and_bounded(tmp_path):
    engine = load_engine()
    directory_fd = os.open(tmp_path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        regular = tmp_path / "History"
        regular.write_bytes(b"12345678")
        fd = engine._open_bounded_regular_at(directory_fd, regular.name, 8, required=True)
        assert os.read(fd, 8) == b"12345678"
        os.close(fd)

        oversized = tmp_path / "Oversized"
        oversized.write_bytes(b"123456789")
        with pytest.raises(ValueError):
            engine._open_bounded_regular_at(directory_fd, oversized.name, 8, required=True)

        target = tmp_path / "target"
        target.write_bytes(b"safe")
        (tmp_path / "link").symlink_to(target)
        with pytest.raises(OSError):
            engine._open_bounded_regular_at(directory_fd, "link", 8, required=True)

        os.mkfifo(tmp_path / "fifo")
        with pytest.raises(PermissionError):
            engine._open_bounded_regular_at(directory_fd, "fifo", 8, required=True)
    finally:
        os.close(directory_fd)


def test_cookie_export_bounds_rows_and_rejects_unsafe_authority(tmp_path, monkeypatch):
    engine = load_engine()
    root = tmp_path / "chromium"
    profile = root / "Default"
    profile.mkdir(parents=True)
    database = profile / "Cookies"
    con = sqlite3.connect(database)
    con.execute(
        "CREATE TABLE cookies (host_key, name, value, encrypted_value, path, expires_utc, is_secure)"
    )
    rows = [
        ("accounts.google.com", f"safe{i}", f"value{i}", b"", "/", 0, 1)
        for i in range(5)
    ]
    rows.extend(
        [
            ("youtube.com.evil.test", "evil", "stolen", b"", "/", 0, 1),
            ("www.youtube.com", "bad\tname", "injected", b"", "/", 0, 1),
        ]
    )
    con.executemany("INSERT INTO cookies VALUES (?, ?, ?, ?, ?, ?, ?)", rows)
    con.commit()
    con.close()

    monkeypatch.setitem(engine.CHROMIUM_BROWSERS, "test", {
        "roots": [root], "label": "Test", "app": "test"
    })
    monkeypatch.setattr(engine, "_AES", object())
    monkeypatch.setattr(engine, "_keyring_safe_storage_secret", lambda _browser: None)

    payload = engine.export_browser_cookies("test")

    assert isinstance(payload, bytes)
    assert b"accounts.google.com\tFALSE" in payload
    assert b"youtube.com.evil.test" not in payload
    assert b"bad\tname" not in payload


def test_cookie_row_preserves_host_only_scope_and_rejects_controls():
    engine = load_engine()
    host_only = engine._cookie_row_line(
        ("accounts.google.com", "SID", "secret", b"", "/", 0, True), None
    )
    domain = engine._cookie_row_line(
        (".youtube.com", "SID", "secret", b"", "/", 0, True), None
    )

    assert host_only.startswith("accounts.google.com\tFALSE\t")
    assert domain.startswith(".youtube.com\tTRUE\t")
    assert engine._cookie_row_line(
        ("notgoogle.com", "SID", "secret", b"", "/", 0, True), None
    ) is None
    for unsafe in ("bad\nvalue", "bad\rvalue", "bad\tvalue", "bad\0value", "bad\x7fvalue"):
        assert engine._cookie_row_line(
            ("accounts.google.com", "SID", unsafe, b"", "/", 0, True), None
        ) is None


def test_v11_cookie_requires_matching_host_hash(monkeypatch):
    engine = load_engine()
    host = ".youtube.com"
    plaintext = hashlib.sha256(host.encode()).digest() + b"secret"
    padding = 16 - len(plaintext) % 16
    decrypted = plaintext + bytes([padding]) * padding

    class Cipher:
        def decrypt(self, _body):
            return decrypted

    class AES:
        MODE_CBC = object()

        @staticmethod
        def new(*_args):
            return Cipher()

    monkeypatch.setattr(engine, "_AES", AES)

    assert engine._decrypt_chromium_cookie(b"v11ciphertext", b"key", host) == "secret"
    assert engine._decrypt_chromium_cookie(
        b"v11ciphertext", b"key", ".google.com"
    ) is None


def test_history_collection_uses_bounded_sql_and_strict_origins(tmp_path, monkeypatch):
    engine = load_engine()
    monkeypatch.setattr(engine, "HOME", tmp_path)
    profile = tmp_path / ".config" / "chromium" / "Default"
    profile.mkdir(parents=True)
    con = sqlite3.connect(profile / "History")
    con.execute("CREATE TABLE urls (url, last_visit_time)")
    con.executemany(
        "INSERT INTO urls VALUES (?, ?)",
        [
            ("https://www.youtube.com/watch?v=abcdefghijk", 2),
            ("https://evil.test/youtube.com/watch?v=zzzzzzzzzzz", 1),
        ],
    )
    con.commit()
    con.close()

    assert engine.collect_browser_history_ids() == {"abcdefghijk"}


@pytest.mark.skipif(not pathlib.Path("/proc").is_dir(), reason="requires Linux /proc")
def test_run_bounded_child_dies_with_parent(tmp_path):
    child_pid_file = tmp_path / "child.pid"
    child_code = (
        "import os,time,pathlib;"
        f"pathlib.Path({str(child_pid_file)!r}).write_text(str(os.getpid()));"
        "time.sleep(30)"
    )
    driver_code = f"""
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader('parent_death_engine', {str(BIN_PATH)!r})
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
sys.modules[loader.name] = module
loader.exec_module(module)
module.run_bounded([sys.executable, '-c', {child_code!r}], timeout=60)
"""
    driver = subprocess.Popen([sys.executable, "-c", driver_code])
    child_pid = None
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and not child_pid_file.exists():
            time.sleep(0.02)
        assert child_pid_file.exists()
        child_pid = int(child_pid_file.read_text())

        driver.kill()
        driver.wait(timeout=5)

        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            stat_path = pathlib.Path(f"/proc/{child_pid}/stat")
            if not stat_path.exists():
                break
            if stat_path.read_text().split()[2] == "Z":
                break
            time.sleep(0.02)
        else:
            pytest.fail("child survived its engine parent")
    finally:
        if driver.poll() is None:
            driver.kill()
            driver.wait()
        if child_pid is not None:
            try:
                os.kill(child_pid, 9)
            except ProcessLookupError:
                pass
