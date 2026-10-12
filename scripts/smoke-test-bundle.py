#!/usr/bin/env python3
"""Smoke-test the packaged helper using disposable, synthetic fixtures only.

Requires macOS and the pinned public text model. Does not test full indexing,
media inference, the GUI, or semantic-search quality. No model is downloaded.
"""
import argparse
import base64
import contextlib
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import selectors
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time


TEXT_MODEL = "embeddinggemma-2-Q8_0.gguf"
TEXT_SHA256 = "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135"
BUNDLE_ID = "io.github.xieshiqi147258.DigUp.ci"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


@contextlib.contextmanager
def child(command, environment):
    """Own the process group; keep stdin open and stderr out of the stdout pipe."""
    with tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(
            list(map(str, command)), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=errors, env=environment, start_new_session=True,
        )
        try:
            yield process
        except BaseException:
            errors.seek(0, os.SEEK_END)
            errors.seek(max(0, errors.tell() - 16000))
            print(errors.read().decode("utf-8", errors="replace"), file=sys.stderr)
            raise
        finally:
            if process.poll() is None:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
            process.stdin.close()
            process.stdout.close()


class Lines:
    """Read JSON lines with an absolute deadline, without blocking on partial lines."""
    def __init__(self, process, seconds=180):
        self.process = process
        self.deadline = time.monotonic() + seconds
        self.buffer = b""

    def next(self):
        with selectors.DefaultSelector() as selector:
            selector.register(self.process.stdout, selectors.EVENT_READ)
            while b"\n" not in self.buffer:
                remaining = self.deadline - time.monotonic()
                require(remaining > 0, "helper JSON protocol timed out")
                require(selector.select(remaining), "helper JSON protocol timed out")
                data = os.read(self.process.stdout.fileno(), 65536)
                require(data, "helper closed stdout before expected JSON response")
                self.buffer += data
                require(len(self.buffer) < 4 * 1024 * 1024, "unbounded helper JSON response")
            line, self.buffer = self.buffer.split(b"\n", 1)
            value = json.loads(line)
            require(isinstance(value, dict), "helper response must be a JSON object")
            return value


def run(helper, arguments, environment):
    with child([helper, *arguments], environment) as process:
        output, _ = process.communicate(timeout=90)
        require(process.returncode == 0, f"helper command failed: {arguments}")
        return output.decode("utf-8")


def estimate(helper, root, environment, expected, *options):
    output = run(helper, ["estimate", "--json", *options, str(root)], environment)
    rows = [json.loads(line) for line in output.splitlines()]
    require(len(rows) == 1, "estimate must report exactly one fixture folder")
    row = rows[0]
    require(Path(row["folder"]).resolve() == root, "estimate returned wrong folder")
    require(row.get("readable") is True, "estimate cannot read synthetic fixtures")
    require(row.get("files") == expected, f"unexpected estimate counts: {row}")


def check_estimates(helper, fixtures, code, environment):
    estimate(helper, fixtures, environment, {"doc": 3})
    estimate(helper, fixtures, environment, {"doc": 2}, "--exclude", str(fixtures / "excluded"))
    estimate(helper, fixtures, environment, {"doc": 1}, "--exclude-ext", "txt")
    estimate(helper, code, environment, {"code": 3}, "--code")
    estimate(helper, code, environment, {"code": 1}, "--code", "--exclude",
             str(code / "excluded"), "--exclude-ext", "py")
    print("PASS: bundled helper estimates normal/code fixtures and honors exclusions", flush=True)


def check_pre_model_search(helper, fixtures, index, environment):
    # Foundation may choose the Darwin user temp directory rather than TMPDIR.
    # Discover the actual API result, then create only exclusive synthetic sentinels.
    # Existing directories are never adopted, overwritten or removed by this test.
    probe = subprocess.run(["xcrun", "swift", "-e",
        "import Foundation; print(FileManager.default.temporaryDirectory.path)"],
        env=environment, capture_output=True, text=True, timeout=90, check=True)
    temporary = Path(probe.stdout.strip()).resolve()
    require(temporary.is_dir(), "Foundation temporary-directory probe failed")
    print(f"Scratch smoke Foundation directory: {temporary}", flush=True)
    dead_pid = 99999999
    try:
        os.kill(dead_pid, 0)
    except ProcessLookupError:
        pass
    else:
        raise AssertionError("scratch-cleanup fixture PID unexpectedly exists")
    original = temporary / f"DigUp-{dead_pid}"
    testing = temporary / f"DigUpTest-{dead_pid}"
    with contextlib.ExitStack() as cleanup:
        original.mkdir()
        cleanup.callback(shutil.rmtree, original, ignore_errors=True)
        testing.mkdir()
        cleanup.callback(shutil.rmtree, testing, ignore_errors=True)
        (original / "keep").write_text("synthetic original-app sentinel", encoding="utf-8")
        (testing / "stale").write_text("synthetic test-app scratch", encoding="utf-8")
        with child([helper, "index-service", str(fixtures), "--index", str(index), "--linger", "0"],
                   environment) as process:
            lines = Lines(process, seconds=90)
            events = []
            while True:
                event = lines.next()
                events.append(event)
                require(event.get("event") != "error", f"index service error: {event}")
                if event.get("event") == "exit":
                    break
            require(process.wait(timeout=10) == 0, "index service failed to exit cleanly")
        require((original / "keep").read_text(encoding="utf-8") == "synthetic original-app sentinel",
                "test helper touched original-prefixed scratch directory")
        require(not testing.exists(), "test helper did not clean its own stale scratch directory")
        names = [event.get("event") for event in events]
        require("sync" in names and "waiting" in names, f"missing pre-model events: {events}")
        require(names.index("sync") < names.index("waiting") < names.index("exit"),
                "index service events out of order")
        waiting = next(event for event in events if event.get("event") == "waiting")
        require(waiting.get("for") == "model" and waiting.get("files") == 3
                and waiting.get("pending") == 3 and waiting.get("vectors") == 0,
                f"unexpected pre-model index state: {waiting}")
        rows = json.loads(run(helper, ["search", "中文旅行计划", "--json", "--index", str(index)], environment))
        target = (fixtures / "中文旅行计划.txt").resolve()
        require(any(Path(row["path"]).resolve() == target for row in rows),
                f"Chinese filename not returned before model download: {rows}")
        print("PASS: bundled index service syncs before model download; Chinese filename search works", flush=True)


