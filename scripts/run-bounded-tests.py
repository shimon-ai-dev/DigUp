#!/usr/bin/env python3
"""Run native tests with a bounded process-group timeout and always preserve flushed diagnostics."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--seconds', type=int, required=True)
parser.add_argument('--log', type=Path, required=True)
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
if args.seconds <= 0 or not args.command:
    parser.error('a positive timeout and command are required')
args.log.parent.mkdir(parents=True, exist_ok=True)
with args.log.open('w') as log:
    process = subprocess.Popen(args.command, stdout=log, stderr=subprocess.STDOUT,
                               start_new_session=True)
    try:
        code = process.wait(timeout=args.seconds)
    except subprocess.TimeoutExpired:
        print(f'Native test timeout after {args.seconds}s; terminating process group.', file=log, flush=True)
        os.killpg(process.pid, signal.SIGTERM)
        try: process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        code = 124
sys.stdout.write(args.log.read_text(errors='replace'))
sys.stdout.flush()
sys.exit(code)
