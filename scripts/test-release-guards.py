#!/usr/bin/env python3
"""Verify test-identity release guards without signing, credentials, or publishing."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TEST_ID = "io.github.xieshiqi147258.DigUp.ci"
MESSAGE = "DigUpTest release publishing is disabled"


def main():
    output = ROOT / "build.noindex"
    output.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="release-guards-", dir=output) as temporary:
        root = Path(temporary)
        (root / "scripts").mkdir()
        (root / "Resources").mkdir()
        for name in ("release.sh", "appcast.py"):
            shutil.copyfile(ROOT / "scripts" / name, root / "scripts" / name)
        app = root / "fixture.app/Contents"
        app.mkdir(parents=True)
        def identity(path, identifier):
            path.write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier,
                "CFBundleShortVersionString": "0.0.0", "CFBundleVersion": "1"}))
        source = root / "Resources/Info.plist"
        identity(source, TEST_ID)
        identity(app / "Info.plist", TEST_ID)
        environment = os.environ.copy()
        environment.pop("SIGN_ID", None)
        environment.pop("NOTARY_PROFILE", None)
        def blocked(command):
            result = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=10)
            assert result.returncode != 0 and MESSAGE in result.stderr, result.stderr
        blocked(["bash", str(root / "scripts/release.sh")])
        appcast = ["python3", str(root / "scripts/appcast.py"), "fixture-0.0.0.dmg",
                   str(root / "feed.xml"), "--app", str(app.parent)]
        blocked(appcast)
        # A test checkout must never package a stale original app, and an upstream
        # checkout must also refuse a testing bundle supplied explicitly.
        identity(app / "Info.plist", "com.abdurrahim.DigUp")
        blocked(appcast)
        identity(source, "com.abdurrahim.DigUp")
        identity(app / "Info.plist", TEST_ID)
        blocked(appcast)
        # The original release entry point is preserved past the testing guard.
        result = subprocess.run(["bash", str(root / "scripts/release.sh")],
            capture_output=True, text=True, env=environment, timeout=10)
        assert MESSAGE not in result.stderr and "SIGN_ID" in result.stderr, result.stderr
        assert not (root / "feed.xml").exists()
        assert not (root / "build.noindex").exists()
    print("PASS: testing identities cannot enter inherited release/appcast flows; upstream entry remains")


if __name__ == "__main__":
    main()
