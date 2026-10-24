extends RefCounted
## Shared Life Simulator lease protocol v3: all state transitions are serialized
## by a stable POSIX fcntl.flock gate in tools/automation_coordinator.py.
## Writers MUST check owns(run_id) immediately before each project mutation.
## No GitHub publishing or other unrelated mutation performed by this lock.
const LOCK := "res://previews/gpt-development.lock"
const ARCHIVE := "res://previews/automation-archive"
const HISTORY := "res://previews/automation-history"
const LEASE_SECONDS := 2400
const RECLAIM_GRACE := 1200

static func _exec(action: String, task: String = "", run_id: String = "", state: String = "", details: String = "") -> Dictionary:
    var script := ProjectSettings.globalize_path("res://tools/automation_coordinator.py")
    var root := ProjectSettings.globalize_path("res://")
    var output: Array = []
    var rc := OS.execute("python3", [script,root,action,task,run_id,state,details], output, true)
    if rc != 0 or output.is_empty():
        return {"ok":false, "reason":"atomic coordinator execution failed; fail closed", "exit_code":rc, "output":output}
    var parsed: Variant = JSON.parse_string(str(output[0]).strip_edges())
    if parsed is Dictionary:
        return parsed
    return {"ok":false, "reason":"invalid atomic coordinator response; fail closed", "output":output}

static func inspect() -> Dictionary:
    var r := _exec("inspect")
    if not r.has("locked"):
        return {"locked":true, "owner":{}, "reason":"atomic coordinator unavailable; fail closed", "diagnostic":r}
    return r

static func _read_owner() -> Dictionary:
    return inspect().get("owner",{})

static func acquire(task: String, run_id: String) -> Dictionary:
    return _exec("acquire",task,run_id)

static func owns(run_id: String) -> bool:
    var r := _exec("owns","",run_id)
    return r.get("ok",false) == true and r.get("owns",false) == true

static func heartbeat(run_id: String) -> Dictionary:
    return _exec("heartbeat","",run_id)

static func release(run_id: String, result: String, details: String = "") -> Dictionary:
    return _exec("release","",run_id,result,details)
