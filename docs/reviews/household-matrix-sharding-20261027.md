# Skeptical review — household matrix sharding, 27 Oct 2026

Run: main-fallback-1793128580-362647. Scope: test harness only, no production code diff.

## Implementation
`tests/test_household_matrix.gd`: `--seed-start` selects seed offset with count bound <=16; `--owner-run-id` is validated as a safe filename, begins with main-, max 64 characters. With owner ID, the test checks `G.owns(id)` immediately before report write. Output filename includes run ID, sizes, seed start/count, days; JSON includes these plus test-script and E module SHA-256. Readback is compared to the serialized bytes. Legacy invocation without owner ID retains historical report filename.

## Evidence and non-evidence
Combined 4/6/8 seed0 30d run timed out at 120 seconds after interim 4/6 checks: exit=None; no completed test summary; DO NOT count as PASS. Isolated 8:0 30d 15/15 PASS (92.1s, exit0); 4:1 30d 15/15 PASS (46.9s, exit0, first harness revision); 4:2 30d 16/16 PASS (49.4s, exit0, final revision with readback). Invalid seed interval and path-like owner ID were deliberately rejected with exit1, no timeout. Syntax checker 60/60 (does not cover tests). Existing 20 ObjectDB leak warnings. No UI change or render required.

Reports: `previews/testlogs/household_matrix_main-fallback-1793128580-362647_s8_seed0_n1_d30.json` (archived original-format 8:0), `previews/testlogs/household_matrix_main-fallback-1793128580-362647.json` (4:1), `previews/testlogs/household_matrix_main-fallback-1793128580-362647_s4_seed2_n1_d30.json` (4:2). The original canonical report contained 12 runs and was restored SHA-256 285059c9e87e6a115b14a505405c6489df8a6bd61f539c41a950e757faf89bbf. Run-specific report provenance hashes are checked separately.

## Gemini skeptical audit and independent adjudication
Two Gemini reviews were requested on the actual harness algorithm/change and measured outputs. Valid: combined timeout invalidates full pass, one-seed samples are statistically insufficient, and separate invocations should preserve per-shard provenance. Overstated/incorrect: (a) zero depressive episodes in one 30-day run is NOT proof of dead-code; (b) it claimed 21 ObjectDB warnings although actual stderr states 20 instances; (c) it described a 16-seed canonical matrix, while this test defaults to 4 seeds x3 sizes; a separate household-dynamics test has 16 seeds; (d) a byte-for-byte readback detects immediate write failures but is not an fsync or atomic durable transaction. Guard denial on ownership loss was reviewed statically, not exercised in a real lost-owner test. No confidential personal data was sent.

## Remaining risk
The full 12-combination 30-day matrix is NOT complete: 3 combinations independently certified, 9 remain. Aggregate criteria across all four seeds per size are not yet verified. The known household_dynamics 79/80 seed outlier remains. Remote full backup quota remains unresolved. Pre-existing 20 ObjectDB leaks need separate investigation. Keep E marked PARTIAL until the full matrix and other E regressions pass.
