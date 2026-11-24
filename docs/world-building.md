# World building: lot grid and buy mode

Status: **B1 done (20 Nov 2026)** – lot grid, buy/sell/move, household budget, save, multiplayer authority,
buy-mode UI. Build mode currently covers walls (B2, 22 Nov 2026); doors, windows, floors and rooms are not implemented yet.

## Overview

| Piece | File | Role |
|---|---|---|
| `LotGrid` | `scripts/world/lot_grid.gd` | Pure data. Single source of truth for purchased items, their placement and the household budget. All placement rules live here. |
| `BuyCatalog` | `scripts/world/buy_catalog.gd` | 22 items in 9 categories (sleep, seating, kitchen, bathroom, electronics, hobby, decor, lighting, garden), with price, footprint, quality, appeal and placement constraints. `validate()` checks consistency. |
| `LotFurnisher` | `scripts/world/lot_furnisher.gd` | Builds nodes for purchased items. Items with an action tag become `SmartObject`s that the AI and the player can use immediately; decor is a plain node. Uses a Blender model when the catalog names one and `AssetLibrary` is enabled, otherwise primitives per `style`. |
| `WorldBuilder.describe_lot()` | `scripts/world/world_builder.gd` | Describes the starter lot for the grid: bounds, walls (including cut-away walls), door corridors, built-in kitchen counter and dining table, path to the street, garden bed, tree trunks, the eight-suite annex (not buildable yet) and the default furniture with its access points. |
| Buy mode UI | `scripts/ui/buy_mode.gd` | Key **B**. Budget, categories, item list with price, quality stars and appeal, a ghost that snaps to the grid (green/red with the reason), **R / Shift+R** rotate, click to place, click an item to select it, **Del/X** sell, **M** move, **Esc** close. Offline, time pauses while the panel is open. |

## Grid and rules

- Cell size 0.25 m over the lot rectangle (starter lot −12…12 × −12…12.75 m → 96 × 99 cells).
- Layers: static (walls and the like), solid (default furniture = −1, purchased items = uid), clear (access zones),
  floor (rugs) and inside (house interior).
- Rotation in 90° steps; the front of an item is local +Z.
- A placement is valid when:
  - the whole footprint lies inside the lot and on no static cell;
  - a solid item overlaps no other solid item and no other item's access zone (you cannot block the fridge door);
  - each of its own access points (0.5 × 0.5 m zone) lies on the lot, is not static, is not covered by another
    item, and can be reached from the item without crossing a wall (a sofa facing a wall is rejected);
  - rugs only collide with rugs and static cells, so furniture can stand on them;
  - `indoor` items lie fully inside the house, `outdoor` items fully outside.
- At most 64 purchased items per lot (keeps saves and network snapshots bounded).

## Money

- Household budget in whole crowns (`int`), starting at 15 000 kr. It never goes below zero; there is no credit
  yet (loans, debt and enforcement are planned together with the economy, see `docs/economy.md`).
- Selling within 24 game hours refunds the full price (a mistaken purchase). Afterwards the resale value is 55 %,
  falling linearly to 30 % over 180 days. If the clock was rewound, the item is treated as old (no full refund).
- A ledger keeps the last 64 transactions (buy, sell, move, restore refund).
- The prices and quality values are game-balance numbers, not calibrated to a real market.

## Effects on the simulation

- **Quality** (0.6–1.3) multiplies the positive comfort, energy and fun gains of actions on that object
  (`SimAgent._object_quality`). A bazaar mattress (0.7) restores energy noticeably slower than a good double bed
  (1.25). Default furniture has quality 1.0, so existing behaviour is unchanged.
- **Appeal** (−3…6 per item) adds up around a position (full weight up to 2 m, fading to zero at 5 m, capped
  at ±10). Once per game hour, on the authority, a character in a pleasant spot (≥ 5) gets the moodlet
  "Hezky zařízený domov", one in a grim corner (≤ −4) gets "Ponurý, zanedbaný kout". Walls do not block appeal yet.
  With no purchased items nothing is evaluated, so older saves and tests stay bit-identical.
- Items in use (reserved by a character, or the target of a queued player command) cannot be sold or moved.

## Saving

- `GameSave` writes a `lot` section (items, budget, next uid, ledger; the runtime revision counter is not saved,
  so save → load → save is bit-identical).
- Validation happens before the household is discarded: the snapshot is type- and range-checked, and the expected
  smart-object list is computed from a dry-run restore (`LotGrid.plan_restore`).
