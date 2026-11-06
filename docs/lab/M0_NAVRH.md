# Social & Psychological Dynamics Laboratory – M0: inventura a návrh oddělení jádra
Claude, 6. 11. 2026. Vychází z GitHub main 7961f6e (clone), jen čtení; nic nebylo změněno ani smazáno.

## 1. Co už je čisté jádro (bez 3D a sítě)
28 modulů v scripts/sim + scripts/psyche je `RefCounted` bez uzlů (žádné get_node, rpc, Mesh, Audio):
needs, mood, mood_cycle, emotional_state (19 os), mental_state (stres/coping/autoregulace), depression, neuro_profile, social_memory, rel_ledger, worldview, inner_voice, personality_accents, ocd_loop, substances, eating_distress, psychosis_state, intimacy_state, vigilance, social_pressure, sensory_profile, rejection_response, traits, action_library, psyche_ext (koordinátor), household_dynamics, utility_planner, fccs_oracle, psyche/psyche_model.
Všechny mají to_dict/from_dict (základ pro snapshot, pokračování a export).

## 2. Kde je vazba na hru (jediné skutečné úzké hrdlo)
- scripts/sim/sim_agent.gd (2584 řádků, `extends Node3D`) míchá: (a) rozhodování a psychiku (jádro) a (b) pohyb, navigaci, pozici, cíle jako Node3D objekty, signály pro zvuk/HUD/vizuál.
- Autoloady: GameClock (čas; signal time_advanced, MAX_STEP 2 min), GameSettings (přepínače; sim_agent čte přes /root/), AudioManager (jen poslouchá signály sim_agentu – jádro na něm nezávisí).
- Slabé vazby uvnitř čistých modulů: household_dynamics preloaduje sim_agent (enum State, konstanty, volá sim.conversation); utility_planner má typ `Node3D` pro objekty/cíle; emotional_state a fccs_oracle zmiňují SimAgent jen v komentářích/klíčích.
- sim_visual, sim_puppet, sensitive_privacy_mask = vrstva zobrazení/sítě, do laboratoře nepatří.
- Signály sim_agentu (action_started/finished, conversation, social_event, panic_changed, crying_changed, memory_added, speech_started) jsou už teď přirozený proud událostí pro event log.

## 3. Už dnes fungující „headless runner"
Testy (např. test_household_determinism_split) spouštějí Main s net_config {mode: offline, visuals:false, hud:false, audio:false, camera:false}, posouvají GameClock.advance(2.0) a čtou stav; seed se nastavuje přes `sim.rng.seed` (každá postava má vlastní RandomNumberGenerator, žádné globální randf). 14 dní × 8 postav ≈ desítky sekund; 30 dní má z historie problémy s 120s limitem nástroje → experimenty musí být v samostatných procesech/shardech (vzor: test_extreme_fictional_household).
→ M1 nemusí začínat přepisem: nejrychlejší bezpečná cesta je tenký runner nad stávajícím Main (bez 3D), a teprve potom vytahovat jádro ze sim_agentu.

## 4. Navržená architektura (cílový stav)
A) core/ (čistý, bez Node): AgentCore (psychika + rozhodování + paměť), World-lite (potřeby prostředí jako data, ne Node3D), Clock (vlastní, ne autoload), Rng per agent.
B) Adaptér hry: SimAgent = tenká vrstva Node3D, která volá AgentCore a řeší jen pohyb/vizuál/sít. Hra se chová beze změny (regresní testy hlídají).
C) Scénář (JSON): agenti (profil, rysy, role), vztahy, prostředí (počet objektů, sociální podpora), intervence (den X, událost Y), parametry běhu (dny, seedy).
D) Runner: N seedů × podmínky, každý běh v samostatném procesu, výstup JSON/CSV; párování podmínek se stejným seedem.
E) Event log: jednotný řádek {t, agent, typ, příčina, velikost příspěvku}; zdroj = existující signály + denní snímky stavů (stres, valence/arousal, vztahy, izolace).
F) Analytika: agregace přes seedy (průměr, rozptyl, intervaly), CSV/JSON export; UI až později (M4).
G) Metodika: ke každému parametru předpoklad, rozsah, zdroj (empirický / herní balance / odhad), verze modelu.

## 5. Rizika
1. Dělení sim_agent.gd (2584 ř.) může rozbít přesný determinismus (pořadí RNG volání). Pravidlo: každý krok musí mít bitově shodný podpis stavu před/po (existující testy household_*: determinism_split, resume, matrix).
2. Část parametrů je herní balance (pravděpodobnost hádek, prahy stresu) – nepoužívat jako vědecké tvrzení; označit „game_balance" a udělat citlivostní analýzu.
3. Otevřený nález: test_worldview 41/42 (průměrná vyhraněnost 4,40→4,47) a seed13 outlier hádek (~5,8 %) – před experimenty vyřešit, ať nezkreslí srovnání.
4. Privátní data: export a dashboard jen pro fiktivní agenty; SH/suicidalita nikdy jako automatická akce; exporty bez citlivých polí podle sensitive_privacy_mask.
5. Souběh: main lock v3 a GPT automatizace zapisují do stejného stromu; M0–M1 dělat v odděleném adresáři (tools/lab/), nezasahovat do sim_agent.gd.
6. Limit 120 s na volání nástroje → shardy a agregace jako u extreme_household.

## 6. Sekvence malých ověřitelných kroků
M0 (hotovo tímto dokumentem): inventura a mapa vazeb.
M1a: tools/lab/run_scenario.gd – headless runner nad Main (offline, bez vizuálu), vstup JSON scénáře, výstup denní snímky. Test: stejný seed dvakrát = shodný hash; shodné s test_household_determinism_split.
M1b: scénář low/high social support pro 8 identických agentů (rozdíl jen v jedné proměnné – musí se nejdřív určit, která existující veličina „sociální podpora" je: pravděpodobnost/kvalita rozhovorů, počet přátel, social_pressure; definovat a zdokumentovat).
M2: event log + CSV/JSON (nad signály, bez zásahu do jádra).
M3: experimentální běžec: seedy × podmínky, procesy, agregace s rozptylem; negativní kontrola (obě podmínky identické → rozdíl ≈ 0).
M4: dashboard (HTML artefakt čtoucí exporty).
M5: revize konstruktů po jednom (psychometrika/literatura).
M6: skupiny a sítě.
Potom (ne dřív) postupně extrahovat AgentCore ze sim_agent.gd.

## 7. Co NEDĚLAT teď
Nemazat ani přesouvat hru; nepřepisovat sim_agent.gd; neprezentovat výsledky jako platné pro lidi; neprohlašovat herní parametry za kalibrované.
