# H3 isolated SimVisual yield experiment — 2026-10-31

Run: `main-fallback-1793484974-59011`. Scope: diagnostic-only; NO production code changes, NO city/Blender/GitHub/AI-room changes.

## Why
Prior three-process H3 acceptance still FAILS (most recent baseline 8/17, extended ENet timeout 12/17; neither meets gate). Earlier client timeline showed ~19–23-second main-loop gaps during multiple visual creations. Test a narrowly scoped hypothesis: yielding *within* one SimVisual build can reduce the maximum main-loop stall, without touching network timeouts or authoritative state.

## Exact files
New `tests/diagnostics/h3_visual_yield_probe.gd` (SHA256 `929dfb3a1b69ab028d76fb8c6169ae61571b25358d1035d12442b372b8f3af64`), `tests/diagnostics/h3_visual_yield_probe.tscn` (SHA256 `b038d196ec3f8d257c603ceeb321f56395527894bdc160f58196add383c88607`). This report, CHECKPOINT.md, DEVLOG.md also updated. Production `scripts/sim/sim_visual.gd` unchanged, source hash `2883e642f792199ecd98aa0c0541ce48230cf28b2035b16b6081d30cc0af6dc3`.

The probe verifies exact source hash and unique function-scoped text anchors before creating an IN-MEMORY GDScript copy. Both variants add only a completion marker. The staged variant awaits after hair build and foot details, before the wardrobe build, and awaits nested coroutine calls. This is a research prototype, NOT safe to transplant to production: `_built=true` occurs before completion; _ready and external calls do not automatically wait; cancellation, look updates, shared cache, reentrancy and in-flight network state are not handled.

## Real headless Godot process results
Four independent runs of each mode, all exit=0, no timeout. Times in milliseconds.

| Pair | Baseline elapsed | Baseline max _process gap | Staged elapsed | Staged max _process gap |
|---|---:|---:|---:|---:|
| 1 | 3705 | 3715 | 3730 | 1417 |
| 2 | 3677 | 3686 | 7441 | 2747 |
| 3 | 3674 | 3683 | 3891 | 1331 |
| 4 (corrected structural assertions) | 3638 | 3647 | 3725 | 1416 |

The initial baseline attempt had exit1 despite successful model creation because its pass predicate inspected a freed node after queue_free; corrected before the four certified pairs. The final corrected pair independently asserts **35 MeshInstance3D, one Skeleton3D, one Label3D, model present** for each mode. Initial label_present metric incorrectly assumed the generated Label3D node name; corrected to type-based find_children. No assertion of semantic/render parity beyond structural counts.

`godot_check`: 60/60 PASS. Independent unchanged production `tests/test_character_net.tscn`: 97/97 PASS, exit0. Existing ObjectDB warnings (20 instances) appeared in some probe runs; not claimed as clean stderr. No visual rendering test: headless only. The 17-gate three-process H3 acceptance was **not rerun** in this isolated step and remains FAILED/PARTIAL.

## Gemini skeptical audit
Pre-code review warned about coroutine lifecycle, partially initialized state, freed nodes, headless-vs-graphical comparability, and lack of network causality. Post-code review flagged a misleading label metric, weak structural parity, and a 7.4s staged outlier; these were checked, the label metric fixed and the structural assertions strengthened. Gemini initially called the 7.4s run a failure/deadlock without evidence; a follow-up corrected this: exit0, no timeout, completed model. No proof of a production solution.

## Conclusion and exactly one next step
This isolated probe demonstrates yielding between expensive build phases can reduce *measured* maximum per-frame blocking (baseline ~3.65–3.72s vs staged ~1.33–2.75s in these runs), though total completion time varies. It does not demonstrate ENet recovery, renderer parity, cancellation safety, or H3 completion.

**NEXT SINGLE STEP:** design and test a guarded asynchronous SimVisual lifecycle (explicit `building/ready/cancelled` state and completion signal) in an isolated test, including `apply_look` during build and deletion before completion, before any production or three-process integration change.