- Items that no longer fit the current lot (for example a rebuilt house) are dropped and refunded, at most at the
  catalog price (an edited save cannot mint money).
- Saves without the section load as the default lot. Server world persistence (H4b) uses the same format.

## Multiplayer

- Only the authority (offline game, host or dedicated server) changes the lot. Clients send
  `_c2s_lot(kind, args)`; the server checks the sender (must be a player with a character – spectators cannot spend
  the household budget), a per-player rate limit (4 burst, 1 per second), the request shape and all value ranges
  (coordinates inside the grid), then calls the same `LotGrid` rules.
- After every change the server sends the public snapshot (items with price and purchase time, budget; no ledger,
  no player names) to all players; a newly joined player gets it right after the welcome.
- Clients sanitise the snapshot (types, ranges, catalog ids, positions inside the grid) and rebuild their nodes.
  Smart objects are ordered as default furniture followed by purchased items by ascending uid, so object indices in
  player commands match on server and clients.
- The budget is shared by the household. Personal wallets will come with the economy.

## Walls (B2, 22 Nov 2026)

Walls are part of `LotGrid` (save format v2). A wall is a segment along cell **edges**: its end points are
integer lattice points `0..gw × 0..gh` (0.25 m steps). Walls do not fill cells; collisions with items are
computed against the edge.

Rules (`check_wall`, reason codes in `REASON_TEXT`):

- axis-aligned, 0.5–20 m (2–80 cells) per segment, inside the lot, at most 128 walls per lot;
- no overlap, duplicate or crossing with another wall; corners and T-junctions are allowed
  (geometry is decided by `build_wall_validation.gd`, checked against each nearby wall);
- not through static surroundings (both neighbouring cells static: house walls, built-in counter,
  door corridors, the path to the street) → `blocked`;
- not through an item (default furniture, purchased items and rugs occupy both sides of the edge) → `overlap`;
- not across an item's access: neither the segment from the item centre to its use point nor the
  0.5 × 0.5 m access zone around the use point → `blocks_access`;
- **no sealing off:** a breadth-first search over cells starts at the lot boundary (the street side);
  door corridors and the path are walkable "keep-out" areas (not buildable, but walkable), and items you
  step into (shower, treadmill) are enterable. Every use point that was reachable before the wall must stay
  reachable → otherwise `seals_off`.

Items in turn must not straddle a wall (`blocked`) and their access must not pass through a wall
(`access_blocked`).

Money: 60 kr per 0.25 m (240 kr/m). Demolishing within 24 game hours refunds the full price (a mistake);
afterwards it refunds nothing – rubble has no resale value. A rewound clock counts as an old wall.

Saving: `walls` + `next_wid` in the lot section (v2). A v1 save loads as a lot without walls. On restore,
walls come first; a wall that no longer fits the environment is dropped and refunded at most at its list
price, then items that would straddle a kept wall are dropped and refunded (same cap as in B1). The
reachability check is skipped while restoring (walls were valid when built; it would slow loading).

Nodes: `main.gd` builds one `StaticBody3D` per wall (box collider on layer 1, plaster body with a darker
skirting board; the plaster gets subtle noise roughness/normal only in visual runs). Walls are 2.7 m high
and 0.12 m thick, extended by half the thickness so corners close. They are procedural on purpose (any
length); a Blender trim/material pass is planned with the B2 asset step.

UI: in the furnishing panel (B) press **T** or "Stavět zeď": drag along the grid (the longer direction wins),
release to build; the ghost shows length and price or the reason. Click a wall to select it, Delete demolishes it.

Multiplayer: `wall` / `unwall` go through the same `_c2s_lot` path as buy/sell (player with a character,
shared lot rate limit) plus a stricter wall bucket (2 requests, 0.5/s) because of the reachability search.
The public snapshot carries walls; clients re-validate types, bounds, lengths and geometry before rebuilding.

## Pathfinding around built walls (B3, 22 Nov 2026)

`scripts/world/lot_nav.gd` (`LotNav`) keeps the old movement unless a **player-built wall** crosses the straight
line from a character to its target (walls are inflated by `CLEAR` = 0.1 m for this test). Then:

1. Start and goal snap to the nearest walkable cell whose centre is visible from the point across walls
   (search radius 2 m; points outside the lot are projected onto the grid edge).
2. `LotPathfinder` finds the shortest 4-neighbour route on the same walk graph that the reachability check uses
   (walls block edges; house walls, counters and furniture block cells; door corridors and step-in items are
   walkable).
3. The route is smoothed forward: from an anchor the walker goes to the farthest cell centre it can see (no wall
   within `CLEAR`, every sample on a walkable cell). Each frame the farthest visible corner of the next six is used.
