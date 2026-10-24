# Hourly GPT automation: cooperative lock protocol v2 (2026-10-24)

The server project `lifesim` is the source of truth while GitHub publication is restricted.
Both hourly tasks coordinate only GPT edits using `tools/automation_lock.gd`.
This is a cooperative protocol: **it does not exclude Claude/Grok or OS processes**.
Read source files immediately before write and compare hashes; never overwrite concurrent changes.

## Mandatory per-run sequence

1. Use `godot_run_script(project="lifesim")` to load
   `var G = load("res://tools/automation_lock.gd")`.
   Compute one unique ID, for example
   `"main-" + str(int(Time.get_unix_time_from_system())) + "-" + str(OS.get_process_id())`
   or with prefix `city-`. Call `G.acquire("main", run_id)` or
   `G.acquire("city", run_id)`. Preserve the returned ID for all calls.
2. On `ok=false` **make no project/Blender mutations**. Report the blocker.
   Never directly delete the lock or modify another run's owner.
3. Before **every** project/Blender mutation check `G.owns(run_id)` in
   a fresh Godot script; if false, stop. Renew through `G.heartbeat(run_id)`
   before lengthy steps and after each meaningful milestone (max 20-minute
   work units). If the heartbeat fails, stop all writes.
4. Record actual changes, verification, and a precise next step in the task's
   checkpoint and devlog. At end, **including after error**, call
   `G.release(run_id, "completed" or "blocked" or "failed", details)`.
   Never release someone else's lock. Check `ok=true`.
5. Read `previews/automation-history/<run_id>.json` to distinguish
   `running` from `completed`, `failed`, `blocked`. A scheduler
   event is not proof of implementation.

## Recovery

Acquired lease duration: 40 minutes, extended by `heartbeat`.
Automated stale-lock reclaim is disabled because directory rename is not an atomic compare-and-swap; this avoids a critical race. Investigate expired locks manually and archive them only after proving the prior writer cannot resume. The prior owner is preserved, not deleted. If the lock
doesn't use protocol v2, is unreadable, changes during checking, or process
inspection fails, automatic recovery **fails closed** and reports manual review.

All cooperating writers must check ownership before writes: a run with an
expired lease must not update project files even if its model execution
resumes. Run logs are best-effort, not a complete audit of scheduler starts.
Godot warnings about old ObjectDB leaks don't by themselves mean failure;
check exit, stderr, test counts, and deadline.

## Scheduler

Both tasks stay `FREQ=HOURLY`: main at around minute 01 and city at around
minute 31, so normal short edits do not overlap. Each individual task is
hourly, not an alternation of tasks every hour. The scheduler may run
late, encounter lease contention, or fail; in those cases state accurately
what did and did not execute.

## Repair evidence, 2026-10-24

Legacy H2b owner `gpt-h2b-20261024-0105` stopped updating at 01:05:50 UTC.
At repair time it was 6130 seconds old; server namespace had no other Godot
process. The original owner directory was archived as
`previews/automation-archive/orphan-1792810080-gpt-h2b/`.
A 114059 KB project backup was uploaded to `peiti/godot-mcp-backup`
before any changes. No files were published to GitHub.
## Diagnostic correction 2026-10-24 03:43 UTC
Gemini independently found a TOCTOU race in automated recovery: rechecking owner.json and then renaming the lock directory is not an atomic compare-and-swap; a parallel heartbeat can win in between. Automatic recovery is therefore DISABLED in tools/automation_lock.gd. When the lock is occupied (even expired), acquisition fails closed and manual owner/process review is required. No other job may force-remove the lock. To restore unattended safe recovery would require a server-side atomic fencing token/compare-and-swap mechanism implemented outside separate GDScript calls. The heartbeat implementation now validates the owner and expiry from one read. Verified acquisition, wrong task reject, concurrent acquire deny, wrong release deny, heartbeat, own release, absence of residual lock. ObjectDB warnings are pre-existing. Scheduler records from 04:58/05:30 local demonstrate triggers only; no fresh H2b/city files or run-history attestations were found, so successful project work is not proven. Godot/Blender/Gemini connector direct smoke tests succeeded; scheduled-run internal execution logs are not exposed by the accessible tasks interface.


## Current protocol v3 — 24 October 2026, 07:14 UTC (supersedes historical v2 recovery ban)
Shared coordinator source: tools/automation_coordinator.py (Python 3.11), called by tools/automation_lock.gd. All acquire / owns / heartbeat / release / inspect run under a permanent project-local POSIX fcntl.flock gate at previews/.automation-gate. Owner JSON and audit logs use atomic file replacement. A 40-minute renewable lease PLUS 20-minute grace permits automatic archival (NOT deletion) of an expired owner during atomic acquire if no other Godot engine is detected. If archive, process visibility, helper, or state cannot be confirmed, fail closed with ok:false and never write without ownership. The v2 section prohibiting ANY auto-reclaim is historical and no longer describes current v3. Users and tasks must NEVER manually delete or overwrite another owner's lock.
Manual incident 2026-10-24: city-1792820091-68355 started 05:34:51 UTC, last heartbeat 05:41:46 UTC, remained running after expired lease 06:21:46 UTC. At 07:03:24 UTC, after backup (114150 KB), no other Godot processes were observed, unchanged owner directory was quarantined under previews/automation-archive/manually-quarantined-1792825404-city-1792820091-68355. New solid-wall assets actually existed despite incomplete checkpoint. Read-only solid wall/3-module regression: 28/28 passed, exit 0; pre-existing ObjectDB shutdown warning only.
Verification: isolated v3 acquire, collision rejection, own check, heartbeat, wrong-owner release refusal, own release and forced-stale archival succeeded. Live v3 inspected and renewed a pre-existing protocol-v2 maintenance lock, followed by successful release; new protocol-v3 project acquire succeeded. Godot syntax checker: 60/60 clean. Gemini independently reviewed Python/GDScript and confirmed serializing heartbeat/acquire fixes old TOCTOU race, with remaining limitations around process detection and cooperative per-write ownership. This is not a global filesystem transaction across arbitrary external writes; check hashes and G.owns immediately before each mutation. The gate file must NEVER be deleted. No GitHub changes made.