def check_worker(helper, environment):
    with child([helper, "worker", "--text-only"], environment) as process:
        lines = Lines(process, seconds=300)
        ready = lines.next()
        require(ready.get("ready") is True, f"text worker did not start: {ready}")
        info = ready.get("info", {})
        require(info.get("dim") == 768 and info.get("text_only") is True,
                f"unexpected worker identity: {info}")
        inputs = ["task: search result | query: 中文旅行计划", "task: search result | query: train to the beach"]

        def request(identifier, operation, **fields):
            message = {"id": identifier, "op": operation, **fields}
            process.stdin.write((json.dumps(message, ensure_ascii=False) + "\n").encode("utf-8"))
            process.stdin.flush()
            response = lines.next()
            require(response.get("id") == identifier and response.get("ok") is True,
                    f"worker request failed: {response}")
            return response

        counted = request("counts", "token_count", inputs=inputs)
        counts = counted.get("counts", [])
        require(len(counts) == len(inputs) and all(isinstance(n, int) and 0 < n <= 512 for n in counts),
                f"invalid token counts: {counted}")
        response = request("vectors", "text", inputs=inputs)
        require(response.get("dim") == 768 and response.get("count") == len(inputs)
                and response.get("errors") == [None] * len(inputs), f"invalid inference response: {response}")
        data = base64.b64decode(response["vectors"], validate=True)
        require(len(data) == len(inputs) * 768 * 4, "wrong Float32 embedding byte count")
        values = struct.unpack("<" + "f" * (len(data) // 4), data)
        require(all(math.isfinite(value) for value in values), "non-finite embedding")
        for start in range(0, len(values), 768):
            require(sum(value * value for value in values[start:start + 768]) > 0,
                    "all-zero embedding")
        request("quit", "quit")
        require(process.wait(timeout=15) == 0, "text worker did not quit cleanly")
    print("PASS: bundled text worker tokenizes, performs native inference and quits", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--models", type=Path, required=True)
    args = parser.parse_args()
    require(os.environ.get("GITHUB_ACTIONS") == "true",
            "Packaged-helper smoke is restricted to the disposable GitHub CI runner")
    app, models = args.app.resolve(), args.models.resolve()
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    require(info.get("CFBundleIdentifier") == BUNDLE_ID, "wrong app bundle identity")
    require(info.get("CFBundleExecutable") == "DigUpTest", "wrong app executable identity")
    require(info.get("SUEnableAutomaticChecks") is False, "automatic updates must be disabled")
    require(info.get("SUFeedURL") == "https://example.invalid/digup-ci/appcast.xml", "unsafe update feed")
    helper = app / "Contents/Helpers/digup-test"
    require(helper.is_file() and os.access(helper, os.X_OK), "bundled helper is missing or not executable")
    require(not os.path.lexists(app / "Contents/Helpers/digup"), "old helper alias must not ship")
    digest = hashlib.sha256()
    with (models / TEXT_MODEL).open("rb") as source:
        for block in iter(lambda: source.read(8 * 1024 * 1024), b""):
            digest.update(block)
    require(digest.hexdigest() == TEXT_SHA256, "text model does not match pinned public SHA-256")
    # Ordinary source roots avoid the inherited /var versus /private/var scope
    # mismatch. Scratch-cleanup coverage still probes Foundation's actual temp dir.
    fixtures_parent = Path.home() / "Library/Caches"
    fixtures_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="digup-bundle-smoke-", dir=fixtures_parent) as directory:
        scratch = Path(directory).resolve()
        fixtures, code, empty_models, index = [scratch / name for name in ("fixtures", "code", "models", "index")]
        for folder in (fixtures / "excluded", code / "excluded", empty_models):
            folder.mkdir(parents=True)
        for path, text in {
            fixtures / "中文旅行计划.txt": "这是公开合成的测试文本。乘坐火车去海边。\n",
            fixtures / "note.md": "A synthetic public note about the beach.\n",
            fixtures / "excluded/skip.txt": "Synthetic excluded document.\n",
            code / "旅行.swift": "func travel() -> String { return \"海边\" }\n",
            code / "helper.py": "def travel():\n    return 'beach'\n",
            code / "excluded/skip.swift": "let excluded = true\n",
        }.items():
            path.write_text(text, encoding="utf-8")
        environment = os.environ.copy()
        environment.pop("DIGUP_WORKER_DIR", None)
        environment["DIGUP_MODELS"] = str(empty_models)
        temporary = scratch / "tmp"
        temporary.mkdir()
        environment["TMPDIR"] = str(temporary) + os.sep
        check_estimates(helper, fixtures, code, environment)
        check_pre_model_search(helper, fixtures, index, environment)
        environment["DIGUP_MODELS"] = str(models)
        check_worker(helper, environment)
    print("PASS: packaged-helper smoke checks only; full indexing, media, UI and search quality are not covered.")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
