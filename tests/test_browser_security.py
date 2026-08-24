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
        ("https://music.youtube.com/watch?v=abcdefghijk", "abcdefghijk"),
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


def test_browser_snapshot_retries_when_source_changes(tmp_path, monkeypatch):
    engine = load_engine()
    root = tmp_path / "chromium"
    profile = root / "Default"
    profile.mkdir(parents=True)
    database = profile / "History"
    con = sqlite3.connect(database)
    con.execute("CREATE TABLE urls (url, last_visit_time)")
    con.commit()
    con.close()
    source = engine._profile_db_candidates(
        root, "History", engine.MAX_HISTORY_DB_BYTES
    )[0]
    real_copy = engine._copy_fd_bounded
    copies = 0

    def changing_copy(source_fd, destination, limit):
        nonlocal copies
        real_copy(source_fd, destination, limit)
        copies += 1
        if copies == 1:
            info = database.stat()
            os.utime(database, ns=(info.st_atime_ns, info.st_mtime_ns + 1))

    monkeypatch.setattr(engine, "_copy_fd_bounded", changing_copy)

    with engine._browser_db_snapshot(source, engine.MAX_HISTORY_DB_BYTES) as snapshot:
        copied = sqlite3.connect(snapshot)
        try:
            assert copied.execute("SELECT count(*) FROM urls").fetchone() == (0,)
        finally:
            copied.close()
    assert copies == 2


def test_browser_snapshot_recovers_hot_rollback_journal(tmp_path):
    engine = load_engine()
    root = tmp_path / "chromium"
    profile = root / "Default"
    profile.mkdir(parents=True)
    database = profile / "History"
    writer = sqlite3.connect(database)
    writer.execute("PRAGMA journal_mode=DELETE")
    writer.execute("CREATE TABLE urls (url, last_visit_time)")
    writer.execute("INSERT INTO urls VALUES ('committed', 1)")
    writer.commit()
    source = engine._profile_db_candidates(
        root, "History", engine.MAX_HISTORY_DB_BYTES
    )[0]
    writer.execute("BEGIN IMMEDIATE")
    writer.execute("UPDATE urls SET url='uncommitted'")
    assert pathlib.Path(str(database) + "-journal").exists()

    try:
        with engine._browser_db_snapshot(source, engine.MAX_HISTORY_DB_BYTES) as snapshot:
            copied = sqlite3.connect(snapshot)
            try:
                assert copied.execute("SELECT url FROM urls").fetchone() == ("committed",)
            finally:
                copied.close()
    finally:
        writer.rollback()
        writer.close()


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
    con.execute("CREATE TABLE meta (key PRIMARY KEY, value)")
    con.execute("INSERT INTO meta VALUES ('version', 24)")
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


def test_chromium_auth_fails_closed_without_safe_decryptor(monkeypatch):
    engine = load_engine()
    monkeypatch.setattr(engine, "_AES", None)

    with pytest.raises(RuntimeError, match="requires pycryptodomex"):
        engine._browser_auth("chromium")


@pytest.mark.parametrize("version", (b"v10", b"v11"))
def test_schema_v24_cookie_requires_matching_host_hash(monkeypatch, version):
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

    assert engine._decrypt_chromium_cookie(
        version + b"ciphertext", b"key", host, True
    ) == "secret"
    assert engine._decrypt_chromium_cookie(
        version + b"ciphertext", b"key", ".google.com", True
    ) is None


def test_pre_v24_v11_cookie_has_no_host_hash(monkeypatch):
    engine = load_engine()
    padding = 16 - len(b"secret")
    decrypted = b"secret" + bytes([padding]) * padding

    class AES:
        MODE_CBC = object()

        @staticmethod
        def new(*_args):
            return type("Cipher", (), {"decrypt": lambda self, _body: decrypted})()

    monkeypatch.setattr(engine, "_AES", AES)

    assert engine._decrypt_chromium_cookie(
        b"v11ciphertext", b"key", ".youtube.com", False
    ) == "secret"


