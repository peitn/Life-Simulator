# M2 complete in city asset, interaction and authoring scope
29 October 2026. Run `city-m2-complete-1793307317`. Current Godot source is authoritative. Main task files were preserved.

## Delivered behavior
M2 now covers all nine existing starter furniture placements and their production action contracts with reusable city scenes. It retains the four original GLBs (sofa,single/double bed,fridge) and adds11fixtures: stove,counter,sink,shower,toilet,bathtub,dining table/chair,bookshelf,treadmill and a television/two-seat-bench assembly. All15 are selectable in the standalone catalogue. TV occupancy covers its bench as one assembly; no competing sofa reservation is created. Users/reserve/release from SmartObject remain authority through the existing M2 adapter; stable physical slots survive another user's departure.

Actual SimAgents cook,shower,read,exercise and watch TV through existing ActionLibrary entries, with normal completion/need effects,occupied rejection,cancel and leave-world cleanup. A runner starts on the measured .18m belt surface and returns to the approach point on exit. The flush walk-in shower has an open front and physical glass sides. Counter,sink,toilet,bath,table,chair remain equipment/decorations because the current simulator does not advertise dedicated actions for them.

Three additional closed-glass window walls (wide,double,arch) and three hinged-door variants (panelled,glazed,metal) are saved with physical colliders. Doors reuse the verified M1 hinge and refuse rotation into an obstacle. Walls use exact convex collider pieces from the source manifest. Window panes are closed/static. Original M1 assets remain unchanged.

The furniture composer has11editable templates,blank designs,up to64box/cylinderparts,dimensions/position/rotation,independent material/tint/collision,undo/redo,validated atomicJSON withonebackup,recovery,andscene/GLBexport. Text names commit on focus loss; dirty navigation and opening require discard confirmation. A file-selection guard prevents invalid indexes. Layout tested at390,640,1280px. Custom drafts are decorative; production interaction layouts stay on the measured catalogue scenes. User guide: FURNITURE_EDITOR.md.

12new repeating256px PBR surfaces (36PNG maps) join the6originalmapped surfaces. The editor offers18mapped surfaces plus11palette materials. These are actual albedo/normal/roughness maps. Metric UVs and tangent generation on mapped custom parts avoid relying on unsupported glTF triplanar mapping. A rotated elliptical cylinder retains bounds,normals,tangents and allthree map types after GLB roundtrip.

## Actual final verification
| Executed suite | Positive assertions |
| --- | ---: |
| Original furniture geometry/placement/collision | 141 |
| Original furniture, actual Main/SimAgent | 49 |
| Existing lifecycle/interleaving matrix | 489 |
| New fixture geometry,source GLB,physics,transforms | 297 |
| New fixture production actions,4yaw rotations,completion/cancel/leave | 244 |
| Editor schema,real controls,storage/recovery,export/responsive UI | 97 |
| Catalogue real buttons,all21entries,TV seats,platform lifecycle | 90 |
| Window/door variants and36PNGedge-seam checks | 76 |
| Existing asset/animation/WorldBuilder regression | 155 |
| Existing playable creator,commands,save/reload/cold start | 81 |
| **Total** | **1719** |

All positive children exit0/no timeout. Logs: `m2-final-core-20261029.json`, `m2-final-ui-20261029.json`, `m2-final-regression-20261029.json`. The orchestrator is `scripts/city/validate_m2_suite.gd`, args `<owned-run-id> <core|ui|regression|negative>`; it bounds child execution. The server syntax tool also reports60/60 (a sample, not a claim that every project file was included); all16changed GDScripts also passed individual --check-only invocations (m2-compile-20261029.json), in addition to direct execution.

Three meaningful negative controls exit1 EXPECTED: old sofa/doublebed slot ordering detects4failures; old TV slot ordering detects2failures; disabling one shower glass collider detects4rotated physics failures. Logs `m2-final-negative-20261029.json`. These are not positive assertions added into the total.

All11new fixture assets are below1000triangles: stove828,counter72,sink276,shower348,toilet180,bathtub264,table60,chair72,bookshelf432,treadmill96,TV84. Original assets retain2896/2472/4200/868triangles; the original4200-triangle doublebed remains an explicit measured reuse exception to the simple-module3000target. Source hashes and visual bounds: m2_furniture_manifest.json,m2_fixtures_manifest.json,variants_manifest.json. New placement_bounds describes the structural collider union; visual extents including decorative handles are recorded separately in the manifest.

## Actual visual and native inspection
12final v2 Godot Compatibility/llvmpipe JPEGs were saved and inspected: editor1280x900 and390x900; furniture front/rear/top and variants front/rear/top at1600x1000; real stove,TV(two users),treadmill,shower interactions at1280x900. Prefix `docs/city/m2-final-city-m2-complete-1793307317-v2-`. Corrected the initial white inspection floor so pale bathroom fixtures remain visible. Earlier v1 views are intermediate evidence. TV actor name labels can overlap; UI separately lists both users. The current character visuals/animations are reused and were not edited by this city task. No human-mesh-fit/FPS/navmesh/fullgame certification.

Blender `lifesim-city-m2-complete-kit` v1.1 has22files/1099010bytes; native `m2_complete.blend` reopened16modelcollections/134meshes (15catalogue assets +1editor example). All GLB hashes and triangle counts matched. Final editor example resynchronized after the last test export; exact hash is in m2_blender_native_manifest.json. The separate variant native reopened with20materials/54packedimages. Importer/generator sources persisted in Godot and Blender script libraries; existing16original city/furniture source GLBs remain byte-identical. Full native asset-kit names are in FURNITURE_EDITOR.md.

Two actual skeptical Gemini code reviews and evidence-based dispositions: review-m2-complete-20261029.md. Unsupported allegations were not treated as failures; concrete focus/file-selection issues were guarded and tested. A discovered UV/glTF mismatch was fixed and roundtripped. Gemini neither ran tests nor saw the images.

## Completion boundary and handoff
M2 is complete in the city plan's asset/interaction/authoring boundary. Start `res://scenes/city/m2_catalog_showcase.tscn` or `furniture_editor.tscn` (F6); the old M2 showcase links to both. Source SmartObject,SimAgent,WorldBuilder,ActionLibrary hashes match the run's initial snapshots. Starter-world replacement,collision-aware routing,live client replication and lot/build persistence remain M6/M7. Existing20ObjectDB shutdown warnings and Compatibility-only optional-renderer warnings also appeared before these changes; they remain recorded without declaring them harmless.

The pre-edit full current-project+NPC backup succeeded378105KB; Godot asset-library backup9115KB. The final full backup is requested after the completed lease/history record; its tool response is the proof of upload. Blender kits are saved through the persistent library API and reopened. Temporary transfer assets/archives are removed after validation. No GitHub publication or room messages.

M0,M1,M2complete in their city scopes. NEXT M3: inventory lots/terrain/street work, then first sidewalk/curb module with compatible dimensions,editable source,collision and seam tests. Keep main-task ownership and protocol-v3 lease.
