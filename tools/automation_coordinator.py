#!/usr/bin/env python3
"""Single-host atomic lease coordinator. Linux fcntl gate serializes ALL lock operations.
Godot calls this script through OS.execute; never delete previews/.automation-gate.
No network access, GitHub writes, or external dependencies.
"""
import fcntl
import json
import os
import re
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

LEASE_SECONDS = 2400
RECLAIM_GRACE = 1200
VALID_ID = re.compile(r"^[a-zA-Z0-9._-]{8,160}$")

def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")

def save_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".tmp-owner-", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

def read_owner(lock):
    try:
        with (lock / "owner.json").open(encoding="utf-8") as f:
            o = json.load(f)
        return o if isinstance(o, dict) else {}
    except (OSError, ValueError, TypeError):
        return {}

def additional_godot_pids():
    # Detect competing Godot engines, excluding our own entire process ancestry:
    # coordinator -> Godot runner -> shell wrapper -> launcher service.
    if not os.path.isdir("/proc"):
        return ["PROC_UNAVAILABLE"]
    ignored = set()
    cur = os.getpid()
    for _ in range(20):
        if cur <= 1 or cur in ignored:
            break
        ignored.add(cur)
        try:
            with open("/proc/" + str(cur) + "/stat", "r", encoding="utf-8") as f:
                stat = f.read()
            cur = int(stat.rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            return ["PROC_UNAVAILABLE"]
    result = []
    try:
        for name in os.listdir("/proc"):
            if not name.isdigit() or int(name) in ignored:
                continue
            try:
                with open("/proc/" + name + "/cmdline", "rb") as f:
                    cmd = f.read(350).replace(b"\\0", b" ").lower()
                # Reject only actual Godot process command lines. Ignore
                # unrelated services whose path may contain "lifesim".
                if b"godot" in cmd:
                    result.append(name)
            except PermissionError:
                return ["PROC_PERMISSION_DENIED:" + name]
            except OSError:
                continue
    except OSError:
        return ["PROC_UNAVAILABLE"]
    return result

def record(history, o, state, details, now):
    rid = str(o.get("run_id", ""))
    if not VALID_ID.fullmatch(rid):
        return
    save_json(history / (rid + ".json"), {
        "run_id":rid, "task":o.get("task",""),
        "start_utc":o.get("started_utc",""), "last_update_utc":utc_now(),
        "state":state, "details":details, "lease_expires_unix":o.get("expires_unix",0)
    })

def apply(root, action, task, rid, result_state, details):
    previews = root / "previews"
    lock = previews / "gpt-development.lock"
    history = previews / "automation-history"
    archive = previews / "automation-archive"
    gate = previews / ".automation-gate"
    previews.mkdir(parents=True, exist_ok=True)
    # This lock file is permanent, even if the lease directory gets quarantined.
    with gate.open("a+b") as guard:
        fcntl.flock(guard.fileno(), fcntl.LOCK_EX)
        now = int(time.time())
        owner = read_owner(lock)
        if action == "inspect":
            return {"locked":lock.is_dir(), "owner":owner, "now_unix":now,
                    "other_godot_processes":additional_godot_pids() if lock.is_dir() else []}
        if not VALID_ID.fullmatch(rid):
            return {"ok":False,"reason":"bad run_id"}
        if action == "acquire":
            if task not in ("main","city"):
                return {"ok":False,"reason":"bad task"}
            recovered = ""
            if lock.exists():
                expires = int(owner.get("expires_unix",0))
                if expires <= 0:
                    return {"ok":False,"reason":"legacy/unreadable lock; needs manual investigation", "owner":owner}
                if now <= expires + RECLAIM_GRACE:
                    return {"ok":False,"reason":"active or recently expired lease", "owner":owner}
                pids = additional_godot_pids()
                if pids:
                    return {"ok":False,"reason":"expired lock but other Godot process(es) active; fail closed",
                            "owner":owner,"processes":pids}
                archive.mkdir(parents=True,exist_ok=True)
                dest = archive / ("expired-" + str(now) + "-" + str(time.time_ns()) + "-" + str(owner.get("run_id","unknown")))
                if dest.exists():
                    return {"ok":False,"reason":"archive destination exists"}
                os.rename(lock, dest)
                recovered = str(dest)
            lock.mkdir(exist_ok=False)
            o = {"run_id":rid,"task":task,"started_utc":utc_now(),
                 "heartbeat_utc":utc_now(),"heartbeat_unix":now,
                 "expires_unix":now+LEASE_SECONDS,"protocol":3}
            save_json(lock / "owner.json",o)
            record(history,o,"running","lease acquired",now)
            return {"ok":True,"owner":o,"recovered_archive":recovered}
        if not lock.is_dir() or str(owner.get("run_id","")) != rid:
            if action=="owns":
                return {"ok":True,"owns":False}
            return {"ok":False,"reason":"not owner or lock missing"}
        if action=="owns":
            return {"ok":True,"owns":int(owner.get("expires_unix",0))>now}
        if action=="heartbeat":
            if int(owner.get("expires_unix",0))<=now:
                return {"ok":False,"reason":"lease already expired"}
            owner["heartbeat_utc"]=utc_now()
            owner["heartbeat_unix"]=now
            owner["expires_unix"]=now+LEASE_SECONDS
            save_json(lock / "owner.json",owner)
            record(history,owner,"running","heartbeat",now)
            return {"ok":True,"expires_unix":owner["expires_unix"]}
        if action=="release":
            if result_state not in ("completed","failed","blocked"):
                return {"ok":False,"reason":"bad release state"}
            record(history,owner,result_state,details,now)
            (lock / "owner.json").unlink()
            lock.rmdir()
            return {"ok":True,"status":result_state}
        return {"ok":False,"reason":"unknown action"}

def main():
    if len(sys.argv)<7:
        raise ValueError("expected root, action, task, run_id, status, details")
    root=Path(sys.argv[1]).resolve()
    if not root.is_dir():
        raise ValueError("missing root")
    response=apply(root,*sys.argv[2:7])
    print(json.dumps(response,ensure_ascii=False,separators=(",", ":")))

if __name__=="__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok":False, "reason":"coordinator error", "error":repr(exc)}))
        sys.exit(1)