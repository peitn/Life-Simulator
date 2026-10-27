# Character anatomy, detailed appearance controls and sleeve join — 26 October 2026

Run: `main-character-audit-1793036435-242124` on the canonical live Godot project `lifesim`. Shared main task lease was acquired and renewed. No city-owned files, multiplayer protocol, private psyche/identity schema, GitHub or Blender city libraries were changed. A pre-edit project/library backup was taken. Scope is partial **functional audit and tangible repairs**, not a claim of complete anatomical certification.

## Inventory and UI findings

The CharacterData v8 data model already had detailed geometry controls but the live creation and edit interfaces only exposed name/age/height/hair style, wardrobe, sexuality (offline edit) and psyche/personality axes. Existing render-capable appearance parameters included:
- body: frame, muscle, fat, shoulders, chest, bust, waist, hips, leg length, head size, neck length;
- face: head width/height, forehead slope, eyebrow arches/height, eyes/sockets, eyelids, nose length/width/tip/bridge, cheekbones and fullness, jaw, chin, mouth, lips, philtrum, ears and neck width; asymmetries, eyelashes and tooth shade/gap/crookedness;
- skin: melanin, undertone, blood perfusion/redness, freckles, moles, acne, vitiligo, aging, oiliness/dryness; hair/eyebrow pigment and density; iris/heterochromia and makeup.

New `scripts/ui/appearance_slider_editor.gd` exposes exactly **72 functioning float controls and 4 enum selectors**, grouped into 6 categories (body 11, face 38, skin 10, hair 6, eyes 2, makeup 5) in a mobile-width-safe, single-category selector. Uses the real `CharacterSchema.fields(group)`, emits properly typed events and uses `load_data()` with no signal reentrancy. Source `scripts/ui/character_creator_panel.gd` and `scripts/ui/character_editor_panel.gd` now wire fields to isolated CharacterEditSession drafts with read-only separate 3D preview and undo/redo. Live editor commits only on Apply through existing validated server/offline authority and native ENet authenticated network transactions; Cancel discards. Fixed previously UI-accepted invalid age 96–110 and height 120–144 / 206–220 by aligning creator SpinBoxes with schema age18..95, height145..205. No new CharacterData/SaveGame schema migration, skin weights, network field exposure or multiplayer authority changes.

## Sleeve defect and corrective

Baseline actual point-to-**triangle** in Godot, default pink cat hoodie, 14 upper-rim vertices per sleeve:
- REST (both arms), before: **median 20.94 mm**, max 33.85 mm, 2 symmetric sides.
- 90-degree elbow bend, before: **median 10.90–10.92 mm**, max 30.94 mm.

Correction keeps all 22 existing C5 sleeves and previously repaired arm/forearm/hand weights; extends the shoulder end of legacy sleeve rings +45 mm (1.164→1.209 m) and next ring +12 mm (1.096→1.108 m). Exact change documented in Blender authoring `tools/blender/clothing_c5.py`, with runtime compatibility in `scripts/assets/clothing_wardrobe.gd`. Runtime intervention is topology-guarded **70 vertices = 5 rings × 14**, and shifts only if **both 14-vertex old-height rings** are found. Future generated assets at new ring positions are not shifted again. Identical offsets are applied to every corresponding body-morph target, source face normals and morph normals are recomputed, UV/tangent computed afterwards, and arm weights and bind indices remain unchanged. This is a surgical presentation-layer geometry correction; existing production LSX source bytes were not rewritten. No claiming GLB re-export from Blender service or fixing unresolved extreme cases.

After correction, actual Godot skinning and triangle distance in default case:
- REST: left median **10.625 mm**, max **21.080 mm**; right median **10.638 mm**, max **21.092 mm** (~49% median improvement).
- 90-degree bent: left median **16.612 mm**, max **30.067 mm**; right median **16.590 mm**, max **30.065 mm**. Thus **the bent median became worse** by ~5.7 mm versus baseline, but remains under the defined 18 mm regression; neither rest nor bend is watertight. Geometry visual quality should not be judged solely from nearest-distance metrics.
- Updated strict surface regression `tests/test_cat_sleeve_surface.gd` to bound both actual pose metrics; updated old vertex-only characterization `tests/test_cat_hoodie_sleeve_gap.gd` to 9–16 mm median/25 mm worst vertex-only proximity on `mikina` and `kawaii_kocici_mikina`.
- Read-only exploratory 4 *extreme* body profiles × 2 arm poses (including zero/max body fat, frame, shoulders, bust, hips, and signed face extremes) all strict-valid after naming character. Found unresolved worst-case right-side max **44.87 mm** at all-max body morph with elbow bent, and right/left max **38.3 mm** on one mixed profile. This is NOT a full animation coverage/rigging pass and **must be corrected or assessed visually** before final art acceptance.

## Tests executed after changes (actual Godot outputs)

| Suite | Result |
| --- | --- |
| New creator and edit UI integration, body/face/skin preview and authority | 108/108, exit 0 |
| Offline full first-playable scene | 45/45, exit 0 |
| Existing offline editor | 55/55, exit 0 |
| Body-morph geometry/rig/scaling | 62/62, exit 0 |
| Head/teeth/lashes/expression geometry | 66/66, exit 0 |
| Real authored preview | 13/13, exit 0 |
| Clothes C5 shared models | 16/16, exit 0 |
| Character network strict validation | 70/70, exit 0 |
| Real two-client authenticated network edit | 27/27, exit 0 |
| Listen-host owner edit | 10/10, exit 0 |
| New surface diagnostic, rest + elbow bends | 0 failures, exit 0 |
| Legacy vertex proximity, 2 styles | 20/20, 0 failures |
| Godot bundled syntax check | 60 existing scripts OK; new script compiled and exercised |

Existing Godot shutdown warnings (ObjectDB instances) remain. The first draft of the new UI test timed out due to a **test-only reference to a freed creator node**; corrected the fixture and re-ran successfully at 108/108. An early C5 compilation error caused by space indentation was corrected and all final Godot checks and dependent suites then passed. These are not claimed as first-try clean runs.

## Remaining work (explicitly NOT done)

- Fingertips/individual finger and toe proportions, sole/instep/foot width, nails, nipples and navel are **not added** by the 72 new slider UI controls. Current body mesh/skeleton only has hand and foot bone chain proxies; adding genuinely independently deformable digits and nail/skin surface details requires model/skin/rig expansion and a versioned schema + safe migration. Do not fake sliders that only alter a label.
- Full deformation matrix for all clothing, animations, wardrobe collisions/body variants, high-resolution vertex self-intersections, normal/UV/tangent continuity and actual screenshot inspection, **not yet complete**. In particular, the extreme cuff/shoulder gap above remains.
- Full blank-household creator, advanced body detail generation and interaction animation QA remain separate workstreams.
- Web build remains offline and the end-user device's earlier DNS/link opening error is not fixed by this character change.

**Next steps:** H2b prioritize skinned sleeve-to-shell junction under extreme fat/shoulder/torso cases and cuff geometry while maintaining authentic arm weights, with actual rendered screenshot before/after; then source-author real deformable hands/feet/digits, nails, navel and nipple detail as optional anatomical geometry with consent/content-appropriate display and proper schema+codec/save+network version testing. All sexes and identities must remain independent of body choices.
