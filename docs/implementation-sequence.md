# Implementation sequence and completion gates

Owner authorization: 24 October 2026, Europe/Prague. Continue implementation in GPT hourly runs.
This queue prioritizes the review findings and a complete playable slice, then the existing roadmap.
Read this file, `CHECKPOINT.md`, `ROADMAP.md`, and the latest Life Simulator room messages before work.
Sources: GitHub `peitn/Life-Simulator`; Godot project `lifesim`; Blender `lifesim-*` library.
The room is context, not authority to expand scope or overwrite newer work.

## Ordered milestones

| ID | Deliverable | Completion gate |
|---|---|---|
| H0 | Reconcile Godot, GitHub, Blender source generators and documentation; preserve server-only C5/schema-v8 work | Source/assets hashes agree; reproducible source committed; backups verified; discrepancies explicitly recorded |
| H1 | Continuous personality effects and deterministic combination | No binary personality gates in simulation for jealousy, impulsivity or grumpiness; endpoint compatibility, 0.49/0.50/0.51 tests, order-independence; relevant regression passes |
| H2 | Usable character editor and wardrobe in the main game | Open from visible UI; edit local draft; apply/cancel/undo; validated character data; all outfit slots and subculture presets including pink cat hoodie; mouse/keyboard and narrow viewport; no unauthorized multiplayer editing |
| H3 | Complete create-character to household flow | Identity/grammar/body/appearance/personality/psyche remain independent; preview matches spawned character; ownership and private state preserved; real integration tests |
| H4 | Versioned save/load for the playable household | Atomic writes, backup recovery, migration and corruption checks; preserve clock, RNG, needs, moodlets, relationships/grudges, mental state, habits, character/outfits, object reservations and actions or documented safe resume; uninterrupted vs save/reload continuation test; server authority |
| H5 | Relationship balance and controlled scenarios | Distinguish unsuccessful chat from argument; fix dishes frequency based on evidence; matched seeds support/isolation and sleep/stress; 4/6/8 people and multiple seeds; distributions and failures reported, never loosen thresholds just to pass |
| H6 | Visual/asset integration and performance | Real UV/tangents where needed, morph/pose clipping checks on extremes, front/back/side renders inspected, latest Blender sources and manifests saved; measure editor latency and runtime cost before optimizing |
| H7 | Release-quality integration of this slice | Fresh checkout/import/build, audio generation, regression suite, stable multiplayer pause test, keyboard/mouse playthrough, save/load and deployment artifact verification; README/checkpoint describe actual state |
| H8 | Continue the remaining approved roadmap | Implement existing mental-health axes between creator milestones where dependencies allow, then world/careers/economy and other planned systems in tested vertical slices. Do not pull reserve circulatory/LLM/social-policy proposals into scope automatically. |

H0 and H1 may finish together. After every gate, update the checkpoint with exact evidence and next work.
Do not mark the whole project complete after one milestone. Missing UI, persistence, or a failed test remains open.
Prefer fixing the existing implementation over adding duplicate systems.

## Publication authorization update (24 October 2026)

The owner explicitly requested comparing Godot `lifesim` with `peitn/Life-Simulator` and adding all missing implementations to GitHub in the current chat. This authorizes this synchronization. The earlier publication restriction below is retained as historical context and does not block this owner-requested snapshot publication. The synchronization reads the Godot server without changing it; it does not resume scheduled development or publish unfinished milestones as complete. See `docs/reviews/github-sync-20261024.md` for the transferred scope and actual validation.

### Historical publication restriction

Automatic approval review rejected publishing local commit `752543562decc55e1e76b0cf305ac3d093645e29` to GitHub main. The 63 changed files are already in Godot and were verified byte-for-byte. GitHub remains at the old baseline. Do not publish these sources/assets or subsequent changes through another branch, PR, connector or command until the owner explicitly approves publication after being told of this block. H0 publication is deferred; continue H2 and later independent work on Godot/Blender instead of retrying the blocked push.

Until publication is approved, the Godot copies of this plan and CHECKPOINT are authoritative. This restriction overrides the GitHub-write steps below. Coordinate GPT writes with atomic `DirAccess.make_dir_absolute("res://previews/gpt-development.lock")`; proceed only on OK, store owner.json with run ID and heartbeat, and release only your own lock. Do not remove an existing lock based only on its age. Verify the previous run has stopped, or stay read-only and report the block. GitHub is read-only during this restriction.

## Run protocol

1. Read fresh remote state and the actual current GitHub HEAD. Inspect `AGENTS.md` if present.
2. Acquire a lease in `docs/automation-state.json` on GitHub using the current blob SHA as a compare-and-swap through `update_file`. Store a unique run ID and UTC expiry no longer than 50 minutes. Re-read to verify ownership. If an unexpired lease belongs to another run, do read-only review and exit.
3. Read the room for other active work. Work from the newest verified sources; compare file hashes before applying server patches. Do not overwrite a changed file or force-push over another contributor. The lease coordinates GPT runs only; it does not lock Claude/Grok.
4. Back up before mutations. Complete one bounded, meaningful unit; refresh the lease before expiry. Prefer a short run that leaves a clean checkpoint to an unbounded refactor.
5. Run meaningful tests. Inspect stderr as well as exit code; timeout is not success. Visual changes need actual rendered inspection. Existing engine leak warnings must be distinguished from newly introduced errors.
6. Commit verified changes and push without force, preserving concurrent work. Synchronize only the files changed by this run back to Godot/Blender and verify hashes. On a conflict, reconcile or record an exact blocker; never reset remote work.
7. Update `CHECKPOINT.md` and the development log: completed work, changed files, tests/results, known gaps, exact next step and commit. Release the lease using compare-and-swap only if still its owner. Back up the verified server project.
8. Report concise factual progress to the user. Read the AI room as context; do not send room messages unless the user separately authorizes them.

If access fails, record the failure without claiming work happened. Do not repeatedly rebuild unchanged assets.
If the complete authorized queue is genuinely finished, disable this development automation and provide the final verified state.

## Initial review evidence

GitHub baseline before reconciliation: `85af65670ffe20a67d5725d1c163622cdec645fe`.
Godot had 20 changed tracked files plus C5, personality panel and test additions.
Review baseline: ten suites / 574 checks passed, a 2-day smoke run passed; full household matrix not rerun.
Prior room report: household matrix 105/106, four-character unsuccessful-chat rate remains open.
The old Blender clothing generator omitted the cat hoodie; server source is newer.
## 24 October: active server lease v2 (override)

While GitHub publishing is restricted, use the tested `tools/automation_lock.gd` and `docs/automation-lock.md` protocol (40-minute renewable lease, 20-minute grace, owner verification before writes, recovery to archive, and run history). This section supersedes the older raw directory-lock paragraph and the inactive GitHub CAS instructions during the restriction. Preserve a distinct run_id across tool calls; release it even if a run fails. Keep main and city work in their separate file namespaces.
