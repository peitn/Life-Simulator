# H3 — dokončení a přerušení idle→walk (29. 10. 2026)

Run: `main-fallback-1793297564-86223`. Zdrojem pravdy je Godot projekt `lifesim`; žádný GitHub push, Blender, city-owned soubor ani AI místnost.

## Rozhodnutí watchdogu a bezpečnost
Čtení CHECKPOINT.md, DEVLOG.md, docs/implementation-sequence.md, docs/automation-lock.md včetně v3 dodatku, seznamu historie a posledních testů. Poslední ověřené dokončení **primární** hlavní úlohy: `main-clothing-editor-1793273623-69443`, 12:16 UTC, tedy >75 minut před kontrolou v 18:12 UTC. Fallback z 17:17 UTC je jiná úloha, ne primární. Atomický G.inspect v 18:12:34 UTC: locked=false, other_godot_processes=[]. Zámek MAIN získán 18:12:44 UTC, historie running ověřena. Počáteční skutečná záloha Godot 377197 KB a knihovna 9115 KB. Před každou mutací G.owns + G.heartbeat a aktuální SHA, soubory zálohovány; nic city-owned.

## Přesné změny
Nový pouze testovací `tests/test_h3_blend_completion_interrupt.gd` (finální SHA256 `51d47c3427572ca79053a4d5a0ba13e2f5e9f7205a883cb8812ef42bf5115dc2`). Tři meziverze uloženy jako `.bak` vedle testu; žádný produkční kód. Test používá dva nezávislé SimVisual modely (preview a live), dvě ruce, reálné `process_frame` hodiny s `Engine.time_scale=0.15`, dočasně vypnutý pouze automatický selector idle/walk, a třetí model jako čistý endpoint. Původní processing/visibility/mode/time_scale se obnoví.

1. Po idle→walk crossfade 0.25 s a skutečném t≈0.2908–0.2909 s jsou `hand_l` i `hand_r` identické s čistým walk a mezi preview/live (vzdálenost 0 m). Čisté idle se od walk liší (ruka L ≈73 mm, R ≈19.5 mm).
2. Samostatně se začne nový idle→walk 0.25 s a **skutečně se přeruší v t≈0.1004 s**, kdy je ruka L ≈46.0 mm od čistého idle a ≈66.0 mm od čistého walk. Následný návrat do idle přes 0.12s crossfade dosáhne v t≈0.1708 s čistého idle (rozdíl 0 m u obou rukou, preview/live 0 m).
3. V čase t≈0.0507 s po obratu je ruka L jen ≈0.902 mm od čistého idle. Jde o diagnostiku, nikoli důkaz plynulosti zpětného blendu. Nesmyslný testovací práh >2 mm byl odstraněn, nikoli vydáván za produkční opravu.

## Skutečné běhy
První návrh **22/23 exit1**: limit 250 frame ticků zastavil hodiny v t=.25739 místo .29; zvýšeno na 500 a test 23/23 exit0. Následný návrh s opravdovým přerušením **26/27 exit1** kvůli neodůvodněnému prahu reverse >2mm. Finální verze **26/26 exit0, timeout=false dvakrát** z aktuálního souboru přes Godot konektor; syntax check **60/60**. Godot hlásí známé warningy ObjectDB20; žádná nová chyba skriptu. Samostatné pokusy o spuštění vnořeného Godot procesu pomocí OS.execute skončily rc1 s prázdným výstupem; nejsou započítány jako PASS. Finální test je reálně spuštěný Godot GDScript v projektu, ale bez GPU framebufferu.

## Skeptický Gemini audit
Dva skutečné audity zdrojového kódu a výsledků. Platné: výsledek po t>.25 potvrzuje koncový stav, nikoli přesný průběh v okamžiku .25; reverzní plynulost není doložena; `seek(t,true)` je použitelný jako čistý endpoint po blendu. První audit správně odhalil, že původní verze nepřerušovala rozpracovaný idle→walk; kód opraven a testováno t=.1004. Druhý audit potvrdil toto rozlišení, ale chybně nazval 26/26 jako 23/23, 0.001 world unit jako 1 mikrometr (při metrech je to 1 mm) a absolutní determinismus mezi běhy; tyto závěry **nepřijaty**. Gemini také nedoložil absence všech P1 v jiných scénářích. Tento test nezahrnuje GPU render, ruční obrazovou kontrolu, vynucené chybové ukončení ani měření interních vah AnimationMixer.

H3 stále PARTIAL. **Další jediný krok:** graficky zachytit skutečně přerušený idle→walk→idle v Xvfb/Mesa s maskou izolující geometrii ruky (ne jen 96×96 okolí) a porovnat průběh reverzního blendu; zachovat produkční kód beze změny.