4. The route is cached per character and rebuilt only when the lot revision or the goal cell changes (a moving
   social target inside one cell does not replan). A character that ends up on a corner with nothing visible
   ahead replans once.

`SimAgent._walk` asks `LotNav` first and then applies the existing dining-table detour to the current leg. Modes:

- `direct` – unchanged straight walk;
- `route` – walk to the returned corner;
- `none` – the target is cut off by walls: the action is aborted, the character gets a short moodlet, says a line
  and does not pick that object again for 120 game minutes (`nav_blocked`, max 32 entries, not saved);
- `escape` – the character itself is enclosed with no connection to the street (old save or a bug): it may walk
  out through the wall once, with a "walled in" moodlet, so it can never soft-lock.

Rules added to the lot:

- **Buying or moving an item** runs `reach_check` on a copy of the lot after the normal placement check: a use point
  that was reachable from the street must stay reachable (`blocks_path`), and the new item's own use points must
  be reachable (`access_unreachable`). Rugs never block. The check runs only for the transaction, not for the
  ghost preview, so the preview can be green and the purchase still refused with a reason.
- **Building a wall** is refused with `traps_sim` when it would cut off a character that was reachable from the
  street (`LotGrid.wall_traps`, called by `main.lot_apply_action` with the positions of all characters).

Pathfinding runs only where characters are simulated (offline or on the server); clients see the result through
the replicated positions.

## Doors and windows (B4a, 23 Nov 2026)

An opening is an attribute of a built wall, not a separate wall piece: `{oid, wid, kind, at, built_at, paid}` in
`LotGrid.openings` (save format v3). `at` is the offset in 0.25 m cells from the wall's normalised start point.

| kind | width | price | passable | sill / head | appeal |
|---|---|---|---|---|---|
| `door` | 1.0 m | 420 | yes | 0 / 2.05 m | 0 |
| `window` | 1.0 m | 360 | no | 0.9 / 2.1 m | +1.5 |
| `window_wide` | 1.5 m | 540 | no | 0.6 / 2.2 m | +2.5 |

Rules (`check_opening`): the wall exists; at least one cell of solid wall at both ends (`opening_edge`) and between
two openings (`opening_overlap`); no other wall may end inside the opening, edges included (`opening_junction`), and a
new wall may not end inside an existing opening (`wall_at_opening`); a door needs two free cell rows on both sides —
no furniture and no static obstacle except walk-through corridors (`door_blocked`); at most 64 openings per lot.
Furniture may not later be placed in that door clearance (`blocks_door`); rugs may.

Doors are passable: their edges are left open when wall edges are stamped, so the reachability BFS, the cell
pathfinder and `LotNav` (which now works with the solid wall segments from `LotGrid.wall_segments`) all route through
them. Windows stay solid for walking. A room can therefore be closed completely as long as a door is fitted before the
last wall goes up. Removing a door is treated like building a wall: it is refused if it would cut a reachable access
point off from the street (`seals_off`, `LotGrid.door_close_seals`) or shut a character in (`door_traps`,
`LotGrid.opening_traps`, called by `main.lot_apply_action`). Demolishing a wall removes its openings. Refunds follow the
wall rule: full price within 24 game hours, nothing afterwards (and nothing when the clock was rewound).

Saving: v3 adds `next_oid` and `openings`; v2 saves load with no openings. On restore, openings are re-checked after
the walls and before the items: invalid openings are dropped and refunded at most at the list price, and an item
standing in a door's clearance is dropped rather than the door. The public snapshot carries `open` rows; clients
re-check types, wall membership, end clearance, spacing and junctions and reject the whole snapshot otherwise.

Visuals (`main._build_wall_with_openings`): a wall with openings is built from solid plaster pieces with skirting,
headers, sills, frames, a glass pane with a mullion, a window board and a door leaf on a hinge
(`scripts/world/lot_door.gd`) that swings open while a character is within 1.4 m. Collision covers the solid pieces,
headers, sills and whole windows; the door span has none. The frames and leaves are procedural primitives for now.

A bug found by the B4 tests was fixed at the same time: the reachability BFS used to seed every walkable border cell
as "connected to the street", so a room built against the lot edge could never be closed. Border cells are now seeded
only through a border edge that no wall blocks (`LotGrid._street_open`).

## Tests

