# Life Simulator — direct world interaction and baseline furniture/action rendering fixes

Date 2026-10-30 Europe/Prague; run `main-furniture-visual-1793316783-108458`. Canonical Godot project `lifesim`, main v3 lock.

## User-visible changes already implemented

- `main.gd` + new `scripts/ui/world_interaction_picker.gd`: left mouse click and touch on a visible character selects the locally controlled character (offline) or shows ownership refusal; projected pick on known SmartObjects opens the HUD's contextual action menu. No command is sent automatically; `hud.gd` sends choices exclusively through `NetSession.request_command`, retaining authenticated action authority and content filters. Approximate screen-space picking, not mesh triangle-level collider picking, and some props under HUD remain occluded.
- `scripts/world/world_builder.gd`: the two previous decorative dining chairs each have four real legs; sofa pose offsets move toward cushion front. Added a quilt mesh to each starter bed.
- `scripts/world/smart_object.gd`: two `DuvetCover` meshes rest flat when unoccupied and rise above lower body during an active reserved lying action, lowering afterward. A simple visual blanket, **not** physics cloth.
- `scripts/sim/sim_agent.gd`: seated facing is now furniture-aware (TV vs sofa), action ids feed the visuals. New `scripts/world/dining_detour.gd` computes a deterministic two-corner visibility-graph path around the starter dining table to avoid the prior through-table walking of characters. This is **not** general navigation or full rigid-body collision.
- `scripts/sim/sim_visual.gd`, `scripts/assets/character_anims.gd`, `scripts/sim/sim_puppet.gd`: clips for reading (with a visible open two-page book attached to real right-hand bone), phone texting/doomscrolling (phone in hand), cooking (arm stirring motion), eating (hand-to-face motion), and existing idle/walk/sit/lie; action clip passed through native/network puppet presentation. Lying pivot shifted upward and towards the bed foot to clear the pillow. Low-detail book and phone are placeholder meshes; no full grasp IK.
- Existing appearance sliders, skinned character mesh, save schema, personality/psychology, and ENet validation untouched apart from presentation-side action-id propagation.

## Tests and observed limitations

- New real production world regression `tests/test_world_interaction_visual.gd/.tscn` **27/27 PASS** on final quilt implementation (mesh support, projected candidates for 9 objects, popup options, real skinned character props/animation, three detour routes), exit0.
- Existing player commands **40/40 PASS**, real offline creator/interaction/save-and-load **81/81 PASS** on repeat. An earlier concurrent run of this 81-case test had **80/81**, failed at exact uninterrupted/reload comparison; it passed on rerun. Treat as intermittent; keep monitoring. Additional save-continuation **12/12 PASS**, 14-day household determinism **5/5 PASS**, browser-responsive menu **22/22 PASS**. Static syntax check **60/60**.
- Real native Mesa GL Compatibility graphical screenshot `previews/main-furniture-visual-1793316783-108458/native-couch-bed.jpg` produced exit0. It shows the legacy **stylized** humanoid models; it does not certify head/pillow and limb/cushion penetration in every body morph and pose. The initial flat duvet appeared below/alongside actor; subsequently added lifting duvet and tested moving y=0.64 to 1.02 with an occupied bed and lowering after release.
- Browser export **SUCCESS**, new 133MB debug web build at https://peiti-godot-mcp.hf.space/play/lifesim/. Actual smartphone/WebGL performance and post-export physical taps **not independently certified** on user hardware. Software SwiftShader/llvmpipe can stall.
- Original screenshot suggests character realism remains low (stylized, low-geometry features). No full high-poly base sculpt, high-detail body rig/IK, layered cloth collision solver or full animation library delivered.

## Next implementation priorities (separate art/animation milestones)

1. Build high-fidelity Blender character asset with watertight anatomy, multi-resolution LOD and facial rig; preserve the existing continuous character schema, independent identity vs appearance, and owner authority.
2. Correct hand/foot props and full procedural IK on chairs, sofas, beds; pose-dependent layered cloth and pillows with no face occlusion.
3. Replace fixed table-only detour with environment-aware navigation and validated object colliders, including per-seat pose anchors.
4. Expand cooking, reading, meals, shower, bed entry/exit, social interaction with matching props, transition animations and sound.
5. Profile web GPU/CPU/long-frame stalls; improve responsive mobile controls and run screenshot/dynamic tests on real Android and desktop.

The specific fixes above do not amount to completing the overall H3/H6/H7 production gates.
