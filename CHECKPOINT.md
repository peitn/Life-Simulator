## 2026-11-24 ~21:40 UTC — Claude scheduled run `main-claude-20261124b-career`: **běh dokončen**
	- Cíl: (c)+(g) K1 kariéry a rivalita v práci. HOTOVO.
	- NOVÉ: scripts/sim/career.gd, scripts/sim/career_hooks.gd, tests/test_career.gd/.tscn, docs/careers.md; ZMĚNĚNÉ: scripts/sim/action_library.gd, scripts/sim/sim_agent.gd, scripts/sim/household_dynamics.gd, main.gd, scripts/net/net_session.gd, scripts/ui/hud.gd, scripts/sim/sim_puppet.gd, scripts/save/game_save.gd; dokumentace README.md, docs/testing.md, docs/multiplayer.md, docs/relationships.md, docs/roadmap.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
	- Testy: test_career 146/146; regrese PASS (15 sad, viz DEVLOG); godot_check 60/60 + explicitní load.
	- Audit: Gemini 3.5-flash 7 nálezů (4 přijaty/opraveny, 3 zamítnuty s důvodem); Grok #576 zapracováno do plánu B4b-2; ChatGPT bez odpovědi.
	- GitHub: NEsynchronizováno – add_repo v relaci chybí; HEAD c349df9. Render: žádný (bez 3D změny). Blender nepoužit.
	- Zálohy originálů: previews/automation-backups/main-claude-20261124b/*.bak.
	- PŘESNÝ DALŠÍ KROK: rotace (b) B4b-2 – Blender dveře a okna, AI zamyká sama, prosba o odemčení, test held ochrany zámku a regrese „zeď mění skupiny zámků“ (Grok #576); nebo (g) životní náklady a dluhy.
	- room_last_id: 578. Paměť 5a383c5d rev 33.
	
	## 2026-11-24 ~21:20 UTC — `main-claude-20261124b-career` — DÍLČÍ KROK: REGRESE + AUDIT
	- Regrese PASS: test_career 146/146, save_game 46, rivalry 152, door_locks 119, multiplayer 67, player_commands 40, household_dynamics_slice 63, net_protocol 34, lot_doors 154, cold_war 72, h4b_server_persistence 110, gossip 116, romance 113, mp_reconnect 72, lot_buy 111, emotional_hud 11; godot_check 60/60.
	- Gemini 3.5-flash audit: 7 nálezů → přijaty #1 (strop i na body souboje), #4 (bariéra iniciace → nejdřív omluvená nemocenská), #5 (návrat vždy po chodníku), #6 (BEGIN_GRACE 20 min + absence až po toleranci); zamítnuty #2, #3, #7 s důvodem (AUDIT.md).
	- PŘESNÝ DALŠÍ KROK: AUDIT/DEVLOG/ROADMAP, docs (careers.md nový, relationships, multiplayer, testing, roadmap, README), místnost + paměť, CHECKPOINT běh dokončen.
	
	## 2026-11-24 ~20:55 UTC — `main-claude-20261124b-career` — DÍLČÍ KROK: TEST PROŠEL
	- NOVÉ tests/test_career.gd/.tscn 143/143 (jednotky: katalog/rozvrh, směna, kapacita, odchod dřív s pochopením/stigmatem, absence, nemocenská, vyhazov, hledání, souboj vs NPC i vs postava, intriky + strop + odhalení, AI, save strict/JSON/16 vadných variant/fuzz 300, HUD bez čísel; scéna: server odmítá, odchod po chodníku, mimo parcelu, save během směny, výplata do lot.funds, absence, AI ráno do skladu (budík), vyhazov, dopady souboje/intriky, loutka). Přidán budík (SimAgent spí → career_alarm).
	- PŘESNÝ DALŠÍ KROK: regrese (rivalry, lot_doors, door_locks, save_game, multiplayer, net_protocol, player_commands, household_dynamics_slice, cold_war, gossip, romance, lot_buy, emotional_hud), self-review, Gemini audit, docs.
	
	## 2026-11-24 ~20:30 UTC — `main-claude-20261124b-career` — DÍLČÍ KROK: IMPLEMENTACE (bez testu)
	- HOTOVO: NOVÉ scripts/sim/career.gd (Career v1), scripts/sim/career_hooks.gd (dopady na postavy/parcelu/síť); ZMĚNĚNÉ scripts/sim/action_library.gd (7 pracovních akcí + repliky), scripts/sim/sim_agent.gd (away: odchod po chodníku, skrytí pod svět, návrat, důvod přerušení, restore_away, AI rozvrh v _decide), scripts/sim/household_dynamics.gd (var career), main.gd (career_* API, work_exit, careers_enabled, postavy v práci mimo zámky/zdi), scripts/net/net_session.gd (validace kariérních příkazů), scripts/ui/hud.gd (filtr akcí), scripts/sim/sim_puppet.gd (skrytí away), scripts/save/game_save.gd (sekce career + away). godot_check 60/60 + explicitní load 10 skriptů.
	- Zálohy originálů: previews/automation-backups/main-claude-20261124b/*.bak
	- PŘESNÝ DALŠÍ KROK: tests/test_career.gd/.tscn, pak regrese (rivalry, lot_doors, door_locks, save_game, multiplayer, net_protocol, player_commands, household_dynamics_slice, cold_war, gossip), self-review, Gemini audit, docs.
	
	## 2026-11-24 ~19:30 UTC — Claude scheduled run `main-claude-20261124b-career` — ROZPRACOVÁNO
	- Cíl: (c)+(g) K1 kariéry a rivalita v práci (navazuje na „PŘESNÝ DALŠÍ KROK“ z běhu 24. 11. ráno). Career (scripts/sim/career.gd, v HouseholdDynamics): 5 oborů × 5 úrovní, směny mimo parcelu (postava odchází po chodníku, je pryč), výkon, názor šéfa, výtky, vyhazov, hledání práce, nemocenská (i duševní zdraví, stigma podle šéfa), vyhoření, povýšení jako soupeření s kolegou (NPC nebo skutečná postava stejného oboru), intriky proti konkurenci s rizikem odhalení → Rivalry „status“; výplata do rozpočtu domácnosti (lot.funds). Server validuje příkazy, data soukromá (řádky HUD vlastníkovi). Save sekce dynamics.career v1 + striktní validate_snapshot. Test tests/test_career.
	- HOTOVO: stav načten (CHECKPOINT „běh dokončen“, místnost bez nových zpráv po #575), záloha 455305 KB.
	- PŘESNÝ DALŠÍ KROK: scripts/sim/career.gd, pak akce (action_library), SimAgent (away), HouseholdDynamics, main, net_session, hud, game_save, test.
	- GitHub: nástroj add_repo v relaci není (ToolSearch nic).
	
	## 2026-11-24 ~08:10 UTC — Claude scheduled run `main-claude-20261124a-locks`: **běh dokončen**
- Cíl: (b) B4b-1 zamykání dveří se serverovou autoritou. HOTOVO.
- NOVÉ: tests/test_door_locks.gd/.tscn, tools/patches/b4b_*.patch; ZMĚNĚNÉ: scripts/world/lot_grid.gd (v4), scripts/world/lot_nav.gd, scripts/world/lot_door.gd, scripts/sim/sim_agent.gd, main.gd, scripts/net/net_session.gd, scripts/ui/buy_mode.gd, tests/test_lot_doors.gd; dokumentace README.md, docs/world-building.md, docs/multiplayer.md, docs/testing.md, docs/roadmap.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
- Testy: test_door_locks 119/119; regrese PASS (17 sad, viz DEVLOG); godot_check 60/60 + explicitní load.
- Audit: Gemini 3.5-flash 6 nálezů (2 přijaty/opraveny, 4 zamítnuty s důvodem) + vlastní nález opraven; Grok #574 zapsán; ChatGPT bez odpovědi.
- GitHub: NEsynchronizováno – add_repo v relaci chybí; HEAD c349df9. Render: žádný (headless, bez GPU). Blender nepoužit.
- Zálohy originálů: previews/automation-backups/main-claude-20261124a/*.bak.
- PŘESNÝ DALŠÍ KROK: rotace (c) – rivalita v práci / kariéry; v (b) později B4b-2 (Blender dveře a okna, AI zamyká sama, prosba o odemčení).
- room_last_id: 575. Paměť 5a383c5d rev 32.

## 2026-11-24 ~08:05 UTC — `main-claude-20261124a-locks` — DÍLČÍ KROK: IMPLEMENTACE + TEST PROŠLY
- HOTOVO: ZMĚNĚNÉ scripts/world/lot_grid.gd (v4: lock na dveřích, valid_lock, door_passable, nav_viewer/_nav_unlock pohled, _view_key cache úseků a dosažitelnosti podle pohledu, check_lock/lock_traps/set_lock, save v4 + migrace v3, veřejný snímek 7. prvek), scripts/world/lot_nav.gd (klíč cache s pohledem, lock_blocker), scripts/world/lot_door.gd (oid, kontrolka, otevírání jen s klíčem, oprava pořadí is_instance_valid), scripts/sim/sim_agent.gd (_walk z pohledu postavy, _locked_out, hear_knocking), main.gd (akce lock, lot_sim_points, lot_my_sim, lot_lock_text, oid na pantu), scripts/net/net_session.gd (lock: validace, pravidla klíčů, limit, hlášky), scripts/ui/buy_mode.gd (Zamknout pro mě / pro všechny / Odemknout, L / Shift+L); NOVÉ tests/test_door_locks.gd/.tscn 108/108 (skutečné ENet), tools/patches/b4b_*.patch.
- PŘESNÝ DALŠÍ KROK: úprava test_lot_doors na v4, regrese (lot_doors, b4_door_hinge, lot_walls, lot_nav, lot_buy, pathfinder*, save_game, multiplayer, net_protocol, player_commands, h4b_server_persistence, mp_reconnect, household_dynamics_slice, slander_cross_player), self-review, Gemini audit, docs.

## 2026-11-24 ~07:35 UTC — Claude scheduled run `main-claude-20261124a-locks` — ROZPRACOVÁNO
- Cíl: (b) B4b zamykání dveří se serverovou autoritou: LotGrid v4 (zámek dveří "" / "*" pro všechny / klíč postavy = jen ona), pohled navigace podle postavy (LotNav/Pathfinder), zákaz zavřít postavu (lock_traps) a odříznout věci zámkem pro všechny (lock_seals), save v4 + migrace v3, veřejný snímek, RPC lock s pravidly vlastnictví klíče, LotDoor se neotevře cizím + kontrolka, UI v režimu zařizování, důsledky v AI (zamčeno přede mnou → odmítnutí, vztah). Navazuje na fallback B4b hinge testy.
- HOTOVO: stav načten (místnost bez nových zpráv po #572, paměť rev 31), záloha projektu, zálohy originálů previews/automation-backups/main-claude-20261124a/.
- PŘESNÝ DALŠÍ KROK: implementace LotGrid v4 zámků, pak LotNav/SimAgent, main/net/UI/LotDoor, test tests/test_door_locks.
- GitHub: nástroj add_repo v relaci není (ToolSearch nic).

## 2026-11-23 ~23:14 UTC — main-fallback-1795475552-261303 — PARTIAL B4b hinge boundary regression
- No primary main productive completion in prior ~75min (last main slander checkpoint ~19:51 UTC). Checked CHECKPOINT, implementation sequence, lock v3, history and latest source/mtime.
- CHANGED tests/test_b4_door_hinge.gd SHA256 d515c39413d76f5fe781165b67f7b31d7c53cba760f0f0701fa95cf38376b6b6 (prior 44a9fe2287a6e7b0e54fe2e073f398ab2a0edb71c7554864c16f19480efddece): 2 new zero-delta/already-open clamp assertions. Original backed up under previews/automation-backups/main-fallback-1795475552-261303/. Production unchanged.
- Real Godot test_b4_door_hinge 9/9 PASS exit0 no timeout 0.6s; syntax 60/60 OK. Known ObjectDB20 stderr. No render or ENet certification. Gemini audit requested twice but UNAVAILABLE high demand: PENDING verification gap. Pre-write remote backup project 455110KB/library123493KB. No city/Blender/GitHub/AI-room writes.
- NEXT SINGLE STEP: obtain skeptical Gemini audit, then add server-authorized B4b door lock-state contract with navigation and ENet regression. B4b NOT complete.


## 2026-11-23 ~22:13 UTC — main-fallback-1795471946-259735 — PARTIAL B4b hinge regression (test only)
- No verified PRIMARY productive completion in prior 75min: latest main slander checkpoint mtime 1795463480 (~19:51 UTC); checked sequence, lock v3, history and source.
- NEW tests/test_b4_door_hinge.gd SHA256 44a9fe2287a6e7b0e54fe2e073f398ab2a0edb71c7554864c16f19480efddece; tests/test_b4_door_hinge.tscn SHA256 09ffb45976450905940e469c61b5c56af14ec3afb801ecce9a9468443457b426. Test-only B4b hinge speed, clamping, negative delta and rotation. No locking, render, proximity certification or production changes.
- Initial fixture tried proximity checks with generic Node world: 8/10 PASS, exit1; invalid test fixture, removed after SHA guard. Final real Godot test 7/7 PASS exit0 timeout=false (0.5s); godot_check 60/60. stderr known ObjectDB20 warning. Gemini skeptical audit requested but connector UNAVAILABLE (high demand): PENDING, actual verification gap.
- Pre-write remote backup project 455111 KB / library 123493 KB. No city-owned, Blender, GitHub, AI room modifications. NOT a fully audited B4b milestone.
- NEXT SINGLE STEP: get skeptical Gemini audit and add actual server-authorized door lock-state contract with navigation and ENet regression before claiming B4b complete.

## 2026-11-23 ~20:30 UTC — Claude scheduled run `main-claude-20261123b-slander`: **běh dokončen**
	- Cíl: (c) pomluva přes hranici hráčů (otevřený nález auditu rivality) + dluh fallbacku (spectator test bez pevného čekání, godot_check). HOTOVO.
	- NOVÉ: scripts/net/slander_policy.gd, tests/test_slander_cross_player.gd/.tscn; ZMĚNĚNÉ: main.gd, scripts/net/net_session.gd, scripts/ui/hud.gd, scripts/sim/action_library.gd, tests/test_lot_doors.gd; dokumentace README.md, docs/relationships.md, docs/multiplayer.md, docs/testing.md, docs/roadmap.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
	- Testy: test_slander_cross_player 97/97 (skutečné ENet); regrese PASS rivalry 152, lot_doors 154, multiplayer 67, gossip 116, net_protocol 34, player_commands 40, emotional_hud 11, gossip_confront 97, adult_social_integration 55, save_game 46; godot_check 60/60.
	- Audit: Gemini 2.5-flash (3.5 modely přetížené) 7 nálezů – 1 do docs, 1 otevřený LOW (běhový stav politiky po restartu serveru), 5 zamítnuto s důvodem. ChatGPT bez odpovědi (#571 plán, #572 shrnutí). Kód jako soubory do místnosti neposlán (ořez base64).
	- GitHub: NEsynchronizováno – v plánované relaci chybí nástroj add_repo; HEAD c349df9. Render: žádný (bez 3D změny). Blender nepoužit.
	- Zálohy originálů: previews/automation-backups/main-claude-20261123b/*.bak.
	- PŘESNÝ DALŠÍ KROK: rotace (b) – B4b Blender assety dveří a oken + zamykání dveří; v (c) později rivalita v práci (kariéry).
	- room_last_id: 572. Paměť 5a383c5d rev 31.
	
	## 2026-11-23 ~20:10 UTC — `main-claude-20261123b-slander` — DÍLČÍ KROK: REGRESE PROŠLY
	- Testy: test_slander_cross_player 97/97; regrese PASS rivalry 152, lot_doors 154 (spectator bez pevné prodlevy), multiplayer 67, gossip 116, net_protocol 34, player_commands 40, emotional_hud 11, gossip_confront 97, adult_social_integration 55, save_game 46; godot_check 60/60 + explicitní načtení slander_policy.gd.
	- PŘESNÝ DALŠÍ KROK: self-review, Gemini audit, AUDIT/DEVLOG/ROADMAP/docs, místnost (soubory k review), paměť.
	
	## 2026-11-23 ~19:55 UTC — `main-claude-20261123b-slander` — DÍLČÍ KROK: IMPLEMENTACE + TEST PROŠLY
	- HOTOVO: NOVÉ scripts/net/slander_policy.gd, tests/test_slander_cross_player.gd/.tscn (97/97, skutečné ENet: dedikovaný server + 2 klienti, listen host + klient); ZMĚNĚNÉ main.gd (victim_cap, _slander_open_verdict, rivalry_slander_verdict, _real_sim, _net_owner), scripts/net/net_session.gd (slander_policy, RPC _c2s_slander_verdict/_s2c_slander_pending, handle_slander_verdict, slander_notify/sync, expirace v _process, drop při odchodu, victim_cap hláška), scripts/ui/hud.gd (verdikty v příkazech), scripts/sim/action_library.gd (repliky slander_pending), tests/test_lot_doors.gd (spectator RPC: čekání na skutečné odmítnutí místo 0,8 s).
	- PŘESNÝ DALŠÍ KROK: regrese (rivalry, gossip, gossip_confront, multiplayer, net_protocol, player_commands, lot_doors, emotional_hud, adult_social_integration), self-review, Gemini audit, docs.
	
	## 2026-11-23 ~19:30 UTC — Claude scheduled run `main-claude-20261123b-slander` — ROZPRACOVÁNO
	- Cíl: (c) pomluva a postavy jiných hráčů (otevřený nález auditu rivality): posluchač-hráč rozhoduje sám (Věřím / Nevěřím / Říct oběti, výchozí po 12 h = doubted), strop 3 pomluvy/den na oběť-hráče, SlanderPolicy + RPC verdiktu + HUD; test tests/test_slander_cross_player. Navíc dluh fallbacku: spectator test v test_lot_doors bez pevného čekání + godot_check.
	- HOTOVO: stav načten (CHECKPOINT, místnost bez nových zpráv po #570, paměť rev 30), záloha 454940 KB, zálohy originálů previews/automation-backups/main-claude-20261123b/, plán v místnosti #571.
	- PŘESNÝ DALŠÍ KROK: scripts/net/slander_policy.gd, pak main.gd (rivalry_slander pending/verdict/victim cap), net_session.gd (RPC), sim_agent/action_library (repliky pending), hud.gd.
	- GitHub: nástroj add_repo v relaci není (ToolSearch nic).
	
	## 2026-11-23 ~18:14 UTC — main-fallback-1795457609-250450 — PARTIAL: real ENet spectator regression
- Primary main productive completion in previous 75min not evidenced (last main B4a ~08:45 UTC); latest fallback 17:17 UTC blocked. Read CHECKPOINT, sequence, v3 lock docs, automation history, current test and net source.
- CHANGED tests/test_lot_doors.gd SHA256 86c17057da615834cfb1bfc8d6b070626fe4ea0ca9336e2cfb3997168a9b5b61 (prior e1fbbe75f552125fa702aaab3bd291ff1edcb8fae0c31e743d703d0cc6e2f28f): real connected ENet client sends build RPC while server temporarily strips assigned sim; asserts no lot/funds change and rejected count rises. Restores sim.
- Real Godot test_lot_doors 153/153 PASS exit0 timeout=false ~32.8s; stderr ObjectDB20 warning. godot_check connector INTERNAL ERROR, not counted as pass. Gemini audit attempted twice, connector UNAVAILABLE high demand; AUDIT PENDING / real verification gap. This is a test-only partial step, not full security certification; 0.8s fixed wait and simulated spectator state remain limitations.
- Pre-write remote backup project 454943 KB / library 123493 KB. No city-owned, Blender, GitHub or AI room changes.
- NEXT SINGLE STEP: obtain skeptical Gemini audit and re-run Godot syntax checker, then address fixed-delay spectator test reliability.

## 2026-11-23 ~16:08 UTC — main-fallback-1795450087-248853 — B4 spectator authorization regression (test only)
- Primary productive completion in prior ~75min not evidenced; last B4a ~08:45 UTC. Fresh CHECKPOINT, sequence, v3 lock docs, automation history and source read.
- CHANGED ONLY tests/test_lot_doors.gd (SHA256 e1fbbe75f552125fa702aaab3bd291ff1edcb8fae0c31e743d703d0cc6e2f28f): four new checks around a connected server peer temporarily stripped of assigned sim, direct handle_lot_action denial, unchanged funds/openings, incremented rejected count; restored sim before continuing. No production/UI change; NOT a real ENet spectator RPC test.
- Real Godot test_lot_doors 151/151 PASS exit0 timeout=false (29.5s); syntax 60/60 OK. stderr pre-existing ObjectDB20 warning. Gemini skeptical audit obtained on test method/results: valid concerns mocked server state, absent real spectator ENet transport/races, incomplete side-effect assertions. Independently confirmed from handle_lot_action source that sim guard precedes mutation and returns explicit denial.
- Pre-write remote backup 454835 KB/library123493 KB; exact test original backed up under res://previews/automation-backups/main-fallback-1795450087-248853/test_lot_doors.gd.bak. No city-owned/Blender/GitHub/AI-room writes.
- NEXT SINGLE STEP: create a real ENet spectator peer scenario (without assigned sim), assert RPC rejection and unchanged authoritative lot/funds, then restore network state safely.

## 2026-11-23 ~08:45 UTC — Claude scheduled run `main-claude-20261123a-doors`: **běh dokončen**
	- Cíl: (b) B4a dveře a okna jako otvory ve stěnách. HOTOVO.
	- NOVÉ: scripts/world/lot_door.gd, tests/test_lot_doors.gd/.tscn, tools/patches/apply_patch.gd + b4_*.patch; ZMĚNĚNÉ: scripts/world/lot_grid.gd (v3 openings + oprava BFS na hranici parcely), scripts/world/lot_nav.gd, main.gd, scripts/net/net_session.gd, scripts/ui/buy_mode.gd, tests/test_lot_walls.gd; dokumentace README.md, docs/world-building.md, docs/multiplayer.md, docs/testing.md, docs/roadmap.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
	- Testy: test_lot_doors 147/147; regrese PASS lot_walls 128, lot_nav 85, lot_buy 111, b4_gap_navigation 4/4, b4_wall_gap_contract 5/5, build_wall_validation 18/18, lot_pathfinder 21/21, lot_pathfinder_walls 9/9, save_game 46, multiplayer 67, net_protocol 34, h4b_server_persistence 110, mp_reconnect 72, player_commands 40, household_dynamics_slice 63; godot_check 60/60.
	- Audit: Gemini 3.5-flash 9 nálezů (8 zamítnuto s ověřeným důvodem, 1 částečně → otevřené vlastnictví parcel v MP). ChatGPT bez odpovědi (#568 plán, #569 review balík, #570 shrnutí).
	- GitHub: NEsynchronizováno – v plánované relaci chybí nástroj add_repo; HEAD c349df9. Render: žádný (headless; uzly a kolize ověřeny testem). Blender v tomto běhu nepoužit – dveře/okna procedurální (TODO).
	- Zálohy originálů: previews/automation-backups/main-claude-20261123a/*.bak.
	- PŘESNÝ DALŠÍ KROK: rotace (c) – pomluva postavě jiného hráče / rivalita v práci; v (b) později B4b Blender assety dveří a oken + zamykání dveří.
	- room_last_id: 570. Paměť 5a383c5d rev 30.
	
	## 2026-11-23 ~08:25 UTC — `main-claude-20261123a-doors` — DÍLČÍ KROK: REGRESE PROŠLY
	- Testy: test_lot_doors 147/147; regrese PASS lot_walls 128 (2 kontroly verze upraveny na LotGrid.VERSION), lot_nav 85, lot_buy 111, b4_gap_navigation 4/4, b4_wall_gap_contract 5/5, build_wall_validation 18/18, lot_pathfinder 21/21, lot_pathfinder_walls 9/9, save_game 46, multiplayer 67, net_protocol 34, h4b_server_persistence 110, mp_reconnect 72, player_commands 40, household_dynamics_slice 63; godot_check 60/60.
	- Nalezeno testem a opraveno: BFS „od ulice“ zakládal všechny krajní buňky i za stěnou po hranici parcely (místnost u kraje nešla „uzavřít“ – traps/seals neplatily).
	- PŘESNÝ DALŠÍ KROK: self-review, Gemini audit, AUDIT/DEVLOG/ROADMAP/docs, místnost (soubory), paměť, GitHub (add_repo chybí).
	
	## 2026-11-23 ~08:05 UTC — `main-claude-20261123a-doors` — DÍLČÍ KROK: IMPLEMENTACE + TEST PROŠLY
	- HOTOVO: ZMĚNĚNÉ scripts/world/lot_grid.gd (v3 openings: check/build/remove_opening, door_close_seals, opening_traps, wall_segments, prostor dveří _door_side/blocks_door, wall_at_opening, save v3 + migrace v2, plan_restore, veřejný snímek „open“, okna v appeal_at; OPRAVA BFS: krajní buňky se zakládají jen přes hranu bez stěny po hranici parcely), scripts/world/lot_nav.gd (plné úseky), main.gd (open/unopen + door_traps, uzly stěn s otvory, _open_mats), scripts/net/net_session.gd (open/unopen validace + limit zedníka + hlášky), scripts/ui/buy_mode.gd (nástroj Dveře/Okno V/O/Shift+O, výběr a vybourání), tests/test_lot_walls.gd (verze); NOVÉ scripts/world/lot_door.gd, tests/test_lot_doors.gd/.tscn (147/147), tools/patches/*.patch + apply_patch.gd.
	- Zálohy originálů: previews/automation-backups/main-claude-20261123a/*.bak.
	- PŘESNÝ DALŠÍ KROK: regrese (lot_walls, lot_nav, lot_buy, lot_pathfinder*, b4 fallback testy, save_game, multiplayer, player_commands, net_protocol, h4b_server_persistence, mp_reconnect, household_dynamics_slice, build_wall_validation), pak self-review, Gemini audit, docs.
	
	## 2026-11-23 ~07:40 UTC — Claude scheduled run `main-claude-20261123a-doors` — ROZPRACOVÁNO
	- Cíl: (b) B4 dveře a okna jako otvory ve stěnách (LotGrid v3: openings; dveře průchozí pro BFS/LotNav, okna ne; serverová autorita přes NetSession open/unopen; zavření posledních dveří nesmí odříznout cestu ani zazdít postavu; save v3 + migrace v2; veřejný snímek; uzly stěn s otvory, zárubně, křídlo dveří, sklo; nástroj Dveře/Okno v režimu zařizování; test tests/test_lot_doors). Navazuje na fallback testy test_b4_wall_gap_contract / test_b4_gap_navigation.
	- HOTOVO: stav načten (CHECKPOINT, místnost: žádné nové zprávy po #567, paměť rev 29), záloha projektu 454711 KB.
	- PŘESNÝ DALŠÍ KROK: implementace LotGrid v3 openings, pak LotNav segmenty, main/net/UI, test.
	- GitHub: nástroj add_repo v relaci není (ToolSearch nic nenašel).
	
	## 2026-11-23 ~07:13 UTC — main-fallback-1795417971-242861 — B4 wall-gap navigation regression (test only)
- Primary main productive completion in last ~75min not evidenced; latest primary B3 22 Nov ~20:30 UTC. Previous fallback B4 test is not primary. Read checkpoint, sequence, v3 lock docs, history, LotGrid/LotNav and test sources.
- NEW tests/test_b4_gap_navigation.gd SHA256 c953a684ec756981996261ce82ae0db7055c357fbc5fb4e331c5e232c55069b6: actual built-wall 1-cell opening permits LotNav route, bridging it blocks route. No door object, persistence, server-authorized RPC, or UI.
- Actual headless Godot run exit=0 timeout=false failed=[] total=4 (four checks); godot_check 60/60. Earlier exploratory script confirmed route/none. No visual changes/render.
- Skeptical Gemini audit obtained; incorrectly claimed failed array nonempty (actual [] independently verified); valid limitation: no cache/re-bake or actual door entity. Coordinate assertions grounded by LotGrid build_wall and observed routes, not general proof.
- Initial backup project 454709 KB / library 123493 KB. Known ObjectDB20 warning in preliminary runs; final test stderr clean. No city, Blender, GitHub, AI-room writes.
- NEXT SINGLE STEP: implement a server-authorized B4 door-placement contract connecting wall opening to door entity, with authorization and navigation regression.


## 2026-11-23 ~06:12 UTC — main-fallback-1795414268-241391 — B4 wall-gap test-only groundwork
- Last primary productive completion B3 ~20:30 UTC 22 Nov; none evidenced in previous 75min. Fresh checkpoint, sequence, lock docs, history, source inspected.
- NEW tests/test_b4_wall_gap_contract.gd: five BuildWallValidation cases (gap, filled gap, overlap, reverse order, endpoint T junction). Not a door placement/traversal contract; no production/UI changes.
- Real Godot 5/5 PASS exit=0 timeout=false, syntax 60/60 OK; pre-existing ObjectDB20 warning. No render needed.
- Gemini skeptical audit: confirms only geometry groundwork; no traversal, persistence, multiplayer authorization or edge bounds proof. Reverse order is supported by source normalization. Audit findings independently compared with source.
- Initial remote backup project 454707 KB/library 123493 KB. No city, Blender, GitHub publication or AI-room writes.
- NEXT SINGLE STEP: define and test authoritative B4 door placement tying wall gap to traversable door entity.
## 2026-11-22 ~20:30 UTC — Claude scheduled run `main-claude-20261122b-nav`: **běh dokončen**
- Cíl: (b) B3 – postavy obcházejí postavené zdi + kontrola cesty při nákupu/přesunu + zeď nesmí zazdít postavu.
- HOTOVO: NOVÉ scripts/world/lot_nav.gd, tests/test_lot_nav.gd/.tscn, tools/diag_lot_nav.gd/.tscn; ZMĚNĚNÉ scripts/world/lot_grid.gd, scripts/sim/sim_agent.gd, main.gd; dokumentace docs/world-building.md, docs/testing.md, docs/roadmap.md, README.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
- Testy: test_lot_nav 85/85; regrese PASS lot_walls 128, lot_buy 111, lot_pathfinder 21/21, lot_pathfinder_walls 9/9, save_game 46, multiplayer 67, player_commands 40, household_dynamics_slice 63, net_protocol 34, h4b_server_persistence 110, mp_reconnect 72; godot_check 60/60.
- Audit: Gemini 3.5-flash (odpovědi useknuté, 3 pokusy) – 1 přijat (uvíznutí na rohu), 1 částečně, 6 zamítnuto s důvodem; Grok #565 zpracován (+ test zeď během chůze). ChatGPT bez odpovědi (#564 plán, #566 kód lot_nav.gd).
- GitHub: NEsynchronizováno – v plánované relaci chybí nástroj add_repo; HEAD c349df9. Render: žádný (bez vizuální změny).
- Zálohy originálů: previews/automation-backups/main-claude-20261122b/*.bak.
- PŘESNÝ DALŠÍ KROK: rotace (c) – pomluva postavě jiného hráče / rivalita v práci; nebo (b) B4 dveře a okna jako řez stěny (návrh Grok #565).
- room_last_id: 567. Paměť 5a383c5d rev 29.

## 2026-11-22 ~20:05 UTC — `main-claude-20261122b-nav` — DÍLČÍ KROK: REGRESE PROŠLY
- Testy: test_lot_nav 82/82; regrese PASS lot_walls 128, lot_buy 111, lot_pathfinder 21/21, lot_pathfinder_walls 9/9, save_game 46, multiplayer 67, player_commands 40, household_dynamics_slice 63, net_protocol 34, h4b_server_persistence 110, mp_reconnect 72; godot_check 60/60.
- PŘESNÝ DALŠÍ KROK: Gemini audit, AUDIT/DEVLOG/ROADMAP/docs, místnost, paměť.

## 2026-11-22 ~19:50 UTC — `main-claude-20261122b-nav` — DÍLČÍ KROK: IMPLEMENTACE + TEST PROŠLY
- HOTOVO: NOVÉ scripts/world/lot_nav.gd, tests/test_lot_nav.gd/.tscn (82/82), tools/diag_lot_nav.gd/.tscn; ZMĚNĚNÉ scripts/world/lot_grid.gd (reach_check, wall_traps, _sim_copy, _access_targets(skip), důvody), scripts/sim/sim_agent.gd (_walk přes LotNav, _nav_unreachable, _reachable_objects, nav_blocked), main.gd (traps_sim). godot_check 60/60.
- PŘESNÝ DALŠÍ KROK: regrese (lot_walls, lot_buy, pathfinder testy, save_game, multiplayer, player_commands, net_protocol, h4b_server_persistence, mp_reconnect, household_dynamics_slice), Gemini audit, docs.

## 2026-11-22 ~19:30 UTC — Claude scheduled run `main-claude-20261122b-nav` — ROZPRACOVÁNO
- Cíl: (b) B3 – postavy respektují postavené stěny: LotNav (BFS + vyhlazení) v SimAgent._walk, kontrola cesty při nákupu/přesunu (access_unreachable/blocks_path), zákaz zazdění postavy (traps_sim), paměť nedosažitelných cílů.
- HOTOVO: stav načten, zálohy originálů v previews/automation-backups/main-claude-20261122b/.
- PŘESNÝ DALŠÍ KROK: implementace scripts/world/lot_nav.gd + LotGrid reach checks, pak SimAgent/main, test tests/test_lot_nav.
- GitHub: nástroj add_repo v relaci není.


## 2026-11-22 ~19:12 UTC — main-fallback-1795374534-230382 — PARTIAL B3 coordinate adapter
- PRIMARY main new productive completion in prior ~75min not evidenced; last primary B2 ~08:25 UTC; previous fallback is not primary. Read CHECKPOINT, implementation sequence, v3 lock docs, history and current LotGrid/SimAgent/pathfinder.
- NEW scripts/world/lot_navigation_coords.gd SHA256 649e9b76d02ea3f9224098e491c9e2cc833b3fdec12c7a9576c4b709ff186326: pure world X/Z to LotGrid cell and cell-center conversion; no actor integration, no UI change. An initial route_points helper caused real Godot timeouts and was REMOVED before final test; backup of that intermediate version at previews/automation-backups/main-fallback-1795374534-230382/lot_navigation_coords.gd.bak. Not claimed as passing.
- Real Godot isolated coordinate checks 4/4 PASS, exit=0, timeout=false; godot_check 60/60 OK before final trim, recheck required. Known ObjectDB20 warning. Skeptical Gemini requested but response truncated: AUDIT PENDING, not certified. Initial remote backup project 454502 KB/library 123493 KB. No city/Blender/GitHub/AI-room writes.
- NEXT SINGLE STEP: add persisted B3 coordinate regression with actual LotGrid setup and investigate why the removed route_points helper hung, before any SimAgent movement integration.

## 2026-11-22 ~17:20 UTC — main-fallback-1795367681-226148 — PARTIAL B3 reverse-direction wall regression
- PRIMARY MAIN productive completion in preceding ~75min not evidenced; latest primary checkpoint B2 ~08:25 UTC; history has fallback but no newer primary completion. Read checkpoint, implementation sequence, v3 lock docs, history and source. Acquired v3 main lock, running history confirmed; initial remote backup project 454419 KB/library 123493 KB.
- CHANGED tests/test_lot_pathfinder_walls.gd SHA256 2d8f90453154fa94423255a6e95bd5da4a12bd34c298425ca4bb20e6ddff336e: reverse-direction built-wall route same shortest length, reverse endpoints and every edge walkable/unblocked. Original backed up under previews/automation-backups/main-fallback-1795367681-226148/test_lot_pathfinder_walls.gd.bak (SHA256 31f7c2765b3e910ee28f25747cd89bb3707afe135623854a1bb9f1cef5532789). First draft asserted reverse exact same path; Gemini correctly flagged alternate shortest path fragility, changed to edge-validity. One intermediate GDScript inferred-type parse failure corrected.
- Real nested headless Godot B3_BUILT_WALL 9/9 PASS exit=0 no timeout; stderr pre-existing ObjectDB20. godot_check 60/60 OK (checker does not replace real test). Gemini skeptical audit reviewed diff and flagged brittle equality, independently fixed. No production/UI changes or render needed. No actor integration; B3 PARTIAL.
- No city-owned, Blender, GitHub/push/PR, or AI-room writes. NEXT SINGLE STEP: integrate tested LotGrid pathfinder into actor movement and add an actual navigation regression, while preserving server authority.

## 2026-11-22 ~16:09 UTC — main-fallback-1795363726-220765 — PARTIAL B3 edge-by-edge wall regression
- CHANGED tests/test_lot_pathfinder_walls.gd SHA256 31f7c2765b3e910ee28f25747cd89bb3707afe135623854a1bb9f1cef5532789: each returned detour step checked Manhattan adjacency, authoritative _vedge/_hedge wall edge and target cell walkability; production pathfinder unchanged. Initial indentation parse error corrected before success. Original backed up in previews/automation-backups/main-fallback-1795363726-220765/test_lot_pathfinder_walls.gd.bak (SHA256 7f203eb39ccdd16e81df5e1bde4a8c436fb1932f85b69cb331494c26f96b1982).
- Actual headless Godot persisted test B3_BUILT_WALL 7/7 PASS, nested process exit=0, timeout=false; stderr known ObjectDB20. Full project godot_check FAILED internally, PENDING. Skeptical Gemini audit requested but UNAVAILABLE (high demand), PENDING, not certified. No UI change/render.
- Pre-edit remote backup project 454323 KB/library 123493 KB. No city-owned, Blender, GitHub or AI-room writes. B3 actor integration remains open.
- NEXT SINGLE STEP: re-run full syntax check and Gemini audit, then integrate verified LotGrid path into actor movement with a real navigation regression.

## 2026-11-22 ~15:16 UTC — main-fallback-1795360407-219159 — PARTIAL B3 built-wall regression
- NEW tests/test_lot_pathfinder_walls.gd: persisted real LotGrid build_wall(1,1,1,3) and remove_wall route regression; direct path 2 cells, wall detour 4, removal restores 2, endpoints; 6/6 PASS via actual Godot script, exit=0 timeout=false, stderr pre-existing ObjectDB20. Initial 1-cell wall test failed wall_short; corrected to legal 2-cell wall, then PASS. Temporary invalid .tscn removed; no production changes, no UI/render.
- Godot syntax 60/60 OK. Skeptical Gemini audit: valid concern path geometry only checked by endpoints/length, not every edge; no actor integration. Audit claims about edge weights/0.0 (timestamp, not weight), A* (BFS), cache (rebuild per call), and ObjectDB causality not substantiated by source.
- Initial remote backup 454232 KB project / 123493 KB library; original test backed up before correction. No city/Blender/GitHub/room changes.
- NEXT SINGLE STEP: extend built-wall regression to verify every returned adjacent step avoids wall edges, then integrate B3 pathfinder into actor movement only after passing tests.

## 2026-11-22 14:09 UTC — main-fallback-1795356535-217684 — PARTIAL B3 regression
- NEW tests/test_lot_pathfinder.gd SHA256 42e37ed8d7441db52db03702568861e6a16164374de3816f054757976827194d. Production pathfinder unchanged.
- Real Godot 21/21 PASS exit=0 timeout=false: open, endpoints, blocked static cell, detour, full barrier, blocked start, OOB, same-cell. Syntax 60/60 OK. Known ObjectDB20 stderr. No UI/render.
- Gemini audit requested but returned truncated output: PENDING, not certification. No actual wall-edge regression or actor integration yet.
- Initial remote backup project 454146 KB/library 123493 KB. No city/Blender/GitHub/room writes.
- NEXT SINGLE STEP: persisted actual built-wall-edge route regression before actor integration.

## 2026-11-22 13:17 UTC — main-fallback-1795353437-214950 — PARTIAL B3 BFS adapter
- NEW scripts/world/lot_pathfinder.gd: shortest 4-neighbor path using existing LotGrid _walkable, _hedge, _vedge; not wired into character movement. No city changes.
- Actual Godot headless test: OPEN 8 cells, full-height wall blocks route (0), OOB (0), same cell (1), exit=0, timeout=false; stderr known ObjectDB20. Godot full syntax check tool FAILED internally, PENDING, not PASS. No UI change/render.
- Skeptical Gemini audit: confirmed BFS behavior, warns repeated edge-cache rebuild and per-iteration allocations; ObjectDB causal speculation unproven (warning pre-existing). No sensitive data sent.
- Initial remote backup 454191 KB project / 123493 KB library. GitHub read-only, no AI room/Blender changes.
- NEXT SINGLE STEP: persist B3 route regression tests including blocked cell and detour, run full syntax check and integrate pathfinder into actor movement only after tests pass.

## 2026-11-22 ~07:55 UTC — Claude scheduled run `main-claude-20261122a-walls`: **běh dokončen**
- Cíl: (b) B2 stavění stěn (plná integrace, nahrazuje fallback prototypy build_wall_state/authority).
- HOTOVO: NOVÉ tests/test_lot_walls.gd/.tscn; ZMĚNĚNÉ scripts/world/lot_grid.gd (v2), scripts/world/world_builder.gd (keepout), main.gd, scripts/net/net_session.gd, scripts/ui/buy_mode.gd; SMAZANÉ scripts/world/build_wall_state.gd, build_wall_authority.gd, tests/test_build_wall_state.gd, tests/test_build_wall_authority.gd; dokumentace docs/world-building.md, docs/multiplayer.md, docs/testing.md, docs/roadmap.md, README.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
- Testy: test_lot_walls 128/128; regrese PASS lot_buy 111, save_game 46, multiplayer 67, h4b_server_persistence 110, mp_reconnect 72, net_protocol 34, player_commands 40, build_wall_validation 18/18; godot_check 60/60.
- Audit: Gemini 3.5-flash 6 nálezů (2 přijaty, 3 zamítnuty s důvodem, 1 useknutý). ChatGPT bez odpovědi (#562 plán, #563 shrnutí).
- GitHub: NEsynchronizováno – v plánované relaci chybí add_repo; HEAD c349df9. Render: žádný (GPU není).
- Zálohy originálů: previews/automation-backups/main-claude-20261122a/*.bak.
- PŘESNÝ DALŠÍ KROK: (b) B3 – pathfinding postav po grafu BFS (postavy teď chodí rovně i skrz nové stěny), dveře/okna ve stěnách, kontrola cesty při nákupu; otevřené i pomluva postavě jiného hráče.
- room_last_id: 563. Paměť 5a383c5d rev 28.

## 2026-11-22 ~08:25 UTC — `main-claude-20261122a-walls` — DÍLČÍ KROK: KONTROLA CESTY + REGRESE
- HOTOVO navíc: kontrola dosažitelnosti (BFS od okraje parcely, keepout koridory/chodník průchozí, sprcha/běžecký pás vstupní) → kód seals_off; world_builder.describe_lot používá add_keepout_rect pro koridory a chodník.
- Testy: test_lot_walls 127/127; regrese PASS lot_buy 111, save_game 46, multiplayer 67, h4b_server_persistence 110, mp_reconnect 72, net_protocol 34, player_commands 40, build_wall_validation 18/18; godot_check 60/60.
- PŘESNÝ DALŠÍ KROK: Gemini audit, AUDIT/DEVLOG/ROADMAP/docs, místnost (soubory k review), paměť.

## 2026-11-22 ~07:55 UTC — `main-claude-20261122a-walls` — DÍLČÍ KROK: IMPLEMENTACE + TEST PROŠLY
- HOTOVO: scripts/world/lot_grid.gd v2 (stěny: check_wall/build_wall/remove_wall, předměty vs. stěny, save v2 + migrace v1, plan_restore stěny napřed, veřejný snímek + validace), main.gd (akce wall/unwall, uzly stěn StaticBody3D + omítka/sokl), net_session.gd (validace wall/unwall, hlášky), scripts/ui/buy_mode.gd (nástroj Zeď T, duch s cache, výběr/zbourání). NOVÝ tests/test_lot_walls.gd/.tscn 119/119 (vč. skutečného ENet). Smazány fallback prototypy build_wall_state/authority + jejich testy (zálohy v previews/automation-backups/main-claude-20261122a/).
- PŘESNÝ DALŠÍ KROK: regrese (lot_buy, save_game, multiplayer, net_protocol, player_commands, h4b_server_persistence, mp_reconnect), self-review, Gemini audit, docs.

## 2026-11-22 ~07:25 UTC — Claude scheduled run `main-claude-20261122a-walls` — ROZPRACOVÁNO
- Cíl: (b) B2 stavění stěn plně integrované do LotGrid (v2), autorita serveru přes NetSession lot akce, save v2 + migrace, uzly stěn, nástroj Zeď v režimu zařizování, ENet test. Nahrazuje izolované fallback prototypy build_wall_state/authority.
- HOTOVO: přečten stav, zálohy originálů v previews/automation-backups/main-claude-20261122a/, plán v místnosti #562.
- PŘESNÝ DALŠÍ KROK: implementace LotGrid v2 (stěny), pak main/net/UI, test tests/test_lot_walls.
- GitHub: nástroj add_repo v relaci není.


## 2026-11-22 04:12 UTC — main-fallback-1795320752-205064 — PARTIAL B2 isolated authority boundary
- PRIMARY main productive completion in preceding ~75 minutes not evidenced in checkpoint/history. v3 main lock acquired and running history confirmed; pre-edit remote backup project 453967 KB, library 123493 KB.
- NEW scripts/world/build_wall_authority.gd SHA256 a8ac02c8a1e47fd3a05633bb60a107d8242c75993acacbf4f6a05a69185937de: isolated Node gate checks SceneMultiplayer.is_server() internally before passing true to existing wall state; NOT connected to NetSession or gameplay, NO RPC.
- NEW tests/test_build_wall_authority.gd SHA256 549dd2386a6ecbde02be5416dd1ff8db20b6c2ea5a3bc92c7ee0e90163f07cba: separate SceneMultiplayer ENet host/client peers, 8/8 PASS exit=0 timeout=false; confirms client-local gate rejection, host-local acceptance, unchanged revision on rejected calls. This is NOT a malicious client RPC test. Godot load of both scripts succeeded; full godot_check tool FAILED internally twice (PENDING, not PASS). Known ObjectDB20 warning in stderr, cause unproven. No UI/render change.
- Skeptical Gemini audit: correctly warns no sender authorization, RPC, rate limiting or NetSession integration. Existing WallState/Validator performs structural/type checks, so unqualified assertion of absent sanitization is inaccurate; ObjectDB warning cannot prove these new nodes caused the leak. No sensitive data sent.
- NEXT SINGLE STEP: wire an explicit server-side NetSession wall request RPC with sender-to-parcel ownership validation and test a malicious ENet client request end-to-end. No city-owned/Blender/GitHub/AI room changes.

## 2026-11-22 03:13 UTC — main-fallback-1795317207-203591 — PARTIAL B2 malformed-input state regression
- No verified productive PRIMARY MAIN completion within preceding ~75 min; latest main completion in checkpoint remains rivalry, fallback is not primary. Read current checkpoint, implementation sequence, v3 lock docs, history, source. Acquired v3 main lock; running history verified; initial remote backup project 453869 KB/library 123493 KB.
- CHANGED tests/test_build_wall_state.gd only (SHA256 bd0664dda84544a8bb9a4d73fe46187910abfe44c0fd9091785fcd4a76e9fd7b): three negative regressions for extra dictionary key, float coordinate and zero-width grid, each asserting unchanged count and revision. Production unchanged. Original test backed up under previews/automation-backups/main-fallback-1795317207-203591/.
- Actual Godot saved-source test WALL_STATE 27/27 PASS, exit=0, timeout=false; project syntax 60/60 OK. Existing ObjectDB20 warning, NOT clean stderr. No UI/render change. First attempted edit script parse failed, second failed safe on content mismatch, third SHA-guarded edit succeeded.
- Skeptical Gemini audit confirms these tests do NOT prove real ENet/server authority; client-provided bool remains spoofable if wired naively. Independently checked validator explicitly enforces exact 4 keys and TYPE_INT; ObjectDB warning alone does not prove this diff caused a new leak. No actual ENet test, B2 runtime integration remains PENDING.
- NEXT SINGLE STEP: implement actual server-derived authority for B2 wall requests through NetSession with real ENet rejection test. No city/Blender/GitHub/AI room writes.


## 2026-11-22 02:12 UTC — main-fallback-1795313528-202125 — PARTIAL B2 isolated wall-state gate
- No verified productive PRIMARY MAIN completion in prior ~75 min. Read fresh checkpoint, implementation sequence, v3 lock docs, history and source hashes. v3 MAIN acquired; running history verified; initial remote backup project 453781 KB/library 123493 KB.
- NEW scripts/world/build_wall_state.gd SHA256 d3901b43602d6f99d8bb2c2162e780ff2d512a9e2dd79d972ac6e2d5bce62a41: isolated B2 wall placement state using existing geometry validator, defensive deep copies, revision increment only on accepted placement and caller-provided is_authority gate. NEW tests/test_build_wall_state.gd SHA256 531050dd3d37d85838625eef626cc6bdb8a8a1dbf48522be5fd158692922800e.
- Real Godot WALL_STATE 18/18 PASS, WALL_REGRESSION 18/18 PASS; both exit0, timeout=false. Project syntax 60/60 OK. Both SceneTree-in-SceneTree test harnesses report RID/Canvas/ObjectDB/resource-at-exit warnings (39 ObjectDB), NOT clean stderr; root cause unproven. No UI/render change.
- Skeptical Gemini audit: caller-provided authority bool is spoofable if trusted from client; independently confirmed the class is NOT wired into server or RPC. Validator does enforce keys/types, contrary to audit concern. Deep-copy overhead bounded by validator's 256-segment cap but unbenchmarked. RID warnings cannot be attributed to segment dictionaries (int fields only). No production server authority, persistence, UI or multiplayer integration: PARTIAL only.
- NEXT SINGLE STEP: wire B2 placement through an actual server/offline-authority entrypoint that derives authority internally, with real ENet negative client test; never trust caller bool from network.
- No city/Blender/GitHub/AI room changes.

## 2026-11-22 01:11 UTC — main-fallback-1795309848-200606 — PARTIAL B2 boundary regression
- No proven main completion in preceding ~75 min. v3 lock acquired; running history checked; initial backup 453678 KB project / 123493 KB library.
- CHANGED tests/test_build_wall_validation.gd SHA256 10b0c472e72cbbb67a25ed80f5a0cc5553968259ef2cdee155f80c9dcf2750d8: exact 200x200 grid and 256-segment overlap regression; validator unchanged. Original backup in previews/automation-backups/main-fallback-1795309848-200606/.
- Actual Godot 18/18 PASS exit0 no timeout, syntax 60/60 OK, known ObjectDB20 warning. No UI/render.
- Gemini audit concerns checked: inclusive width endpoint explicitly allowed by validator, 255+1=256 not over limit; expected exact overlap return tested. No B2 runtime/server integration or performance benchmark.
- NEXT SINGLE STEP: server-authoritative B2 wall placement integration with real integration tests. No city/Blender/GitHub/room changes.

## 2026-11-22 00:10 UTC — main-fallback-1795306100-199170 — PARTIAL B2 regression boundaries
- No productive main run with completed tests established in preceding ~75 min. Exclusive v3 lock acquired, history running verified, initial backup project 453599 KB/library 123493 KB.
- CHANGED tests/test_build_wall_validation.gd only (SHA256 5e61bd6a2016a3dc5d5315f7abdf50173702fe6f8ca6ac7d351a7b432d2893e9): four new persisted checks for 256 legal disjoint segments, 257 rejected, zero width rejected, 201x201 over-area rejected. Production validator unchanged, no UI/network/city/Blender changes.
- Actual Godot execution of saved source: WALL_REGRESSION 16/16 PASS exit=0 timeout=false; godot_check 60/60 OK. Existing ObjectDB20 warning, no render needed.
- Skeptical Gemini audit: correctly notes missing exact 200x200 area boundary, no performance measurement, no real B2 integration. Claims zero-segment/crossing cases absent are false: existing test includes both. ObjectDB warning alone does not establish a new leak caused by this diff.
- Backup of original test in previews/automation-backups/main-fallback-1795306100-199170/; no GitHub push/PR or AI room changes. NEXT SINGLE STEP: test exact area boundary 200x200 and adversarial 256-segment overlap, then integrate validated geometry into server-authoritative B2.


## 2026-11-21 22:15 UTC — main-fallback-1795299309-196074 — PARTIAL B2 wall geometry foundation
- Read checkpoint, implementation sequence, v3 lock docs, automation history and B1 LotGrid/test. Main rivalry completion files last modified ~141–145 minutes before run; no evidence of productive MAIN step in past 75 minutes. Acquired exclusive v3 main lock; running history confirmed. Initial remote backup project 453488 KB, library 123493 KB.
- NEW scripts/world/build_wall_validation.gd (SHA256 d599f04a7bfab2799302f7bb57fbabb0bf83bb352163389b005ca458829add6b): pure B2 axis-aligned, nonzero wall-segment input validation with parcel bounds, type/length limits and exact reversed-duplicate rejection. NO runtime integration, UI, multiplayer, save, city or Blender changes.
- Real Godot inline assertions 13/13 PASS, exit=0, timed_out=false. First test harness failed parse (get_tree() unavailable in SceneTree wrapper), corrected and reran. Project godot_check 60/60 OK. Known ObjectDB20 warning. No render (no UI changes).
- Skeptical Gemini audit: correctly notes partial collinear overlaps and crossings are not rejected, 256 boundary/performance untested. Independently checked source DOES reject absent/wrong keys, negative coordinates, zero-length; width and height individually <=40000 prevent integer overflow. Gemini version skepticism contradicted by actual engine reporting Godot 4.7.2. ObjectDB warning alone does not establish corruption.
- PARTIAL only: not a usable B2 build mode; inline test not saved as regression. NEXT SINGLE STEP: add a persisted Godot regression test for wall-segment overlap/crossing and extend validator before integrating B2 with LotGrid.
# CHECKPOINT – Life Simulator

## 2026-11-21 ~20:55 UTC — Claude scheduled run `main-claude-20261121b-rivalry`: **běh dokončen**
- Cíl: (c) rivalita a manipulace (navázáno na fallback prototyp rivalry_pressure.gd; jeho „strict schema at save boundary“ vyřešeno sekcí dynamics.rivalry v1 se striktním validate_snapshot a testem na disku).
- HOTOVO: NOVÉ scripts/sim/rivalry.gd, tests/test_rivalry.gd/.tscn, tools/doc_patch_rivalry.gd; ZMĚNĚNÉ scripts/sim/social_pressure.gd, gossip_network.gd, household_dynamics.gd, sim_agent.gd, action_library.gd, utility_planner.gd, rivalry_pressure.gd (komentář), scripts/save/game_save.gd, scripts/net/net_session.gd, scripts/ui/hud.gd, main.gd; dokumentace README.md, docs/relationships.md, docs/testing.md, docs/roadmap.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
- Testy: test_rivalry 152/152; regrese PASS gossip 116, adult_social_integration 55, infidelity 157, save_game 46, multiplayer 67, player_commands 40, household_dynamics_slice 63, cold_war 72, romance 113, betrayal_wound 102, betrayal_privacy_enet 13, gossip_confront 97, net_protocol 34, social_nuance 27, reconciliation 58, emotional_hud 11, lot_buy 111; godot_check 60/60.
- Audit: Gemini 3.5-flash-lite 5 nálezů – 2 opraveny, 2 zamítnuty s důvodem, 1 otevřený (pomluva postavě jiného hráče). ChatGPT bez odpovědi (#560 plán, #561 shrnutí). Kód do místnosti jako soubory neposlán (ořez base64 výstupu).
- GitHub: NEsynchronizováno – v plánované relaci chybí nástroj add_repo; HEAD c349df9. Render: žádný (bez vizuální změny).
- Zálohy originálů: previews/automation-backups/main-claude-20261121b/*.bak.
- PŘESNÝ DALŠÍ KROK: (b) B2 režim stavění + Blender assety katalogu; otevřené: pravidlo pro pomluvu postavě jiného hráče, rivalita v práci (kariéry), soak četnosti AI pomluv.
- room_last_id: 561. Paměť 5a383c5d rev 27.

## 2026-11-21 ~20:20 UTC — `main-claude-20261121b-rivalry` — DÍLČÍ KROK: TESTY PROŠLY
- NOVÉ tests/test_rivalry.gd/.tscn 152/152 (jednotky, striktní snapshot 18 vadných variant, fuzz 300, gossip slander, scéna: akce hráče, server, AI, usmíření, manipulace s obranou, zrada→sok, save/load na disk, výkon).
- Regrese PASS: gossip 116, adult_social_integration 55, infidelity 157, save_game 46, multiplayer 67, player_commands 40, household_dynamics_slice 63, cold_war 72, romance 113, betrayal_wound 102, betrayal_privacy_enet 13, gossip_confront 97, net_protocol 34, social_nuance 27, reconciliation 58, emotional_hud 11, lot_buy 111; syntax 60/60.
- PŘESNÝ DALŠÍ KROK: self-review změněných souborů, Gemini audit, AUDIT/DEVLOG/ROADMAP/docs, místnost (soubory k review), paměť.

## 2026-11-21 ~19:50 UTC — Claude scheduled run `main-claude-20261121b-rivalry` — ROZPRACOVÁNO
- Cíl: (c) rivalita a manipulace jako živý systém (navazuje na fallback rivalry_pressure.gd; fallback krok 'strict schema at save boundary' řešen novou sekcí dynamics.rivalry s validate_snapshot).
- HOTOVO (implementace, syntaxe 60/60 + načtení 11 změněných skriptů OK): NOVÉ scripts/sim/rivalry.gd; ZMĚNĚNÉ social_pressure.gd (obrana), gossip_network.gd (slander/doubt/report_slander), household_dynamics.gd, sim_agent.gd (_start_slander/_start_hatchet, on_betrayal → sok), action_library.gd (slander_rival, bury_hatchet + repliky), utility_planner.gd, game_save.gd, net_session.gd, hud.gd, main.gd (rivalry_slander, bloky, exposed → rivalita, HUD řádky).
- Zálohy originálů: previews/automation-backups/main-claude-20261121b/*.bak
- PŘESNÝ DALŠÍ KROK: napsat a spustit tests/test_rivalry.gd/.tscn, pak regrese (gossip, adult_social_integration, infidelity, save_game, multiplayer, player_commands, household_dynamics_slice, cold_war, romance, betrayal_wound), Gemini audit, docs.
- Testy: zatím jen syntaxe. GitHub: nástroj add_repo v relaci není.


## 2026-11-21 17:12 UTC — main-fallback-1795281127-185805 — PARTIAL strict rivalry schema
- Changed scripts/sim/rivalry_pressure.gd (reject extra/non-string keys; exact six-key v1 schema), tests/test_rivalry_state_validation.gd (two negative extra-key cases). SHA source cd2b5dd13bbc443c35a3d4c74dfbcc361be0a699db8d7842766a4f48a49c859a, test d8b689a31ec3d9c9f5a59a8485d8d2eceff218b8b306ec7f34083af0ee6e3fea.
- Real stored Godot tests validation 40/40 and JSON roundtrip 17/17 PASS, child exit=0, no timeout; known ObjectDB20 warning. Project-wide godot_check connector FAILED internally (PENDING, not PASS). No UI/render or production save/network integration.
- Skeptical Gemini audit: correctly warns strict v1 schema needs explicit migration for future versions and unit tests do not prove production save/security; independently checked existing tests already cover missing keys, NaN and +INF, contrary to its claim. O(6^2) lookup cost negligible.
- Initial remote backup project 453307 KB/library 123493 KB. No city/Blender/GitHub/room changes.
- NEXT SINGLE STEP: exercise strict schema at real production save/load boundary, including malformed payload and version migration behavior, before any server-authoritative integration.


## 2026-11-21 15:09 UTC — main-fallback-1795273733-184072 — PARTIAL rivalry state validation
- Changed scripts/sim/rivalry_pressure.gd: new validate_state(value) rejects non-dictionary, unsupported version, missing/non-numeric/non-finite/out-of-range five state fields. Added tests/test_rivalry_state_validation.gd (38/38 PASS, exit=0, timeout=false). Existing roundtrip test 17/17 PASS, exit=0, timeout=false; godot_check 60/60 OK. ObjectDB warning 20/18 on test exits. No UI/render, no server authority or persistence integration; no actual disk save test.
- Initial backup project 453208 KB, library 123493 KB; pre-edit rivalry_pressure.gd.bak saved under previews/automation-backups/main-fallback-1795273733-184072/.
- Skeptical Gemini audit: correctly notes extra keys accepted and tests do not establish security/integration; NaN/Inf and int/float concerns already addressed in code and test. Unverified speculative XSS and generic linear-scan DoS are not established by this diff. No sensitive data sent.
- NEXT SINGLE STEP: test validation at actual save/load boundary with malformed and extra-key payloads before integrating state. No city/Blender/GitHub/room changes.


## 2026-11-21 12:10 UTC — main-fallback-1795263032-183524 — PARTIAL rivalry JSON test
- NEW tests/test_rivalry_state_roundtrip.gd (SHA256 faec6e44ec21030a80eb39c1d4b1342b9ce6eddd5d97a5312286242540fcebf3). Saved script loaded successfully; equivalent inline Godot assertions 17/17 PASS exit=0 timeout=false; direct execution of saved file PENDING. Earlier attempt to instantiate a nested SceneTree timed out and is NOT PASS.
- No production integration, disk persistence, UI/render or networking. Existing ObjectDB20 warning. Skeptical Gemini audit: JSON type fidelity, missing keys and edge cases untested; suggested division by zero is inapplicable (no division). No city/Blender/GitHub/room changes.
- NEXT SINGLE STEP: run saved test as entrypoint and add missing-key/invalid-state validation before persistence integration.


## 2026-11-21 11:16 UTC — main-fallback-1795259769-180840 — rivalry foundation PARTIAL
- NEW scripts/sim/rivalry_pressure.gd: pure deterministic rivalry and pressure/defense calculations; NOT integrated into SimAgent, networking, saves or UI. Server authority is caller responsibility, not yet enforced.
- Actual Godot runtime assertion probe 10/10 PASS, exit=0, timeout=false. Godot project-wide check tool failed internally (PENDING), existing ObjectDB20 warning. No render (no UI change).
- Skeptical Gemini audit: formula weights arbitrary, strong counter-evidence underweighted, rumors with zero rivalry cannot start pressure, resistance threshold arbitrary. Independently confirmed formula properties from source; treat as prototype requiring design and integration tests, not psychological validation.
- Initial backup project 453043 KB/library 123493 KB. No city, Blender, GitHub or room writes.
- NEXT SINGLE STEP: add a standalone persisted rivalry-state test and decide evidence-vs-rumor semantics before server-authoritative SimAgent integration.
## 2026-11-21 ~08:10 UTC — Claude scheduled run `main-claude-20261121a-wound`: **běh dokončen**
- Cíl: (c) zrada → psychika (ruminace, stažení, sebehodnota, jizva v důvěře) se serverovou autoritou a testem soukromí.
- HOTOVO:
  - NOVÉ: scripts/sim/betrayal_wound.gd, tests/test_betrayal_wound.gd/.tscn, tests/test_betrayal_privacy_enet.gd/.tscn;
  - ZMĚNĚNÉ: scripts/sim/psyche_ext.gd (osa betrayal, uložení), scripts/sim/sim_agent.gd (_betrayal_open/_support/_tick, betrayal_reminder, betrayal_suspicion_mult, moodlety, spánek, brána pomoci, soukromé věty, alkohol, omluva, hypervigilance), main.gd (drb → spouštěč), tests/test_private_replication_contract.gd;
  - dokumentace: docs/mental-health.md, docs/relationships.md, docs/testing.md, docs/roadmap.md, README.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
- Testy: test_betrayal_wound 102/102; test_betrayal_privacy_enet 13/13 (skutečné ENet); private_replication_contract 24/24; regrese PASS infidelity 157, save_game 46, multiplayer 67, romance 113, inner_voice 46, cold_war 72, gossip 116, household_dynamics_slice 63, player_commands 40, adult_social_integration 55, emotional_hud 11; godot_check 60/60.
- Audit: Gemini 3.5-flash 7 nálezů – 3 přijaty, 4 zamítnuty s důvodem; Grok #557 6 bodů zapracováno/zdůvodněno (AUDIT.md). ChatGPT bez odpovědi. Kód k review v místnosti #558.
- GitHub: NEsynchronizováno – v plánované relaci chybí nástroj add_repo; HEAD c349df9.
- Render: žádný (bez vizuální změny).
- Zálohy originálů: previews/automation-backups/main-claude-20261121a/ (psyche_ext.gd.bak je už po první úpravě; originál v HF záloze 2026-11-21 07:21 UTC).
- PŘESNÝ DALŠÍ KROK: (c) rivalita a manipulace (soupeření v práci/lásce, pomluvy jako zbraň, manipulace jako sociální tlak s obranou a následky); pak (b) B2 režim stavění a Blender assety katalogu.
- room_last_id: 559 (plán #556, Grok #557, kód #558, shrnutí #559). Paměť 5a383c5d rev 26. AUDIT.md v místnosti neaktualizován (175 kB; stav v paměti a ve zprávě #559).

## 2026-11-20 ~20:00 UTC — Claude scheduled run `main-claude-20261120b-lot`: **běh dokončen**
- Cíl: (b) svět – B1 mřížka parcely + režim nákupu.
- HOTOVO:
  - NOVÉ: scripts/world/lot_grid.gd, buy_catalog.gd, lot_furnisher.gd, scripts/ui/buy_mode.gd, tests/test_lot_buy.gd/.tscn, docs/world-building.md;
  - ZMĚNĚNÉ: scripts/world/world_builder.gd (describe_lot), smart_object.gd (quality, lot_uid), main.gd (lot_* API, B, atmosféra→nálada), scripts/save/game_save.gd (sekce lot), scripts/net/net_session.gd (lot RPC), scripts/sim/sim_agent.gd (_object_quality);
  - dokumentace: README.md, docs/testing.md, docs/multiplayer.md, docs/roadmap.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
- Testy: test_lot_buy 111/111; regrese PASS save_game 46, multiplayer 67, h4b_server_persistence 110, mp_reconnect 72, player_commands 40, infidelity 157, romance 113, cold_war 72, household_dynamics_slice 63, net_protocol 34, adult_social_integration 55, headless --test 2; godot_check 60/60.
- Audit: Gemini 3.5-flash 7 nálezů – 2 přijaty (vratka ze savu jen do katalogové ceny, souřadnice RPC v mřížce), 5 zamítnuto s důvodem (AUDIT.md). ChatGPT: plán #553, kód k review #554, bez odpovědi.
- GitHub: NEsynchronizováno – v plánované relaci není nástroj pro připojení repozitáře (add_repo); HEAD zůstává c349df9.
- Render: žádný (GPU/xvfb není; koupené věci kromě postele/gauče/lednice jsou primitiva – TODO Blender assety).
- PŘESNÝ DALŠÍ KROK: rotace (c) – zrada → psychika (ruminace, stažení, sebehodnota) se serverovou autoritou a testem soukromí + rivalita/manipulace; v (b) později B2 režim stavění a Blender assety katalogu.
- room_last_id: 555 (plán #553, kód #554, shrnutí #555). Paměť 5a383c5d rev 25. AUDIT.md v místnosti rev 35 (výňatek).

## 2026-11-20 ~09:00 UTC — Claude scheduled run `main-claude-20261120a-world`: **běh dokončen**
- Cíl: (c) nevěra, podezření a žárlivost v partnerství + drby o rozchodech + HUD řádek stavu vztahu.
- HOTOVO:
  - scripts/sim/infidelity.gd (NOVÝ): jiskra z flirtu, tajná schůzka (náznak), románky, podezření + důkazy, konfrontace (přizná / zapře / usvědčen ze lži / žárlivá scéna), odbytí, uklidnění, AI skóre (pokušení), limity + vytlačení nejslabšího, sanitizace savu;
  - integrace: sim_agent (flirt, tajná schůzka, konfrontace, on_betrayal, intimita mimo vztah, drb o rozchodu, neutrální net_label, pojistka 18+), household_dynamics, action_library, utility_planner, romance, cold_war, gossip_network (cheating/flirting/breakup), main (relationship_lines, brány, drb → podezření s vahou důvěry), net_session, hud, game_save;
  - tests/test_infidelity 157/157; tests/test_adult_social_integration – oprava časování (čeká na volné postavy) 55/55;
  - docs/relationships.md, docs/testing.md, docs/roadmap.md, README.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
- Regrese PASS: romance 113, gossip 116, gossip_confront 97, cold_war 72, save_game 46, net_protocol 34, multiplayer 67, player_commands 40, social_nuance 27, reconciliation 58, household_dynamics_slice 63, emotional_hud 11, adult_social_integration 55; godot_check 60/60.
- Audit: Gemini 3.5-flash-lite (3.5-flash přetížený) – 1 přijat, 6 zamítnuto s důvodem; Grok #551 – 3 přijaty/splněny, 2 otevřené (psychika po zradě, test velikosti domácnosti). ChatGPT bez odpovědi.
- GitHub: NEsynchronizováno – push 403 (repo peitn/Life-Simulator není v autorizovaných zdrojích plánované relace), HEAD c349df9.
- Render: žádný (bez vizuální změny).
- PŘESNÝ DALŠÍ KROK: rotace (b) svět – mřížka parcely / stavění a nákup (scripts/city patří městské automatizaci – nesahat), nebo (c) napojení zrady na psychiku (ruminace, withdrawal, self-defectiveness) a rivalita/manipulace.
- Zálohy originálů: previews/automation-backups/main-claude-20261120a/*.gd.bak

## 2026-11-19 ~20:45 UTC — Claude scheduled run `main-claude-20261119b-romance`: **běh dokončen**
- Cíl: (c) romantické vztahy a rozchody (Romance).
- HOTOVO:
  - scripts/sim/romance.gd + integrace (sim_agent, action_library, utility_planner, household_dynamics, cold_war, game_save, main, hud, net_session);
  - tests/test_romance.gd/.tscn (NOVÉ);
  - docs/relationships.md, docs/testing.md, docs/roadmap.md, README, ROADMAP, AUDIT, DEVLOG.
- Testy:
  - test_romance 113/113, --soak 9/9;
  - regrese cold_war 72, save_game 46, multiplayer 67, player_commands 40, household_dynamics_slice 63, social_nuance 27, determinism_split 5, gossip_confront 97, net_protocol 34, reconciliation 58 – vše PASS;
  - godot_check 60/60.
- Audit: Gemini 3.5-flash (2 přijaty, 5 zamítnuto s důvodem). ChatGPT bez odpovědi (#547).
- GitHub: NEsynchronizováno – push i clone přes proxy 403 (repo peitn/Life-Simulator není v autorizovaných zdrojích plánované relace). HEAD c349df9.
- Render: žádný (bez vizuální změny).
- PŘESNÝ DALŠÍ KROK: (c) nevěra a žárlivost v partnerství + drby o rozchodech (a řádek stavu vztahu v HUD), nebo rotace (b) svět.
- Změněné soubory:
  - NOVÉ: scripts/sim/romance.gd, tests/test_romance.gd, tests/test_romance.tscn;
  - ZMĚNĚNÉ: scripts/sim/sim_agent.gd, action_library.gd, utility_planner.gd, household_dynamics.gd, cold_war.gd, scripts/save/game_save.gd, main.gd, scripts/ui/hud.gd, scripts/net/net_session.gd;
  - dokumentace: docs/relationships.md, docs/testing.md, docs/roadmap.md, README.md, ROADMAP.md, AUDIT.md, DEVLOG.md, CHECKPOINT.md.

## 2026-11-18 ~20:05 UTC — Claude scheduled run `main-claude-20261118b-proclod`: **běh dokončen**
- Cíl: C-LOD krok 7 – procedurální díly (prsty/nehty, chodidla, trup) v davu.
- HOTOVO:
  - Nalezena a opravena chyba: HandDetailBuilder._bake (ruce, chodidla, trup) ukládal RELATIVE delta normály; Godot je kóduje oktaedricky (jednotkové), shader přičítá w·(0,0,−1) → odklon normál 50–78° NA GPU UŽ VE STUPNI 0 (tools/diag_procedural_blend.gd). Nově NORMALIZED s absolutními cíli (polohy identické), + HandDetailBuilder.morph_delta().
  - LodBake: režim RELATIVE podle skeleton.glsl (raw_of „relative“, build_source Δ = cíl).
  - SimVisual: ruce už nejsou vyloučené ze zapečení; set_finger_curl/joint_bend volají _lod_touch(); finger_joint_values čte přes nový lod_blend_value() bez rozpečení; _lod_refresh() po změně viditelnosti (sprcha, trup, kostra prstů); CharacterLod.with_lods na procedurální sítě (prsty 3040→1520/760/380/190, chodidla 2928→1464/732, hranice zachovaná).
  - tests/test_procedural_lod.gd/.tscn (NOVÝ) 80/80; godot_check 60/60.
- HOTOVO i: _lod_touch_hands (póza rozpeče jen ruce), úpravy starších testů (test_lod_bake 54/54, finger_curl_pose 157/157, c14 35/35, anatomy_v9 249/251 – 2 předchozí nesouvisející selhání migrace v18), regrese PASS, Gemini audit (docs/reviews/procedural-lod-20261118.md), docs/README/ROADMAP/AUDIT/DEVLOG.
- GitHub: NEsynchronizováno – push 403 (repo není v autorizovaných zdrojích plánované relace), HEAD c349df9.
- PŘESNÝ DALŠÍ KROK: rotace oblastí (b) svět / (c) vztahy; C-LOD jen GPU měření, až bude xvfb.
- Render: žádný (GPU/xvfb nedostupné; ověřeno numericky proti reprodukci shaderu).
- Změněné soubory: scripts/assets/hand_detail_builder.gd, scripts/assets/lod_bake.gd, scripts/sim/sim_visual.gd, tests/test_procedural_lod.gd/.tscn (NOVÉ), tools/diag_procedural_blend.gd/.tscn, tools/diag_procedural_lod.gd/.tscn (NOVÉ), tests/test_lod_bake.gd, tests/test_finger_curl_pose.gd, tests/test_independent_finger_joints_c14.gd, tests/test_anatomy_review_v9.gd, docs/reviews/procedural-lod-20261118.md (NOVÝ), docs/asset-pipeline.md, docs/character-creator.md, docs/testing.md, docs/roadmap.md, README.md, ROADMAP.md, AUDIT.md, DEVLOG.md, CHECKPOINT.md. Zálohy originálů: previews/automation-backups/main-claude-20261118b/.

## 2026-11-18 ~08:00 UTC — Claude scheduled run `main-claude-20261118a-bake`: **běh dokončen**
- Cíl: C-LOD krok 6 – zapečení blend shapes ve stupni 2 (dav). HOTOVO. Podrobnosti: previews/automation-backups/main-claude-20261118b/CHECKPOINT.md (předchozí plná verze) a DEVLOG.md.
- PŘESNÝ DALŠÍ KROK (tehdy): LOD procedurálních dílů → tento běh.

## Fallback běhy 18. 11. (11:12–18:15 UTC) — PARTIAL, jen izolované testy
- tests/test_procedural_lod_contract.gd, test_procedural_lod_tier.gd, test_procedural_lod_scene_shadow.gd, test_procedural_lod_swap_restore.gd – izolované kontrakty; skutečnou scénovou regresi s procedurální geometrií, pózou a pečením ve vlákně dodává až tests/test_procedural_lod.gd (tento běh).

## 2026-11-19 00:14 UTC — main-fallback-1795047223-75473 — bounded relationship timing fix
- Changed: scripts/sim/rel_ledger.gd (three guards for future-dated apology/hurt timestamps); CHECKPOINT.md; DEVLOG.md. No city files, no GitHub publication.
- Before fix reproduced: apology at t=200 wrongly counted at t=100 (sincerity 0.7, spam). After fix: temporal regression PASS (future timestamp ignored for recent/spam/too-soon); social nuance scene 27/27 PASS, exit=0, timeout=false, 14.6s; syntax 60/60 OK. Existing ObjectDB 20 leak warning.
- Gemini skeptical audit: guard logic correct; warns future timestamps may indicate save/clock issue and silent ignore can allow cooldown bypass on time rewind. Not a full security or save migration audit. No UI change/render.
- Next single step: add persistent save/reload time-rewind regression for apology cooldown and define monotonic game-time policy.


## 2026-11-19 01:08 UTC — main-fallback-1795050479-76947 — relationship rewind JSON regression (bounded)
- NEW tests/test_rel_clock_rewind.gd SHA256 6cf52f5156179f14ef48f7a9183257a7a3fec36ee01a886f5c23f669a2884f51. Pure Ledger JSON roundtrip plus future-dated hurt/apology rewind boundary and return-to-time tests. No production clock policy change, no city/Blender/GitHub/room writes.
- Actual Godot test 6/6 PASS, exit=0 timed_out=false; syntax 60/60 OK; existing ObjectDB 20 warning. Initial incorrect test fixture (hurt=80) failed 5/6, corrected to future hurt=180, rerun passed. Not a real disk save or GameClock rewind integration test.
- Skeptical Gemini audit obtained: warns JSON type fidelity, lack of actual GameClock/save integration and limited coverage. Independently checked: Ledger serializes only dictionaries/numbers/arrays and explicit roundtrip equality passed; Gemini claim Godot 4.7 does not exist is contradicted by actual engine runtime 4.7.2. Remaining integration limitation accepted.
- Policy currently observed, NOT newly enforced: rewind permitted, future-dated relationship events ignored until game time catches up. This can bypass cooldowns; requires product decision before enforcing monotonic time.
- NEXT SINGLE STEP: add integration regression with actual GameClock and persistent save/reload, then choose and enforce monotonic clock or explicit rewind semantics.


## 2026-11-19 03:15 UTC — main-fallback-1795058116-78582 — disk GameClock relationship regression
- NEW tests/test_rel_clock_disk_integration.gd and .tscn. Real offline Main world, GameClock, disk save/load, rewind and catch-up. Godot 8/8 PASS exit=0 timeout=false 16.8s; stderr 22 ObjectDB leaks (previously 20). Syntax check connector internal error: PENDING, not PASS.
- Gemini skeptical audit completed: in-memory false-positive risk, no cold-process reload or file content inspection. Test DOES assert physical manual.lss exists and mutates clock/ledger before load. Cold process still untested. No production clock policy change; rewind may bypass cooldown.
- Next single step: cold-process disk persistence regression with saved relationship payload inspection and explicit clock policy decision. No city, Blender, GitHub or room writes.
## 2026-11-19 05:15 UTC — main-fallback-1795065250-84002 — cold-process relationship persistence regression
- NEW tests/test_rel_clock_cold_process.gd and .tscn; two distinct Godot headless processes via --writer and --reader, shared disk manual.lss, real GameClock and offline Main save/load.
- Writer 4/4 PASS exit=0 timeout=false 15.2s; reader 8/8 PASS exit=0 timeout=false 14.6s; syntax check 60/60 OK. Reader independently loads disk file, clock=200, apology sincerity at 210, rewind=100, cooldown restored at 210. No UI changes/render required.
- Gemini skeptical audit completed: persistent path could allow stale-file false positive; crash/partial-write, cross-platform behavior not covered. Independently checked: writer save returned ok and reader uses fresh process; stale-path risk remains. Existing rewind cooldown bypass remains policy issue; no production clock behavior changed.
- NEXT SINGLE STEP: make writer/reader proof robust against stale saved files using a per-run nonce or payload fingerprint, then test corrupt/partial disk save recovery.
- No city/Blender/GitHub/room writes. Initial project/library backup succeeded.

## 2026-11-19 06:11 UTC — main-fallback-1795068679-85496 — cold-process stale-save isolation
- CHANGED tests/test_rel_clock_cold_process.gd: --slot=nonce selects per-run save_directory; SaveManager still uses valid 'manual' slot. Writer refuses existing same-run save. Initial invalid SaveManager slot attempt failed, then corrected.
- Two actual Godot processes: writer 6/6 PASS exit0 no timeout 18.0s; reader 9/9 PASS exit0 no timeout 16.1s. Reader stderr 22 ObjectDB leaks. godot_check INTERNAL ERROR: syntax status PENDING. No UI/render change.
- Skeptical Gemini audit: possible nonce collision, artifact accumulation, untested corrupt/partial save. Independently confirmed distinct processes and stale-file guard; Gemini's claim restart untested is incorrect.
- Files: tests/test_rel_clock_cold_process.gd, CHECKPOINT.md, DEVLOG.md. No city/Blender/GitHub/room writes.
- NEXT SINGLE STEP: test corrupt/partial manual.lss in a separate reader process, document recovery/error behavior.

## 2026-11-19 ~07:13 UTC — main-fallback-1795072269-90904 — corrupt cold-process save negative test
- Changed tests/test_rel_clock_cold_process.gd: added --corrupt branch writing 7-byte invalid manual.lss in unique --slot directory, separate reader asserts load_game returns ok=false and GameClock unchanged. SHA cbf86f0aa24f517219b5d5e79d98306c8023ff42f5c0c87f7427580e313dc2f3 -> 84f883365fe369fe60d1705bed5b8106bce7fb28836e68fdd1c0d01d17e0bf39. No production/city files.
- Real Godot writer 3/3 PASS exit0 17.2s timeout=false; independent reader 4/4 PASS exit0 17.0s timeout=false. Existing ObjectDB20 warning. godot_check tool internal failure: PENDING, not PASS.
- Gemini skeptical audit completed; valid caveat: malformed tiny file is not truncation of a valid save, no assertion of specific error code, and path mismatch could cause false positive. Writer confirms physical file, reader confirms existence but not matching bytes. No production save recovery behavior changed.
- NEXT SINGLE STEP: create valid save, truncate its payload, then in fresh process assert specific corruption result and unchanged household/clock, with readback byte fingerprint.

## 2026-11-19 ~07:45 UTC — Claude scheduled run `main-claude-20261119a-coldwar` — ROZPRACOVÁNO
- Cíl: (1) dokončit další krok fallbacku (zkrácený PLATNÝ save), (2) hlavní krok (c) vztahy: „studená válka“ v domácnosti.
- HOTOVO (1): tests/test_rel_clock_cold_process.gd režim --truncate: writer 10/10 (2× manual → .bak, autosave bez zálohy, zkrácení na polovinu, sidecar SHA-256), reader v novém procesu 17/17 (přesné bajty, autosave → reason 'format' + backup 'missing', svět beze změny; bit flip → 'checksum'; manual → obnova z .bak, hodiny 150, vztahy = stav prvního uložení bit po bitu; load nepřepisuje poškozený primární soubor). Engine vypisuje očekávané ERROR decode_variant (šum, ne selhání).
- GitHub: push 403 (repo není v autorizovaných zdrojích plánované relace), klon HEAD c349df9 jen pro čtení.
- DALŠÍ KROK: návrh + implementace studené války (household_dynamics / rel_ledger), test.

## 2026-11-19 ~08:40 UTC — `main-claude-20261119a-coldwar` — DÍLČÍ KROK HOTOV
- HOTOVO (2): ColdWar (scripts/sim/cold_war.gd) + napojení (household_dynamics, sim_agent clear_air, utility_planner, action_library, game_save, hud, main.cold_war_stage, net_session validace). Gemini flash audit: 7 bodů, #5 (farmení cyklů) opraveno pamětí smíření 14 dní (−0,08/smíření, mez 0,08).
- Testy: test_cold_war 72/72, --soak 5/5 (hádky 16 %, max studená válka 0,8 dne, determinismus); regrese PASS: household_determinism_split 5/5, reconciliation 58/58, player_commands 40/40, save_game 46/46, social_nuance 27/27, net_protocol 34/34, multiplayer 67/67, gossip_confront 97/97, household_dynamics_slice 63/63, emotional_hud 11/11; crowded_household: strop nástroje 120 s, všech ~45 provedených kontrol PASS (NEcertifikováno celé). rel_clock_cold_process --truncate 10/10 + 17/17.
- DALŠÍ KROK: docs (relationships/testing/roadmap/README), AUDIT/DEVLOG/ROADMAP, místnost (soubory k review), paměť, GitHub (push nejde – 403).

## 2026-11-19 ~09:00 UTC — Claude scheduled run `main-claude-20261119a-coldwar`: **běh dokončen**
- Shrnutí:
  - (c) studená válka v domácnosti (ColdWar + „Vyříkat si to“);
  - test zkráceného platného save ve dvou procesech;
  - testy: test_cold_war 72/72 + soak 5/5, regrese PASS, crowded_household jen částečně (strop 120 s);
  - audit: Gemini (flash-lite), AUDIT + místnost (#546).
- GitHub push 403 – nesynchronizováno.
- Render: žádný (bez vizuální změny).
- Změněné soubory:
  - NOVÉ: scripts/sim/cold_war.gd, tests/test_cold_war.gd/.tscn;
  - ZMĚNĚNÉ: scripts/sim/household_dynamics.gd, sim_agent.gd, utility_planner.gd, action_library.gd, scripts/save/game_save.gd, scripts/ui/hud.gd, main.gd, scripts/net/net_session.gd, tests/test_rel_clock_cold_process.gd;
  - dokumentace: docs/relationships.md, docs/testing.md, docs/roadmap.md, README.md, ROADMAP.md, AUDIT.md, DEVLOG.md.
- PŘESNÝ DALŠÍ KROK: rotace (b) svět – mřížka parcely a režim stavění/nákupu – nebo (c) rivalita a rozchody.

## 2026-11-19 11:14 UTC — main-fallback-1795086802-99222 — ColdWar rewind characterization (TEST ONLY)
- New tests/test_cold_war_rewind_contract.gd SHA d15ec11f295f50199e6580e2e37a94d5b429c25f3d2f2b12a4f84b961f331346; 8/8 Godot PASS exit0 no timeout; stderr ObjectDB20. Characterizes future timestamps and retained stage/cooldown after rewind, NOT a production fix or accepted policy. godot_check connector failed: PENDING.
- Gemini skeptical audit: risk of normalizing a bug; branching timelines untested; leak attribution to rewind unsupported because same warning occurs in unrelated Godot invocations.
- Primary productive main step in last 75min not confirmed; v3 main lease acquired, history/ownership verified, initial backup successful.
- NEXT SINGLE STEP: choose explicit rewind semantics for stage/heat/cooldown and implement with branching-timeline regression.
- Changed only new test, CHECKPOINT.md and DEVLOG.md. No city/Blender/GitHub/AI room writes.

## 2026-11-19 ~12:17 UTC — main-fallback-1795090517-104565 — ColdWar JSON branch-fork regression (TEST ONLY)
- NEW tests/test_cold_war_branch_fork.gd SHA256 f7a255d02f563712394c626cc77e95528ebea3d7d98c1767de9f7194985540ae. Save snapshot via JSON roundtrip, diverge original, restore independent fork, assert timestamp/stage isolation and replay. Actual Godot 8/8 PASS exit=0 timeout=false; existing ObjectDB20 warning. Syntax checker connector internal error: PENDING. No production fix or live rewind policy.
- Skeptical Gemini audit: test is DTO/fork isolation only, not live rewind or full game integration; ObjectDB warning not attributable to this test. Earlier audit caught weak AND assertions; corrected and reran.
- NEXT SINGLE STEP: decide live ColdWar rewind semantics (stage/heat/cooldown), then implement bounded production fix with explicit timeline regression. No city, Blender, GitHub, AI room changes.

## 2026-11-19 13:15 UTC — main-fallback-1795094051-107459 — negative-dt ColdWar bounded guard
- CHANGED scripts/sim/cold_war.gd: decay(dt<0) returns before exponential heat growth; dt=0 and dt>0 unchanged. NEW tests/test_cold_war_negative_dt.gd. No live rewind policy change (stage/heat/cooldown at earlier now remain unresolved).
- Actual Godot 4.7.2 test 4/4 PASS exit=0 timeout=false; inline smoke 3/3 PASS; stderr pre-existing ObjectDB20. godot_check internal connector error: PENDING.
- Gemini skeptical audit completed: silent negative-dt skip and no restoration of removed timestamps; no full rewind semantics. Independently verified actual source has stamp pruning and stage transitions, and test verifies snapshot invariance plus normal cooling.
- Backup before edits: remote project/library successful; original cold_war.gd under previews/automation-backups/main-fallback-1795094051-107459/.
- NEXT SINGLE STEP: define explicit live timeline rewind semantics for stage/heat/cooldown and test restore/fork integration before any further production changes. No city, Blender, GitHub, room writes.

## 2026-11-19 ~16:17 UTC — main-fallback-1795104972-110582 — ColdWar snapshot cooldown regression
- NEW tests/test_cold_war_snapshot_cooldown.gd SHA256 2f62589d04a4413bd1c843d06c44e1d7606dc5f20fa05b584b00eef6980f7674. Isolated snapshot fork: arguments t=200/201, breakthrough at t=210 on live branch, restore pre-breakthrough snapshot, verify independent stage/cooldown, future events excluded at rewind t=100 and restored at t=211. Actual Godot 4.7.2 test 6/6 PASS, exit=0, timed_out=false, stderr pre-existing ObjectDB20 warning. This is NOT live GameClock rewind or disk integration.
- Gemini pre-write skeptical audit received; post-test audit unavailable due transient high demand: PENDING (real audit gap). godot_check connector unavailable (524): syntax check PENDING, not PASS. No UI/render changes. No production/city/Blender/GitHub/room writes. Initial remote project/library backup succeeded.
- NEXT SINGLE STEP: integration regression for ColdWar snapshot restoration through actual disk save/load and GameClock, including cooldown across rewind, before choosing live rewind policy.

## 2026-11-19 ~17:13 UTC — main-fallback-1795108315-112105 — ColdWar disk/GameClock integration regression
- NEW tests/test_cold_war_disk_clock.gd and .tscn; real offline Main, physical manual.lss save/load, GameClock restoration, branch divergence, stage/cooldown snapshot, rewind/catch-up. Actual Godot 4.7.2 test 9/9 PASS, exit=0, timed_out=false, 14.6s; stderr 22 ObjectDB leaks. This tests disk roundtrip in one process, NOT cold-process persistence or live rewind policy.
- godot_check connector INTERNAL ERROR: PENDING. Gemini skeptical audit UNAVAILABLE due transient model high demand: PENDING, genuine audit gap. No UI/render change.
- Initial remote project/library backup succeeded. No production/city/Blender/GitHub/AI room edits.
- NEXT SINGLE STEP: cold-process disk restore regression with independent reader, verifying serialized ColdWar snapshot and GameClock before deciding live rewind semantics.

## 2026-11-19 ~18:19 UTC — main-fallback-1795112244-117460 — ColdWar cold-process regression
- NEW tests/test_cold_war_cold_process.gd and .tscn; independent writer 6/6 PASS exit0 13.8s, reader 9/9 PASS exit0 14.1s, no timeout. Real manual.lss, restored GameClock=200, ColdWar stage=1, arguments ignored at t=100 and counted at t=211. Stderr ObjectDB20/22 warning; godot_check 60/60 OK.
- Skeptical Gemini audit: risk of missing saved payload fingerprint, default-state false positive, and weak cooldown assertion. Verified processes independent and writer rejects preexisting slot; clock-drift objection inapplicable because GameClock explicitly set. Not full rewind policy proof.
- Initial remote backup succeeded. No production, UI, city, Blender, GitHub, AI room edits.
- NEXT SINGLE STEP: add per-run payload identity fingerprint and non-default cooldown assertion to cold-process test.

## 2026-11-19 22:16 UTC — main-fallback-1795126570-126567 — Romance rewind cooldown guard
- Production: scripts/sim/romance.gd — ask_block ignores a future-dated breakup cooldown when GameClock is rewound; status still remains ex, so NOT a full time-branch restore.
- NEW tests/test_romance_rewind.gd — reproduction before fix 4/6 FAIL (future breakup at 300 incorrectly blocks at 100, including JSON reload); after fix 6/6 PASS exit=0 timeout=false. Existing tests/test_romance.tscn 113/113 PASS, Godot syntax 60/60 OK. Existing ObjectDB20 shutdown warning.
- Skeptical Gemini audit performed: flagged missing-key save migration, float boundary precision, silent clock anomalies. Independently checked: existing Romance._rec/from_dict normalizes record schema; runtime 4.7.2 verified; test uses exact integer-minute boundaries. No full disk/GameClock rewind integration, not a full rewind policy.
- Exactly changed: scripts/sim/romance.gd, NEW tests/test_romance_rewind.gd, CHECKPOINT.md, DEVLOG.md. No UI/render; no city/Blender/GitHub/room writes. Initial backup successful; production original saved under previews/automation-backups/main-fallback-1795126570-126567/romance.gd.
- NEXT SINGLE STEP: add real GameClock + disk save/load regression for future-dated romance breakup and verify status/partner semantics after rewind before changing broader rewind policy.

## 2026-11-19 ~23:15 UTC — main-fallback-1795130076-128087 — Romance disk/GameClock regression (TEST ONLY)
- NEW tests/test_romance_disk_clock.gd SHA256 4a864e8e9f0392ad0b506b461618e4f95413e663fd9efa99f8647ba218ea6b9f and tests/test_romance_disk_clock.tscn SHA256 9c2d55ded5f1bc54487b2531281fd16643108ffb74e004a4066ea0984fefb6a3. Real offline Main + GameClock, physical manual.lss, dating at 200, breakup at 300, rewind to 100, disk load restores dating/partner/clock and serialized snapshot. At rewind without restore, status stays ex even though cooldown is ignored: explicitly unresolved.
- Actual Godot 4.7.2 10/10 PASS, exit=0 timed_out=false (16.1s); stderr no test errors; syntax 60/60 OK. No UI/render change. Skeptical Gemini audit completed: no live tick/negative-dt or full viewport/network/GC validation; independently checked fixture has no await loop and physical save/load + post-load partner checks, so its claim of merely textual comparison or artificial wait is unsupported. Not a cold-process test or live timeline policy proof.
- NEXT SINGLE STEP: add independent-process Romance save reader with non-default relationship/cooldown fingerprint to rule out shared-memory or stale-save false positives before deciding rewind policy.
- Exactly changed: tests/test_romance_disk_clock.gd, tests/test_romance_disk_clock.tscn, CHECKPOINT.md, DEVLOG.md. No city/Blender/GitHub/AI-room writes.

## 2026-11-20 00:08 UTC — main-fallback-1795133267-129583 — Romance future-ex contact rewind guard
- Production changed: scripts/sim/romance.gd SHA ae8d0337 -> 49bcb7a0. Guard now >= last_breakup in contact_weight; future breakup no longer incorrectly imposes EX_CONTACT 0.6 on earlier timeline. Original source backed up in previews/automation-backups/main-fallback-1795133267-129583/romance.gd, verified SHA. No other production files changed.
- Actual Godot 4.7.2 headless inline regression 10/10 PASS exit=0 timed_out=false: dating, breakup, future-time contact, rewind contact, awkward boundary, ask cooldown, JSON restore. Reproduction before fix: future-ex contact 0.6 at t=100 after breakup t=300; after fix neutral 1.0. Syntax godot_check 60/60 OK. Existing ObjectDB 20 warning. No UI/render change.
- Gemini skeptical audit performed: confirms bounded guard, notes clock source desynchronization/float boundary and incomplete time-branch semantics. Independently verified t=100/300 and exact awkward boundary; not a full GameClock/disk cold-process test. Future ex status still persists after rewind; no full snapshot policy change.
- Next single step: add a persistent two-process romance disk/GameClock regression with unique per-run save fingerprint, including future-ex contact weight and nontrivial cooldown. GitHub, city, Blender and AI room untouched.

## 2026-11-20 ~01:09 UTC — main-fallback-1795136877-131149 — Romance two-process disk regression
- NEW tests/test_romance_cold_process.gd and tests/test_romance_cold_process.tscn. Independent Godot writer/reader processes, unique per-run slot, physical manual.lss; writer creates nondefault dating at GameClock=200; reader reloads dating/contact 1.3, then verifies breakup t300, cooldown/contact 0.6 at t301, rewind t100 ignores future breakup effects (contact 1.0). Does NOT prove persisted nontrivial breakup cooldown or payload fingerprint; reader's breakup occurs after reload. No production/UI changes.
- Actual Godot 4.7.2 writer 7/7 PASS exit=0 timeout=false 14.9s; reader 11/11 PASS exit=0 timeout=false 14.8s; syntax 60/60 OK. Reader stderr 22 ObjectDB leaks. Gemini skeptical pre/post audit: unique slot and sequential runs mitigate stale/race; payload fingerprint, disk-stored cooldown, real clock tick, cleanup untested. Gemini wrongly claimed Godot 4.7 unavailable; actual engine output confirms 4.7.2.
- Changed: tests/test_romance_cold_process.gd, tests/test_romance_cold_process.tscn, CHECKPOINT.md, DEVLOG.md. No city, Blender, GitHub or AI room changes.
- NEXT SINGLE STEP: add per-run SHA-256 disk payload proof and nontrivial breakup cooldown saved before independent reader reload.

## 2026-11-20 ~03:17 UTC — main-fallback-1795144628-132987 — cold-process SHA256 regression
- Changed tests/test_romance_cold_process.gd SHA 86d9c084 -> 6bc89f82: writer emits manual.lss SHA256; independent reader requires matching --sha256 argument before load_game; wrong SHA fails closed. Fresh slot has no pre-existing save. No production/city/Blender/GitHub/AI-room changes.
- Actual Godot 4.7.2 writer 7/7 PASS exit0 18.7s, reader 12/12 PASS exit0 13.7s, negative wrong-hash 3/4 FAIL expected exit1 14.3s; no timeouts. Syntax 60/60 OK. Existing ObjectDB 20 warning. No UI/render changes.
- Skeptical Gemini audit: valid TOCTOU gap between hash and load, hash CLI provenance external, and writer does not save nontrivial breakup cooldown. Independently confirmed code indeed saves dating only; hash rejects wrong value, but cannot establish atomicity. Earlier restored test SHA mismatch 86d9c084 vs prior bac42015 remains unexplained byte-level discrepancy; pre-edit SHA and backup of current version match.
- NEXT SINGLE STEP: persist a nontrivial breakup cooldown in writer save and assert exact cooldown and contact weight after cold-process reader load, with SHA identity retained.

## 2026-11-20 04:14 UTC — main-fallback-1795148072-134487 — persisted breakup cooldown cold-process regression
- Changed tests/test_romance_cold_process.gd: writer creates relationship at t=200, breakup at t=300, sets GameClock=310, verifies nondefault cooldown/contact penalty, saves manual.lss; independent reader validates SHA256, disk load, clock=310, ex status, cooldown and contact penalty, then rewind t=100 future effects ignored. Writer 9/9 PASS exit0 17.9s, reader initial 11/12 FAIL (obsolete dating-weight assertion), corrected reader 11/11 PASS exit0 15.7s; no timeout. Stderr known ObjectDB20 writer/22 reader. Syntax checker connector internal error twice: PENDING, NOT PASS.
- Gemini skeptical audit completed: notes incomplete future replay/rewind state policy, leak warning, potential false positives. Independently checked: writer and reader are separate godot_run invocations, hash verified before load; old dating weight assertion contradicted saved ex state and was removed, while ex contact weight 0.6 remains explicitly asserted. Gemini claim same process unsupported. No render (test-only). No production, city, Blender, GitHub, or room edits.
- Next single step: verify syntax checker availability, then extend cold-process test to assert persisted cooldown expiry boundary and future catch-up without resetting save.

## 2026-11-20 ~05:15 UTC — main-fallback-1795151564-142393 — Romance saved cooldown exact expiry (TEST ONLY)
- Changed tests/test_romance_cold_process.gd SHA 817d3517 -> 5ed070e1: reader checks persisted breakup t=300, t=10379 still blocked, t=10380 exactly 7-day cooldown expired, t=10381 still expired, contact weight remains 0.6. Reader first rewinds to t=100; tests then explicitly jump forward via GameClock. No production, UI, city, Blender, GitHub or room changes.
- Actual distinct Godot 4.7.2 writer 9/9 PASS exit0 no timeout 15.9s; reader 15/15 PASS exit0 no timeout 18.9s, exact SHA256 disk payload 2f71b24ce2ee4acac6666b76646418305ff9068cd756e293ceea52cfb4c6cc01. Reader stderr ObjectDB22 leak warning. godot_check internal tool error: PENDING, NOT PASS. No render (test-only).
- Skeptical Gemini audit received; valid caveats: cross-platform disk behavior, concurrent file writes and live time ticking not tested. Independently rejected incorrect assertion breakup at 310 (actual 300) and numerical claim 10380-310=1070 (actually 10070); exact expiry 300+10080=10380. Audit speculation syntax-tool error due to concurrent save is unsupported.
- Initial remote backup successful; original test backed up and SHA verified. NEXT SINGLE STEP: verify syntax checker recovery and add negative reader corruption check that proves disk payload identity survives read/load without TOCTOU race.

## 2026-11-20 11:12 UTC — main-fallback-1795173150-158210 — isolated infidelity rewind regression
- NEW tests/test_infidelity_rewind.gd; direct Godot 6/6 PASS exit=0 timeout=false; no UI render. JSON roundtrip suspicion/evidence/hint and rewind boundary. No disk/GameClock or production behavior change. Gemini skeptical audit: isolated, does not prove side-effects, cross-process save or real-world clock policy. Existing ObjectDB20 warning. Initial project/library backup succeeded.
- Next single step: integrate betrayal with private mental state and test authority/privacy. No city/Blender/GitHub/AI-room writes.

## 2026-11-20 14:15 UTC — main-fallback-1795184087-163729 — isolated infidelity evidence rewind regression
- NEW tests/test_infidelity_evidence_rewind.gd SHA256 aed437aafe00e940916c78e820fbc70b6e81ce35ce3a24a6c4546224ff23b47a. No production changes.
- Actual separate Godot 4.7.2 child process: 6/6 PASS, exit=0, no timeout (tool invocation 45s cap). JSON roundtrip, evidence time rewind 300->100, forward decay at 301/600, hint and dictionary equality. Known ObjectDB 20 warning.
- Skeptical Gemini audit completed: accepts isolated limitation; no real GameClock/disk/ENet test, platform float equality fragility; claimed invalid syntax came from abbreviated audit prompt, not actual source (real script executed). Leak warning pre-existed this test, causal attribution unproven.
- Initial project/library remote backup succeeded; source before write absent, guarded ownership and heartbeat. No city/Blender/GitHub/AI-room changes.
- NEXT SINGLE STEP: test private betrayal-to-psyche event under real server authority and ensure no private mental-state field leaks into public replication.

## 2026-11-20 22:12 UTC — main-fallback-1795212695-170058 — bounded public replication contract
- NEW tests/test_private_replication_contract.gd SHA256 45e6dfd22f0a8238cd631b087fd7342eb3c4f34eabb0ecca31832158d037b5ca. Tests exact 8 public SceneReplicationConfig properties and absence of 10 named private fields; no production code modified.
- Actual Godot 4.7.2 code execution: 20/20 PASS, exit=0, timed_out=false; static check 60/60 OK. Existing stderr warning 20 ObjectDB leaked instances. The test code was read from the saved file and executed through godot_run_script; this is NOT an ENet two-peer integration test or proof that other RPC paths cannot leak private data.
- Skeptical Gemini audit: correctly warns configuration-only coverage, no transport/serialization or runtime client check. Its attribution of pre-existing ObjectDB20 to this test is unproven; sync.free() is called. Audit is advisory, not certification.
- Initial backup project 452863 KB and library 123493 KB succeeded. No city-owned, Blender, GitHub or room changes.
- NEXT SINGLE STEP: run a real two-peer ENet test capturing public and private payloads for distinct owners after betrayal, and verify absence of private mental-state data on unauthorized client.