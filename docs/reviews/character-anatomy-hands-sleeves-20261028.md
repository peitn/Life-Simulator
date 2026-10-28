# Character anatomy, hands, sleeve seams and ankles — 28 October 2026

Canonical project: `lifesim`. Owner: `main-anatomy-review-1793199275-7123`.

## Reproduced visual defects and repairs

Direct Godot GL Compatibility framebuffers exposed mismatched skin shading between the palm and procedural fingers, a lateral rather than medial thumb, incorrectly ordered digit lengths, and separate capped barefoot ankle/sole cylinders with visible circular intersections. Prior conversation summaries reporting C16 integration did not match the currently loaded hand source; current source and live render were used as evidence.

- Fingers now share the exact palm/forearm skin ShaderMaterial and supply CUSTOM0 rest positions. Feet use that same material. Nails retain their own surface. Existing StandardMaterial handles remain as compatible fallbacks.
- Digit construction and curl endpoints use one definition. Anatomical order is index, middle, ring, little, thumb on each hand; the middle is longest and the little finger shortest. Both thumbs originate on the medial palm edge. Finger roots overlap the actual rounded palm and remain separate surface geometry, not a welded replacement for the palm.
- All vertices and the nail of each digit receive the same four-neighbor displacement sampled at its root, rather than changing nearest-source samples along the digit. Body changes therefore cannot shear a nail away from its finger. Existing independent curl morphs and both hand bones remain intact.
- A continuous elliptical heel/instep/ankle mesh replaces intersecting sole and ankle cylinders. The upper shaft follows the shin, the plantar surface and toes follow the foot, and weights blend across the ankle. Upper and lower caps are internal end closures rather than exposed rings at the instep. Barefoot visibility still follows shoe selection.
- Each legacy sleeve's upper ring is brought 90% toward the closest segment of its matching shirt-shell cross-section. Positions, all ten morph targets, and skin weights are sampled from the SAME shell triangle using barycentric interpolation. The remaining 10% ring spacing prevents collapsed corners. This preserves 70 vertices per sleeve, recomputes base/morph normals, and never changes opposite-arm or leg weights. Correction is cached once per wardrobe source, not evaluated every frame. Production LSX/Blender binary assets were not re-exported.

## Actual hand-size control and compatibility

CharacterData schema **v9** adds public `body.hand_size`, float -1..1, default 0. Both hand bones scale from 0.8 to 1.2 around their actual joints. This changes the existing palm and procedural digits/nails together, while forearm length stays independently controlled. `BodyMorphs` and `AppearanceResolver` quantize and transport the scale; `SimVisual` applies it. The creator/editor's schema-generated body category exposes **Velikost rukou**. Random generation appends the new draw so prior draw order for existing fields is preserved. Identity does not determine hand size.

The v8→v9 codec migration copies its input and fills missing hand size with neutral 0; old proportions remain unchanged. Tests cover strict validation, compressed share-code roundtrip, migration input immutability, real bone/vertex scale, reset behavior, UI draft/preview updates and variation across generated characters. No private mental-state fields or multiplayer authority rules were changed.

## Measurements and verification

Default cat hoodie true skinned point-to-triangle seam distance:

| Pose | Before median L/R | Before max L/R | After median L/R | After max L/R |
| --- | --- | --- | --- | --- |
| Rest | 10.625/10.638 mm | 21.080/21.092 mm | 1.070/1.064 mm | 2.117/2.118 mm |
| Elbows bent 90° | 12.034/12.031 mm | 21.266/21.278 mm | 1.177/1.176 mm | 2.110/2.111 mm |

Five body profiles × eleven long-sleeve outfits × four arm poses × both sides = **440 observations**, **1012/1012** assertions. Worst median **1.765 mm**, worst maximum **2.767 mm**. Final regression bounds are 3 mm median / 4 mm maximum. This is a narrowed seam, not a welded/watertight garment.

Verified suites:

| Suite | Result |
| --- | --- |
| New v9 anatomy: morph/nail attachment, actual sizing, extreme bodies/gestures, ankle flexion, migration | 231/231 |
| Existing modeled hands | 73/73 headless; 76/76 graphical |
| Existing finger curls/gestures | 157/157 |
| Barefoot anatomy | 30/30 headless; 34/34 graphical |
| Sleeve skin ownership | 166/166 |
| Entire wardrobe geometry and 5712 combinations | 7319/7319; 172 parts; zero collapsed triangles |
| Body morphs and rig | 62/62 |
| Neck length, migrations and scale | 36/36 |
| Full generated head/neck seam | 56/56, 73.96 seconds |
| Face details/expressions | 66/66 |
| Character codec/data | 157/157 |
| Public character network validation/replication | 70/70 |
| Save/load | 46/46 |
| Appearance editor, including actual hand-size input | 111/111 |
| Existing live editor | 55/55 |
| Full playable scene/save-resume | 54/54 |
| Bundled script syntax check | 60 existing scripts OK; new scripts separately executed |

The initial wardrobe test reported two failures because the prior test did not recognize the already-existing intentional `top=zadne` and fully unclothed outfit. Updated that test's exemptions/composition expectation; geometry did not need to change. The first foot test also assumed all vertices were rigidly foot-bound and used a tolerance smaller than Godot's 16-bit GPU weight quantization. Updated it to verify the correct foot/shin chain, rigid upper shaft, and two-quantization-unit sum tolerance. Actual ankle-flexion behavior is independently checked by the new test.

Graphical captures under `previews/main-anatomy-review-1793199275-7123/` include `v9-small.jpg`, `v9-large.jpg`, `v9-relaxed.jpg`, `v9-fist.jpg`, `v9-whole.jpg`, `v9-feet.jpg`, and `v9-flexed_ankle.jpg`. These are real rendered runtime geometry, inspected directly, not generated illustrations. Source backups live in the same run's `before/` tree.

## Scope and remaining limits

This remains a stylized low-poly character. Palms/digits, individual toes/nails and body accessories use overlapping surfaces, not a single welded high-resolution anatomy mesh. Digit curls are independent GPU morphs on the existing hand bones, not a full phalange skeleton or collision solver. The sampled sleeve matrix does not certify all animation interpolation or arbitrary contacts. The full neck-seam generator test exceeded its initial 45-second budget; a separate longer run completed in 73.96 seconds with 56/56 assertions and exit 0, recorded in `neck-seam-final.json`. Known inherited ObjectDB shutdown warnings and GL Compatibility subsurface-scattering limitations remain. Expected decompression errors in the codec's corrupt-input tests are negative test cases.

The 114 MB web export completed at https://peiti-godot-mcp.hf.space/play/lifesim/ . No claim of a real end-user browser/device test; native graphical runtime and export were verified. GitHub publication was not performed.

Next art pass: weld palm/digit and toe junctions, inspect collision/self-intersection throughout longer animation sequences and complete high-resolution anatomical surfacing while preserving the now-tested schema, morph and seam behavior.
