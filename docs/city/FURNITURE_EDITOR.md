# Furniture authoring and M2 catalogue
29 October 2026. Godot project `lifesim`.

Open `res://scenes/city/furniture_editor.tscn` and press F6. The older M2 showcase and the new catalogue have launch buttons. The editor's **Katalog M2** button opens `res://scenes/city/m2_catalog_showcase.tscn`.

Choose one of 11 templates or create a blank design. Add boxes/cylinders, choose a part in the list, and edit its size, position, rotation, surface, RGB tint and collision flag. Units: meters and degrees. Cylinders support independently sized elliptical X/Z axes. Maximum64parts; sizes .001–8m; local positions -10..10m. The native scene tree and source catalogue remain editable separately in Godot/Blender.

The 29 material choices include11plain palette materials and18actually mapped PBR surfaces. The12new maps are white/sand/sage plaster,white brick,oak/dark wood,white/terracotta tile,grey stone,dark concrete,striped wallpaper and oak parquet. Each has256px repeating albedo,OpenGL+Ynormal,roughness. Six prior mapped surfaces remain available. Mapped custom geometry bakes meter UVs and tangents so GLB export retains texture scale; material resources are independent between parts.

Use **Duplikovat**, **Smazat díl**, **Zpět**, **Znovu**. Keyboard: Ctrl+S save,Ctrl+Z undo,Ctrl+Shift+Z/Ctrl+Y redo,Ctrl+D duplicate when focus is outside text input. Native text-field undo remains available. Typed names commit on Enter or focus loss. Navigation/opening another draft asks before discarding unsaved changes.

**Uložit JSON** stores a data-only draft under `user://furniture_editor/<sanitized-name>.json`. The status gives the exact path. The filename list and **Otevřít** load saved drafts. Successful overwrites retain one `.bak` predecessor; a malformed primary falls back to a validated backup. JSON accepts only bounded known fields, never scripts/resource paths. A failed save reports its error and leaves the good primary intact. Drafts are stored in Godot's per-user data directory; export/copy important user drafts when moving installations.

**Export scény** creates `.tscn` with local geometry/materials, conservative compound colliders and draft metadata. **Export GLB** creates geometry/materials for Blender; keep the JSON draft for continued composition and collision settings. Exports and saves are restricted to the furniture-editor directory. Empty designs can be saved but cannot be exported. A measured table example is retained as `docs/city/furniture_editor_example.{json,tscn,glb}` and in the Blender kit.

Custom drafts are **decorative objects**. Their edited geometry does not automatically inherit the fixed catalogue's measured interaction points. This prevents resizing a bench or moving a cabinet while leaving an actor inside it. Verified interactive furniture lives in the M2 catalogue; future custom interaction-point authoring and lot placement belong to the planned build-mode integration.

The catalogue contains15furniture/fixture assets plus3window and3door variants. **Použít dalším Simem** commands actual household agents through existing actions/reservations; repeat for multiple users. **Čas +5minut** steps simulation; **Dokončit akce** completes naturally through production ticks; **Zrušit akce** releases users. The clock is manually stepped in this isolated showcase. Door controls use the existing collision-aware hinge. Surface selection previews material changes; it does not alter saved catalogue sources. Rotate the camera to inspect the model.

All nine current starter furniture placements/actions have reusable equivalents. Counter,sink,toilet,bathtub,table and chair are authored equipment without new simulated actions. The catalogue leaves the main starter lot unchanged; lot replacement,navmesh,client replication and build-mode persistence remain M6/M7.

Blender: model library `lifesim-city-m2-complete-kit` v1.1, `m2_complete.blend` (16collections/134meshes, including one editor example). Only stove is initially visible to avoid overlapping all models; unhide a named collection in the Outliner. Its GLBs/manifests have exact source hashes. `lifesim-city-authoring-variants-v1` has the editable window/door source and54packed maps. Reproduction helpers: `tools/blender/city/import_m2_kit.py` and `authoring_variants.py`.
