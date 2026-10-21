# Blender bridge (Life Simulator)

Zdrojové skripty 3D assetů. Blender (4.0.2, headless) běží jako samostatná služba – do Godot projektu
se data dostávají textově po částech, proto vlastní kompaktní formát **LSX** (v3, od C2 i **v4**).

| Soubor | Obsah |
|---|---|
| `lsx_common.py` | pomocníci (zaoblené kvádry, materiály, převod os Blender→Godot), `export_lsx()` (+ `_quad_part()` pro řídicí sítě) a `chunk()` |
| `char.py` | **tělo C2**: jedna neutrální řídicí síť (868 vrcholů, čtyřúhelníky) se 10 shape keys, kostra 17 kostí, heat-weights → `body.lsx` |
| `char_v3.py` | postava v3 (běh 5) – zdroj `character_head.lsx` (hlava, oči, krátké/dlouhé vlasy) do C3 |
| `furn.py` | gauč, dvojlůžko, jednolůžko, lednice (bevely, polštáře, přehoz, lístečky na lednici…) |

## Postup
1. V Blenderu: `exec(lsx_common.py)`, `exec(char.py)` + `export_body()` / `exec(furn.py)` + `build_*()` a `export_lsx(...)`.
   Výsledek je base64 v `/tmp/lifesim_lsx/<jméno>.b64`, `chunk(jméno, k)` vypíše k-tou část (3 500 znaků + CRC-32).
2. Části se uloží do `res://assets/src/<jméno>.<n>.part` (jeden soubor může nést víc částí). Doporučeno
   ověřit CRC každé části už při přepisu (lokálně), ne až v Godotu.
3. `tools/import_lsx.gd` → ověří CRC každé části, složí `res://assets/src/<jméno>.lsx`, postaví scénu
   (`scripts/assets/lsx_decoder.gd`) a uloží **GLB** do `res://assets/models/` + `manifest.json`.
   Složené modely (`COMPOSE`): `character` = `body.lsx` (tělo v4) + `character_head.lsx` (hlava a vlasy v3).
4. Za běhu `scripts/assets/asset_library.gd` načte GLB přes GLTFDocument (bez importu editoru),
   přidá materiálům povrchový detail podle prefixu (`fabric_`, `wood_`, `skin_`…) a cachuje PackedScene.

## LSX v4 (C2, běh 8)
- **Morph targety** ze shape keys: na část `[jméno, měřítko, offset, délka]`, výchylky 3×int8 planárně,
  delta-kódované mezi sousedními vrcholy; výchylky < 0,5 mm se nulují. Hlavička `morphs` = pořadí jmen
  (max 32), `meta.morph_bones` = posuny kloubů při plné váze, `meta.basis_defaults` = výchozí hodnoty
  schématu, které základní síť představuje.
- **Čtyřúhelníková část** (`prim: quad`): ŘÍDICÍ síť + materiál po plochách (`mats`, `fmat`), bez normál.
  Import ji zjemní Catmull-Clarkem (`scripts/assets/subdiv.gd`, totožné s `cc_matrix()` v `char.py`
  a s Blender Subdivision Surface bez limitní plochy – chyba 3,6e-7 m) a normály dopočítá pro základ
  i každý morf. Přenáší se 4× méně dat (tělo 21,5 kB textu místo ~90 kB).
- Morfy jsou spočítané **na jemné síti** (to, co hráč vidí) a převedené na řídicí síť nejmenšími čtverci
  (`min |S·d − D|² + λ|d|²`) – jinak by zjemnění lokální tvary (poprsí) zploštilo na polovinu.
- Blend shapes v Godotu: `BLEND_SHAPE_MODE_NORMALIZED` s absolutními cíli – jen tak je Godot GLTF export
  zapíše správně (režim RELATIVE ukládá cíle chybně a rozbije nulové výchylky normál).
- Indexy kostí ve vrcholech importovaného GLB odkazují na **bind (kloub skinu)**, ne na index kosti
  v kostře – při práci s váhami vždy přes `Skin.get_bind_bone()`/`get_bind_name()`.

## Konvence
- Osy: Blender (Z nahoru, předek −Y) → Godot (Y nahoru, předek **+Z**); postavy chodí ve směru +Z.
- Kosti mají v Godotu klidovou rotaci = identita (jen posun) → animace (`scripts/assets/character_anims.gd`)
  se píší v osách modelu. Tvar těla mění klidové polohy ramen/kyčlí i inverzní bind (SimVisual), délku nohou
  měřítko stehna, velikost hlavy měřítko kosti hlavy.
- Uzly částí: `<skupina>__<část>__<materiál>` (skupiny `body`, `head`, `hair_short`, `hair_long`).
- Rozpočet: nábytek ≤ 8 000 trojúhelníků, hlavní postava ≤ 18 000 (od C3 s obličejem; hlídá `tests/test_assets.gd`).
- Hlava (C3) se nestaví v Blenderu, ale procedurálně při importu (`scripts/assets/head_builder.gd` +
  `character_assembly.gd`): každý obličejový morf je funkce parametrů schématu, takže blend shapes přesně
  odpovídají datům; z `character_head.lsx` se berou jen vlasy (morfy lebky se na ně přenesou).

## Proč ne přímo GLB
Blender služba umí exportovat jen scény z primitiv a výstup skriptů má limit ~4 kB. LSX (12bit pozice,
oktaedrické normály, kódování indexů „vysoké hladiny“, max. 2 kosti/vrchol, zlib) zmenší postavu
z ~290 kB GLB na ~44 kB textu. Přepis při přenosu odhalí CRC (v běhu 5 tak byla odhalena a opravena
jedna chyba přenosu v části gauče; v běhu 8 se části ověřovaly CRC ještě před zápisem do projektu).
