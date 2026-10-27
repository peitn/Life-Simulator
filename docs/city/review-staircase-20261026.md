# Staircase skeptical audit — 2026-10-26
Run city-1793018567-220376. Gemini received actual complete generator, Godot builder and validator plus geometry/test evidence; two responses. Gemini did not execute code or see renders.

1. Claimed cumulative boxes overlap: rejected. Their heights start at floor but occupy distinct .3m Z slices. Actual Step07 z[-2.4,-2.1], Step08[-2.7,-2.4], Step14[-4.5,-4.2]. Added exact dimensions/centers and pair intersection test. It passes with10micron linear tolerance. First1e-6m3 threshold failed last seam due4.77e-7m rounding, independently diagnosed and corrected.
2. Claimed disabled7 test cannot fail: disproved by executed negative exit1 with exactly3ray failures. Repeated followup concern about unexecuted flag contradicted by actual command/log. No persistent collider disabled.
3. Claimed bounds mismatch: no alternate actual bounds identified; actual AABB min(0,0,-4.5),max(1,3,0) matches manifest and both coordinate systems. Rejected.
4. Exact124tris intentionally locks fixed artifact; deliberate geometry edits must update baseline. Not generic optimizer test.
5. Claimed UV count mismatch from per-loop UV: glTF splits vertices at attribute seams, pervertex UV/normals count matches POSITION. Actual import passes. Rejected; followup acknowledges.
6. Followup bottom socket offset: intentional lower floor rear corner at bottom.position+(0,0,-2); floor origin is front corner and lower landing occupies z[0,2]. Upper floor front corner at (0,3,-4.5). Actual landing rays verify correct height. No automatic build-mode API assumed.
7. Suggested lateral edge rays and traversal useful; not implemented in bounded prototype. Centerline15rays, outsidewidth2rays, exactboxbounds and landingheight2rays are covered. Handrail, ceiling opening, capsule clearance, dynamic stair ascent and performance remain pending.

Final tests stair93/93 exit0, disabled7negative90/93 exit1expected, floor51/51 exit0; no timeouts. Existing18ObjectDB warnings. Three actual Blender views manually inspected. No gameplay acceptance claim.