def test_history_collection_uses_bounded_sql_and_strict_origins(tmp_path, monkeypatch):
    engine = load_engine()
    monkeypatch.setattr(engine, "HOME", tmp_path)
    profile = tmp_path / ".config" / "chromium" / "Default"
    profile.mkdir(parents=True)
    con = sqlite3.connect(profile / "History")
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA wal_autocheckpoint=0")
    con.execute("CREATE TABLE urls (url, last_visit_time)")
    con.executemany(
        "INSERT INTO urls VALUES (?, ?)",
        [
            ("https://www.youtube.com/watch?v=abcdefghijk", 2),
            ("https://evil.test/youtube.com/watch?v=zzzzzzzzzzz", 1),
        ],
    )
    con.commit()

    try:
        assert engine.collect_browser_history_ids() == {"abcdefghijk"}
    finally:
        con.close()


@pytest.mark.skipif(not pathlib.Path("/proc").is_dir(), reason="requires Linux /proc")
def test_run_bounded_reaps_child_when_selector_setup_fails(tmp_path, monkeypatch):
    engine = load_engine()
    pid_file = tmp_path / "child.pid"
    child_code = (
        "import os,time,pathlib;"
        f"pathlib.Path({str(pid_file)!r}).write_text(str(os.getpid()));"
        "time.sleep(30)"
    )

    class BrokenSelector:
        def register(self, *_args):
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and not pid_file.exists():
                time.sleep(0.02)
            raise RuntimeError("selector failed")

        def close(self):
            pass

    monkeypatch.setattr(engine.selectors, "DefaultSelector", BrokenSelector)

    with pytest.raises(RuntimeError, match="selector failed"):
        engine.run_bounded([sys.executable, "-c", child_code], timeout=30)

    assert pid_file.exists()
    process_id = int(pid_file.read_text())
    stat_path = pathlib.Path(f"/proc/{process_id}/stat")
    assert not stat_path.exists() or stat_path.read_text().split()[2] == "Z"


@pytest.mark.skipif(not pathlib.Path("/proc").is_dir(), reason="requires Linux /proc")
def test_supervisor_kills_descendants_after_direct_child_exits(tmp_path):
    engine = load_engine()
    grandchild_pid_file = tmp_path / "grandchild.pid"
    grandchild_code = (
        "import os,time,pathlib;"
        f"pathlib.Path({str(grandchild_pid_file)!r}).write_text(str(os.getpid()));"
        "time.sleep(30)"
    )
    child_code = (
        "import subprocess,sys,time;"
        f"subprocess.Popen([sys.executable, '-c', {grandchild_code!r}],"
        "stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);"
        "time.sleep(0.2)"
    )

    result, limited = engine.run_bounded(
        [sys.executable, "-c", child_code], timeout=5
    )

    assert result.returncode == 0 and not limited
    assert grandchild_pid_file.exists()
    process_id = int(grandchild_pid_file.read_text())
    stat_path = pathlib.Path(f"/proc/{process_id}/stat")
    assert not stat_path.exists() or stat_path.read_text().split()[2] == "Z"


@pytest.mark.skipif(not pathlib.Path("/proc").is_dir(), reason="requires Linux /proc")
def test_run_bounded_child_dies_with_parent(tmp_path):
    child_pid_file = tmp_path / "child.pid"
    grandchild_pid_file = tmp_path / "grandchild.pid"
    grandchild_code = (
        "import os,time,pathlib;"
        f"pathlib.Path({str(grandchild_pid_file)!r}).write_text(str(os.getpid()));"
        "time.sleep(30)"
    )
    child_code = (
        "import os,time,pathlib,subprocess,sys;"
        f"pathlib.Path({str(child_pid_file)!r}).write_text(str(os.getpid()));"
        f"subprocess.Popen([sys.executable, '-c', {grandchild_code!r}]);"
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
    process_ids = []
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and not (
            child_pid_file.exists() and grandchild_pid_file.exists()
        ):
            time.sleep(0.02)
        assert child_pid_file.exists() and grandchild_pid_file.exists()
        process_ids = [
            int(child_pid_file.read_text()),
            int(grandchild_pid_file.read_text()),
        ]

        driver.kill()
        driver.wait(timeout=5)

        for process_id in process_ids:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                stat_path = pathlib.Path(f"/proc/{process_id}/stat")
                if not stat_path.exists() or stat_path.read_text().split()[2] == "Z":
                    break
                time.sleep(0.02)
            else:
                pytest.fail(f"process {process_id} survived its engine parent")
    finally:
        if driver.poll() is None:
            driver.kill()
            driver.wait()
        for process_id in process_ids:
            try:
                os.kill(process_id, 9)
            except ProcessLookupError:
                pass
