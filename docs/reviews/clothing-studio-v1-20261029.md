# Clothing Studio v1 — 29 October 2026

Canonical project: `lifesim`, Godot 4.7.2. Main lease: `main-clothing-editor-1793273623-69443`.

## User workflow

Open **Dílna oblečení** from the HUD to design and save clothing. To equip it, open **Upravit postavu** or **Vytvořit vlastní postavu**, then **Dílna oblečení — vytvořit vlastní kus**. Choose a saved design or start from a template, edit it and click **Použít v návrhu postavy**. The normal parent editor's **Použít** remains the authoritative commit; Undo/Redo and Cancel remain available. The standalone workshop never modifies a live actor.

The workshop offers 51 actual C5 clothing bases: tops/dresses, bottoms and shoes. Controls modify supported template geometry (hem length, ease, separate sleeve length and cuff flare), main/accent colors, seven existing PBR textile sets or original fabric, solid/stripe/check/dot patterns, repeat density, roughness and optional hood/pocket/applique details. Shoe controls intentionally expose surface design rather than unsupported leg/sleeve geometry. Six presets provide starting examples. Rotation, garment close-up, two alternate fitting bodies and three arm poses operate only in the isolated preview.

Recipes can be saved in **Moje uložené návrhy**, reopened, and exported/imported as JSON text for copying. The device-local library holds up to 128 recipes in `user://garments/`; filenames are content hashes. Identical saves are deduplicated. Browser/device storage is local to the app environment; JSON is the portable transfer format.

## Implementation and compatibility

- New bounded `garment_design.gd` data model, validated independent of identity or mental state. No paths, URLs, shader code, scripts or executable mesh payloads are accepted. Formats and enum values are allowlisted, numeric limits and finite values enforced, and imported text capped at 4096 bytes.
- Character schema **v19**, chained after the recovered v18 hand-size migration. Each outfit can carry three portable `designs` entries. v18→v19 copies old data and inserts empty design maps, preserving appearance and existing private data.
- Strict server validation verifies each design matches its chosen top/bottom/shoe base. Public appearance carries only the bounded visual recipe. Existing authenticated owner Apply/readback, private/public separation and conflict/reconnect rules remain intact.
- C5 meshes are shared templates. Tailoring creates separate cached mesh variants, keeps all ten body morph targets and the original 17-bone skin binding convention, recalculates normals/tangents and retargets shortened sleeve/trouser influences to the appropriate original template region. Shortened sleeves pin the original 14 shoulder-rim vertices in the base and every body target; a measured initial 3.685 mm morph drift was removed. Geometry cache is bounded at 64 variants; unchanged ordinary outfits use the original path.
- Pattern/fabric materials are per actor. Actual original textile albedo/normal maps are reused. Logos and trim keep their distinct material palette; boot shafts remain structural.
- A custom dress's legacy bodice/skirt void is filled by a new fitted waist band derived from both actual template boundaries and all ten morphs.
- Shortened trousers reveal the existing skinned bare-leg meshes. Crop tops lazily instantiate the existing torso anatomy, but render only the lower skin surface with an actual hem-height fragment mask. The full chest/accessory meshes remain hidden. Skin, rig and body-morph updates propagate to this surface, including save/reload.
- Original LSX binaries, Blender authoring files, city-owned paths and private psyche schema were not changed. No GitHub publication or AI Room message was sent.

## Executed verification

| Suite | Result |
| --- | --- |
| New workshop data/UI/library/geometry matrix | **451/451**, 92 actual custom pieces |
| Real HUD/editor/creator → draft → authority → save/reload | **23/23** |
| Real skinned geometry, two body profiles and three poses | **98/98**, 72 combinations; shoulder pins checked across all ten targets |
| Extended real ENet owner/observer/private readback/reconnect | **80/80**, including custom recipe commit and public delivery |
| Existing character codec/data | 157/157 |
| Existing character editor | 68/68 |
| Existing appearance UI | 111/111 |
| Existing character network | 83/83 |
| Save/load | 46/46 |
| First playable scene and cold resume | 81/81 |
| C5 clothing / authored models | 16/16 and 14/14 |
| Entire wardrobe | 7319/7319, 172 original parts, 5712 combinations, zero collapsed triangles |
| Body morphs and rig | 62/62 |
| Existing sleeve extremes | 1012/1012, 440 observations, max 2.767 mm |
| Bundled source checker | 60/60; new scripts also executed directly |

Actual GL Compatibility/Mesa screenshots were captured and inspected at **1280×900** and **360×800**, including reachable Apply/Close buttons, native patterns/materials, six example garments, a shortened/loosened pink cat hoodie with bent elbows and the repaired dress waist. Files are under `previews/main-clothing-editor-1793273623-69443/`. These are native rendered game geometry, not image-generated mockups. Final graphical run had no shader or script errors.

During development a test-only parse error, a producer-side StringName key for `clothing.active`, preview animation reset order and the first torso custom-attribute format were corrected. An intermediate whole-torso mask protruded above the cropped hem; it was replaced by the per-garment rest-height shader mask. Own source snapshots are preserved with `.before` suffix and `.gdignore` so historical test drafts cannot be mistaken for current runnable scripts. Expected codec corrupt-input decompression diagnostics and inherited ObjectDB shutdown warnings remain.

## Scope

This is a functioning **template-based garment editor**, not arbitrary freeform mesh sculpting or a sewing-panel/cloth physics solver. Controls genuinely change supported geometry and materials. The sampled checks cover rig/morph integrity and representative poses; they do not certify zero body/garment penetration for every user combination or arbitrary animation. The web build is exported for the existing game URL; actual browser/device execution was not tested in this run.

Next optional development: panel-based freeform garment authoring and systematic collision/fit validation across longer animation sequences, while preserving the v19 portable recipe/authority contracts.
