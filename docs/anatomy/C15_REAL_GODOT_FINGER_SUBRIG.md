# C15 — first actual 28-bone finger subrig running on the playable Godot character (27 October 2026)

## What changed
C14 provided twenty independent finger *blend morph* channels on an unchanged 17-bone avatar, plus a separate true 28-phalange Blender anatomy demonstration. C15 brings that **actual hierarchical phalange-bone concept into the Godot runtime** without changing networked character/save schemas.

New file: `scripts/assets/finger_phalange_subrig_c15.gd`. It reads the real 194-bone Blender anatomy landmark atlas already stored in `assets/anatomy/anatomy_runtime_proxy_v1.json`, selects fourteen actual phalange head/tail coordinates **per hand** (two thumb and twelve other finger segments), maps them into the existing playable GLB `hand_l`/`hand_r` bone rest frames and builds:
- **Two optional true Godot `Skeleton3D` nodes with fourteen *distinct hierarchical bones* each** = 28 genuine independent in-engine bone transforms.
- Two `BoneAttachment3D` parents attached to the corresponding real player's **17-bone production character hand bones**. The subordinate skeleton therefore moves with the live player's elbow/hand animation, while retaining independent local phalanx rotations.
- 28 individually animated bone surface `MeshInstance3D` child pieces bound to the matching subrig joint using `BoneAttachment3D`. These are lightweight **procedural cylinder visual bone references**, not the high-definition Blender `anatomy_independent_finger_joints_c14.glb` geometry.
- `Subrig.bend(anchor,digit,"proximal"/"distal",strength)` with true `Skeleton3D.set_bone_pose_rotation`, plus a 30%-angle dependent last segment for non-thumb fingers. Separate bones, parent-child motion, not merely 3D GPU morph deltas. Independent finger contact physics is still **not running**.
- There is **no creation cost for normal game characters**; rig is constructed only on explicit opt-in local character-editor action, and reused on subsequent toggles.

In `scripts/sim/sim_visual.gd`, `set_finger_skeletal_view(bool)` toggles the bone model lazily, temporarily hides precisely the two original skinned finger+nail render instances (with per-object exact visibility restoration), and synchronizes the new skeleton with C14 independent bend sliders or C12 combined digit preset angles. Ordinary model, 17-bone Skin, movement animations, multiplayer authority and CharacterData remain unchanged.

In `scripts/ui/character_preview.gd`, the existing expandable **Prsty: jednotlivě** panel now includes **Kostra článků prstů: vypnuto/zapnuto**, which actually builds and displays both true 14-bone subrigs. The same C14 proximal/distal sliders animate the corresponding **real bone hierarchy** while the opt-in mode is enabled. The creator/editor preview remains a separate `SubViewport` world, with no server-side RPC, collision hitboxes or storage changes.

## Testing
`tests/test_finger_phalange_subrig_c15.gd/.tscn`: real 17-bone playable GLB+preview integration, **39/39 PASS**, covering:
- no subrig allocated by default, exactly fourteen new bones and fourteen attachment/mesh objects per hand on request;
- correct hierarchical parent-child relationships including three distinct index-finger segments, anchored to the real animated player's `hand_l/r`;
- proximal skeletal rotation moving a child phalanx, independently from other fingers/right hand, followed by independent distal skeletal rotation;
- whole new 14-bone hand following the actual live forearm animation, invalid input rejection, node reuse on toggling, exact legacy skin/nail visibility restoration;
- actual editor button and live 3D slider driving a corresponding `Skeleton3D` pose, isolated from gameplay/identity/mind.

This is a significant *skeletal visual integration* over C14, but still **not 28 independently physics-simulated rigid bodies**, not an inverse-kinematic grasp model, and not a transparent replacement of the original character's 17 production bones. Blender C14 standalone rigged GLB exists separately and still has not been imported as the runtime bone meshes. Real functional collision/grasp/Elmer transfer require a separate server-authoritative and measured physics integration.

## User-approved handoff to Life Simulator AI Room Relay
Current canonical project plus C15 code/test/report handed off as actual source attachments; reconstruction manifest in room. Do **not** overwrite city worker file ownership or push GitHub without explicit user authorization.