- `tests/test_lot_nav.tscn` (85 checks): walking around a wall end (route length within 12 % of the ideal,
  0.1 m clearance, never crossing), furniture on the way, full barrier (`none`), walled-in character (`escape`),
  route cache and moving goals, determinism, performance (maze plan ≈ 26 ms, cached step ≈ 0.1 ms), purchase and
  move reachability, `wall_traps`, and a real `SimAgent` in the starter world.
- `tests/test_lot_doors.tscn` (147 checks): opening rules, navigation through doors (BFS edges, cell path, `LotNav`
  never crossing a solid segment, windows solid, closed rooms, door closing vs. `seals_off` and trapped characters,
  rooms against the lot edge), door clearance vs. items, wall demolition and refunds, save v3, v2 migration,
  16 malformed variants and restore drops, public snapshot fuzz, performance, world nodes and collision, the door leaf
  opening near a character, disk save/load, `door_traps` through the world, the Door/Window UI and real ENet authority.
- `tests/test_lot_walls.tscn` (128 checks): wall rules, items vs. walls, refunds, save v2 and v1 migration,
  snapshot fuzzing, performance, wall nodes on the starter lot, the wall tool UI and real ENet authority.

`tests/test_lot_buy.tscn` (111 checks): placement rules on the real starter lot, money and limits, resale, move,
appeal and moodlets, item quality during real sleep, performance (≈15 µs per placement check, ≈1 ms grid
rebuild), determinism, world integration, save round trip, old and corrupt saves, refund cap, 400-mutation snapshot
fuzz, forged network snapshots, real ENet server with two clients (authority, replication, late join, forged
requests, rate limit, index parity) and a headless buy-mode UI smoke test.

## Door locks (B4b, 24 November 2026)

Doors carry a lock (`LotGrid` format v4): `""` unlocked, `"*"` locked for everybody, or a character key (the
character's node name) – only that character can pass ("she locked herself in the bathroom"). Windows cannot be
locked. Locks cost nothing and are not written to the money ledger.

- **Per-character navigation.** `LotGrid.nav_viewer` selects whose point of view the door spans are computed from.
  `SimAgent._walk` sets it to its own key only for the duration of `LotNav.next_point` and resets it to `""`.
  For a character without the key, a locked door is a solid wall for the cell BFS, the pathfinder and the wall
  segments used for smoothing. Caches (wall segments, reachability) are keyed by a view key that collapses to the
  lock-free view whenever no lock applies to that character, so the common case shares one cache.
- **Building checks stay lock-free**, plus one extra check: building a wall or demolishing a door may not trap a
  character behind somebody else's lock (`traps_in_lock_views`, characters grouped by the set of locks that apply
  to them, one BFS pair per group).
- **Rules.** A lock may not trap a character without the key who can currently reach the street (`lock_traps`);
  locking for everybody may not cut off item use points (`lock_seals`). A personal lock *may* cut other people off
  from the bathroom or bedroom – that is the point (privacy, conflict). At most 16 locked doors per lot.
- **Consequences.** When a character cannot reach its target, `LotNav.lock_blocker` finds out whether a lock is the
  reason and whose. The character remembers the target as unreachable for two game hours (no endless banging),
  gets a mood penalty, records a "rejection" in social memory (interpreted through vigilance) and loses 2 points of
  relationship with the person who locked themselves in – at most once per 6 game hours per person. The person
  inside hears knocking if within 10 m. A character without a key who ends up inside a locked room (old save) uses
  the existing escape mode rather than being stuck.
- **Visuals.** `LotDoor` reads the lock from the lot on each poll: the leaf only opens for characters who may pass,
  and a small lamp by the handle shows the state (green unlocked, amber personal, red everybody).
- **UI.** In buy mode a selected door shows *Lock for me (L)*, *For everybody* (Shift+L) and *Unlock*.

AI characters do not lock doors on their own yet.

## Known limitations / next steps

- Purchased items use primitive geometry except the bed, sofa and fridge models; Blender assets for the other
  catalog styles are still to do (no render was made in this run).
- Floors, rooms, multiple storeys and buildable annex rooms.
- Walls do not shade appeal and windows add appeal regardless of daylight. The walk graph ends at the lot edge: a
  wall across the whole lot makes the other side unreachable instead of sending characters round by the street.
  Characters keep only 0.1 m from the wall axis, so a shoulder can visually touch a wall.
- Door frames, leaves and windows are procedural (Blender assets to do); AI does not lock doors by itself and there
  is no break-in or lock picking yet. Item placement
  treats a wall with a door as solid (a rug cannot run through a doorway). Floors/wallpapers and a cut-away camera.
- Credit, debt and personal wallets together with the economy; item wear, breakdowns and repairs.
