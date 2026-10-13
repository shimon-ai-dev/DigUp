#!/usr/bin/env python3
"""Launch the extracted AppKit app on a disposable CI Mac, past its real settings boundary."""
import argparse
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
import time

TEST_ID = "io.github.xieshiqi147258.DigUp.ci"


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=30)


def original_snapshot():
    home = Path.home()
    result = {}
    for root in [home / "Library/Application Support/DigUp",
                 home / "Library/Preferences/com.abdurrahim.DigUp.plist"]:
        for path in ([root] + list(root.rglob("*")) if root.is_dir() else [root]):
            if path.exists() or path.is_symlink():
                meta = path.lstat()
                result[str(path)] = (meta.st_mode, meta.st_size, meta.st_mtime_ns,
                                     os.readlink(path) if path.is_symlink() else None)
    return result


def launch(executable, directory, name, suite=None, snapshot=False):
    case = directory / name
    case.mkdir()
    index = case / "index"
    image = case / "onboarding.png"
    command = [str(executable), "-indexDir", str(index), "-modelsDir", str(case / "models"),
               "-roots", "", "-codeRoots", "", "-onboarded", "NO", "-debugOffscreen", "YES",
               "-AppleLanguages", "(en)"]
    if suite is not None:
        command += ["-defaultsSuite", suite]
    if snapshot:
        command += ["-debugWindow", "onboarding:welcome", "-debugSnapshot", str(image), "-debugQuit", "YES"]
    else:
        command += ["-debugMenu", "YES", "-debugQuitAfter", "4"]
    started = time.monotonic()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                               cwd=case, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=45)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
        raise AssertionError(f"{name}: AppKit startup/clean shutdown timed out\n{stdout}\n{stderr}")
    elapsed = time.monotonic() - started
    print(f"STARTUP {name}: pid={process.pid}, exit={process.returncode}, elapsed={elapsed:.2f}s", flush=True)
    print(stderr, flush=True)
    assert process.returncode == 0, (name, process.returncode, stdout, stderr)
    log = (index / "app.log").read_text()
    assert f"launch pid {process.pid}:" in log and "power:" in log, (name, log)
    assert str(index) in log and str(case / "models") in log, (name, log)
    if snapshot:
        assert "window: onboarding:welcome loaded" in log, log
        assert "snapshot: onboarding:welcome" in log, log
        assert image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n") and image.stat().st_size > 1000, image
    else:
        assert elapsed >= 3.5, (name, elapsed)
        for marker in ["menu:", "menu after Pause:", "menu after Resume:", "debug: menu", "debug: quitting"]:
            assert marker in log, (name, marker, log)
    return log


def check(app):
    assert os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("GITHUB_REPOSITORY") == "xieshiqi147258/DigUp", \
        "GUI startup smoke is restricted to the disposable public-fork CI runner"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == TEST_ID, info
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    assert executable.is_file() and os.access(executable, os.X_OK), executable
    verified = run("codesign", "--verify", "--deep", "--strict", str(app))
    assert verified.returncode == 0, verified.stderr
    # No persistent domain may be adopted or overwritten, even on this ephemeral runner.
    assert run("defaults", "export", TEST_ID, "-").returncode != 0, "Startup fixture requires a fresh test defaults domain"
    custom = TEST_ID + ".startup." + str(os.getpid())
    assert run("defaults", "export", custom, "-").returncode != 0
    before = original_snapshot()
    try:
        for suite, sentinel in [(TEST_ID, "persisted-test-hotkey"), (custom, "persisted-custom-hotkey")]:
            result = run("defaults", "write", suite, "hotkey", "-string", sentinel)
            assert result.returncode == 0, result.stderr
        with tempfile.TemporaryDirectory(prefix="DigUpTest-startup-") as directory:
            root = Path(directory)
            normal = launch(executable, root, "same-bundle-default")
            assert 'hotkey: can\'t read "persisted-test-hotkey"' in normal, normal
            explicit = launch(executable, root, "same-bundle-explicit", suite=TEST_ID, snapshot=True)
            assert 'hotkey: can\'t read "persisted-test-hotkey"' in explicit, explicit
            separate = launch(executable, root, "custom-suite", suite=custom)
            assert 'hotkey: can\'t read "persisted-custom-hotkey"' in separate, separate
            assert "persisted-test-hotkey" not in separate, separate
            for suite, sentinel in [(TEST_ID, "persisted-test-hotkey"), (custom, "persisted-custom-hotkey")]:
                value = run("defaults", "read", suite, "hotkey")
                assert value.returncode == 0 and value.stdout.strip() == sentinel, value
        assert original_snapshot() == before, "AppKit startup changed original DigUp data/settings"
    finally:
        for suite in [custom, TEST_ID]:
            run("defaults", "delete", suite)
    print("PASS: extracted signed AppKit app loaded persisted isolated settings, constructed onboarding/menu, "
          "processed Pause/Resume, remained alive, rendered PNG and exited cleanly; original data unchanged", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    arguments = parser.parse_args()
    check(arguments.app.resolve())
