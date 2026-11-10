#!/usr/bin/env python3
"""Isolated timeout-cleanup regression for the H3 observer bounded runner.

No Godot project, network, saves, or unrelated processes are touched.
Only child PIDs with verified /proc starttimes may be signaled.
"""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import time

runner_path = Path(__file__).with_name("h3_observer_bounded_runner.py")
spec = importlib.util.spec_from_file_location("h3_observer_bounded_runner", runner_path)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

# The child inherits a separate process group from this self-test.
# It spawns a grandchild, then remains alive until the timeout.
parent_code = (
    "import subprocess,sys,time;"
    "subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)']);"
    "print('PARENT_READY',flush=True);time.sleep(60)"
)
proc = subprocess.Popen(
    [sys.executable, "-c", parent_code],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    start_new_session=True,
)
known = {}
try:
    if proc.stdout.readline().strip() != "PARENT_READY":
        raise RuntimeError("synthetic parent failed to start")
    deadline = time.monotonic() + 3.0
    while time.monotonic() < deadline:
        known.update(runner.descendants(proc.pid))
        if known:
            break
        time.sleep(0.05)
    if not known:
        raise RuntimeError("synthetic grandchild not discovered")
finally:
    # Parent is a subprocess created by THIS self-test, not a Godot worker.
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    cleaned, forced = runner.terminate_verified(known)
    remaining = [pid for pid, started in known.items()
                 if runner.still_same(pid, started)]
    print({
        "parent_exit": proc.returncode,
        "verified_children": len(known),
        "cleaned": cleaned,
        "forced": forced,
        "remaining_same_pid_starttime": remaining,
        "success": bool(known) and not remaining,
    }, flush=True)
    if not known or remaining:
        sys.exit(1)
