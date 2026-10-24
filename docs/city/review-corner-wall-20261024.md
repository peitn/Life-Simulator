# Corner wall audit — 2026-10-24
Run city-1792873902-112872.
Gemini actually reviewed the complete Blender generator, Godot builder and initial31-check validator, with existing wall dimensions and render/mesh test results. It did not directly access Blender or Godot.

Findings and independent disposition:
1. Claimed HIGH corner collider gap/overlap: rejected. Review miscomputed second box bounds: centerZ=-1.05, length1.9 => [-2,-.1], NOT [-2.1,0]. First box Z=[-.1,.1]. They meet on a plane without volume overlap. Added exact box positions/sizes/shared-boundary checks and diagonal ray + swept70cm sphere tests. Final36/36 passes; this is not a full CharacterBody3D sliding/locomotion test.
2. Exact492-triangle assertion called brittle across Blender versions: retained for this fixed exported artifact and manifest; intentional regeneration with a different Blender version must update measured manifest and expectations explicitly. Budget remains<3000.
3. Bevel strip UV distortion: accepted limitation for future textured variants; only large planar face1UV/m density certified. Current original solid-color PBR materials have no texture maps. No textured-finish claim.

Evidence:
- Blender generator exit0; three manifold meshes, positive polygon areas, unit normals, large quad UV density within2%,492triangles.
- Actual480x480 CyclesCPU24sample outer/inner/top renders displayed and inspected: continuous L core, inner/outer skirting, no missing faces/obvious seam gap. Render noise remains at24samples.
- Godot imported bounds and axes, pivot,3meshes,492triangles,UV/normal arrays,colliders,snap sockets and adjacentwall raycasts;36/36 exit0.
- Existing solid37/37 and doorway31/31 unchanged; total104checks. No timeout. Existing18ObjectDB warning; Blender bundled exporter emitted Python invalid-escape SyntaxWarnings, no failed render/export.
- Corner validator3.729ms warm /10.121ms first observed run; import+physics fixture duration, NOT FPS.
- First transfer/import invocation happened before base64 transfer cell finished: Godot snippet parse error(undefined), then missing builder. No asset writes occurred. Retried after complete transfer, successful.
- Builder now checks previous output hash before save and lease ownership; not an atomic filesystem CAS against arbitrary external writers. Final builder parses; original build succeeded before adding hash guard.

Remaining: actual locomotion/navmesh, textured bevel UV treatment, large scene performance, saved corner+doorway demo and main UI integration. Next single module: compatible window opening. Existing wall/doorway assets were not regenerated.
