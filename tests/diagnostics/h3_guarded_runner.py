#!/usr/bin/env python3
"""Bounded external runner for the H3 three-process Godot diagnostic.

Runs the existing fixture unchanged. All output is kept in a caller-supplied
/tmp result JSON, never in project source or user saves. Tracks descendants
while the parent is alive and cleans up only verified child PIDs.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


def process_identity(pid):
    try:
        raw = Path(f"/proc/{pid}/stat").read_text()
        tail = raw[raw.rfind(")") + 2:].split()
        return int(tail[1]), int(tail[19])  # ppid, starttime (field 22)
    except (OSError, ValueError, IndexError):
        return None


def descendants(parent_pid):
    rows = {}
    for name in os.listdir("/proc"):
        if name.isdecimal():
            pid = int(name)
            item = process_identity(pid)
            if item is not None:
                rows[pid] = item
    found = {}
    frontier = [parent_pid]
    while frontier:
        parent = frontier.pop()
        for pid, (ppid, started) in rows.items():
            if ppid == parent and pid not in found:
                found[pid] = started
                frontier.append(pid)
    return found


def still_same(pid, started):
    item = process_identity(pid)
    return item is not None and item[1] == started


def terminate_verified(known):
    alive = {pid: start for pid, start in known.items() if still_same(pid, start)}
    for pid in alive:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.6)
    forced = []
    for pid, started in alive.items():
        if still_same(pid, started):
            try:
                os.kill(pid, signal.SIGKILL)
                forced.append(pid)
            except ProcessLookupError:
                pass
    return sorted(alive), forced


def owns(root, run_id):
    coordinator = root / "tools" / "automation_coordinator.py"
    cmd = [sys.executable, str(coordinator), str(root), "owns", "", run_id, "", ""]
    try:
        reply = subprocess.run(cmd, capture_output=True, text=True, timeout=8, check=False)
        data = json.loads(reply.stdout.strip())
        return reply.returncode == 0 and data.get("ok") is True and data.get("owns") is True
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return False


def main():
    if len(sys.argv) not in (7, 8):
        raise SystemExit("usage: runner.py PROJECT_ROOT GODOT_BIN RUN_ID OUTPUT_JSON TIMEOUT_SEC EXPECTED_FIXTURE_SHA [cold|prewarm|enet-extended]")
    mode = sys.argv[7] if len(sys.argv) == 8 else "cold"
    if mode not in ("cold", "prewarm", "enet-extended"):
        raise SystemExit("invalid H3 A/B mode")
    root = Path(sys.argv[1]).resolve()
    godot = Path(sys.argv[2]).resolve()
    run_id = sys.argv[3]
    output = Path(sys.argv[4]).resolve()
    timeout = min(105.0, max(5.0, float(sys.argv[5])))
    expected = sys.argv[6]
    import hashlib
    fixture = root / "tests/diagnostics/h3_three_process.FAILING.gd"
    actual = hashlib.sha256(fixture.read_bytes()).hexdigest()
    if actual != expected or not owns(root, run_id):
        raise SystemExit("preflight failed: changed fixture or main lease not owned")
    if output.parent != Path("/tmp") or not output.name.startswith("lifesim_h3_"):
        raise SystemExit("result must be a unique /tmp/lifesim_h3_*.json")
    cmd = [str(godot), "--headless", "--path", str(root),
           "res://tests/diagnostics/h3_three_process_guarded.tscn"]
    if mode in ("prewarm", "enet-extended"):
        cmd.extend(["--", mode])
    start = time.monotonic()
    known = {}
    timed_out = False
    with tempfile.TemporaryDirectory(prefix="lifesim_h3_runner_") as directory:
        stdout_path = Path(directory) / "stdout.log"
        stderr_path = Path(directory) / "stderr.log"
        with stdout_path.open("wb") as out, stderr_path.open("wb") as err:
            proc = subprocess.Popen(cmd, stdout=out, stderr=err, cwd=root,
                                    start_new_session=True)
            parent_start = process_identity(proc.pid)
            while proc.poll() is None:
                known.update(descendants(proc.pid))
                if time.monotonic() - start > timeout:
                    timed_out = True
                    break
                time.sleep(0.25)
            # Capture children while their parent still exists; never kill other tests.
            known.update(descendants(proc.pid))
            if timed_out and proc.poll() is None:
                try:
                    proc.terminate()
                    proc.wait(timeout=1.5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=3)
            rc = proc.poll()
        cleaned, forced = terminate_verified(known)
        stdout = stdout_path.read_text(errors="replace")
        stderr = stderr_path.read_text(errors="replace")
    report = {
        "run_id": run_id,
        "ab_mode": mode,
        "fixture_sha256": actual,
        "elapsed_seconds": round(time.monotonic() - start, 2),
        "timeout_seconds": timeout,
        "timed_out": timed_out,
        "exit_code": rc,
        "children_seen": len(known),
        "children_cleaned": cleaned,
        "children_forced": forced,
        "stdout_chars": len(stdout),
        "stderr_chars": len(stderr),
        "stdout_tail": stdout[-60000:],
        "stderr_tail": stderr[-14000:],
        "success": rc == 0 and not timed_out and not cleaned,
    }
    temporary = output.with_suffix(".tmp")
    temporary.write_text(json.dumps(report, ensure_ascii=False), encoding="utf-8")
    os.replace(temporary, output)
    print(json.dumps({key: val for key, val in report.items()
                      if key not in ("stdout_tail", "stderr_tail")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
