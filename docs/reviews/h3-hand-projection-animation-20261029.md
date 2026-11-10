# H3: preview/spawn hand bone projection and animation phase — 29 Oct 2026 UTC

Run: main-fallback-1793250847-47344. Fresh source/checkpoint/sequence/v3 lock/history inspected. No successful primary MAIN development in prior 75 min (latest primary 28 Oct 20:56:25 UTC). v3 exclusive MAIN lease acquired, running history verified, pre-edit remote project backup 374207 KB / library 9115 KB. No production/UI, city-owned, Blender, GitHub or AI-room changes.

## Exact source change and observed result
Changed ONLY `tests/test_h3_rendered_parity.gd` (final SHA256 b9b9492201a9a978d476273d140d3b2e98d9de59304ce08d314c279f584f1b87) before documentation. Added `_hand_projection()` diagnostic reading real Skeleton3D hand_l/hand_r world poses, camera.unproject_position, visual root/body-pivot/skeleton transforms, and AnimationPlayer current clip/time/playing status. Test checks both projection dictionaries exist and prints their values while actual preview/spawn meshes share the SAME SubViewport camera. Existing test restores pose, finger bends, transforms and parent; no gameplay state or UI source changed.

Actual graphical Xvfb/Mesa/OpenGL runs **124/124** twice, child rc0, ~18.2 and 17.5s, no timeout; 32 new PNGs (16 per run). Original hand crop discrepancy reproduced: unregistered IoU .021–.108, horizontal shift 36–38px, registered IoU .785–.811. Distinct residents Nora/Mira and normal/narrow windows. Preview and live root/body-pivot/skeleton transforms are all identity in capture. **Preview AnimationPlayer idle at t=0.0** (preview visual process disabled), while live AnimationPlayer idle at t=.115–.84. Hand_l preview world x=.279589 vs live x=.234–.241; hand_r preview x=-.279589 vs live x=-.231..-.224. These are true differing bone poses in one camera, not a mere different root or camera transform. The hand camera size=.33 magnifies ~.04–.055m pose differences to dozens of pixels. This is **strong evidence of animation/pose-state mismatch in the QA comparison**, not yet a proven causal mechanism or production spawn defect.

Other actual regressions: independent cold-process verify **19/19** exit0 14.2s, H3 playable slice **81/81** exit0, syntax check **60/60**. Known ObjectDB20 warnings; no final parse errors or timeouts.

## Skeptical Gemini audit and independent verification
One actual Gemini text-only review of the precise diagnostic diff and test results. Gemini correctly warned that phase mismatch correlation alone is NOT causal proof, recommended a controlled same-frame comparison and robust animation/skeleton restoration. Its claims of proven IK/pose-blend fault and nonlinear orthographic projection are speculative; no IK or camera mismatch demonstrated. It did not run tests or inspect screenshots. Source inspection confirms preview visual PROCESS_MODE_DISABLED, live animation progresses; same camera used for both in test. Remaining: animation phase alignment and safe restoration, then strict **unregistered** hand crop parity. H3 PARTIAL.

## Exact generated PNG paths
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Mira-Cold-1280-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Mira-Cold-1280-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Mira-Cold-1280-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Mira-Cold-1280-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Mira-Cold-360-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Mira-Cold-360-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Mira-Cold-360-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Mira-Cold-360-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Nora-Cold-1280-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Nora-Cold-1280-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Nora-Cold-1280-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Nora-Cold-1280-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Nora-Cold-360-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Nora-Cold-360-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Nora-Cold-360-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-animdiag-Nora-Cold-360-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Mira-Cold-1280-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Mira-Cold-1280-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Mira-Cold-1280-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Mira-Cold-1280-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Mira-Cold-360-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Mira-Cold-360-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Mira-Cold-360-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Mira-Cold-360-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Nora-Cold-1280-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Nora-Cold-1280-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Nora-Cold-1280-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Nora-Cold-1280-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Nora-Cold-360-handcrop-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Nora-Cold-360-handcrop-spawn.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Nora-Cold-360-preview.png`
- `previews/h3-render-main-fallback-1793250847-47344-registered-Nora-Cold-360-spawn.png`
