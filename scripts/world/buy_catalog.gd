extends RefCounted
## Katalog režimu nákupu (B1, 20. 11. 2026). Čistá data, žádné uzly.
##
## Každá položka:
##   name/desc   – český název a krátký (syrový, občas černě vtipný) popisek do UI
##   cat         – kategorie (CATEGORIES)
##   price       – cena v korunách (celé číslo; fiktivní ceník, `game_balance`)
##   w, d, h     – půdorys a výška v metrech (w, d jsou násobky Lot.CELL); předek položky = lokální +Z
##   tag         – tag chytrého objektu (akce z ActionLibrary: bed, sofa, fridge, stove, shower, tv,
##                 bookshelf, treadmill); "" = dekorace bez akcí
##   cap         – kapacita (kolik postav ji používá najednou)
##   use / pose  – lokální body použití / polohy [x, z] (stejný význam jako SmartObject.use_offsets)
##   quality     – 0,6..1,3: násobí kladné přírůstky komfortu, energie (spánek) a zábavy z akcí na objektu.
##                 Levná věc tak není jen kosmetika: na bazarové matraci se člověk vyspí pomaleji.
##   appeal      – -3..6: příspěvek k atmosféře okolí (Lot.appeal_at) → nálada „hezky zařízený domov“ / „ponurý kout“
##   place       – "indoor" | "outdoor" | "any"
##   layer       – "solid" (výchozí) | "floor" (koberec: leží pod nábytkem, koliduje jen s koberci a stěnami)
##   style       – jak ji LotFurnisher postaví z primitiv (když chybí model z Blenderu)
##   model       – jméno modelu v res://assets/models (AssetLibrary), "" = jen primitiva
##   color       – hlavní barva (hex)
##   light       – true = položka svítí (OmniLight3D)
##
## Ceny ani kvalita nejsou kalibrované na reálný trh; jsou to herní hodnoty (docs/world-building.md).

const CATEGORIES := {
	"sleep": "Spaní", "seating": "Sezení", "kitchen": "Kuchyň", "bathroom": "Koupelna",
	"electronics": "Elektronika", "hobby": "Zábava a sport", "decor": "Dekorace",
	"lighting": "Osvětlení", "outdoor": "Zahrada",
}
const CATEGORY_ORDER := ["sleep", "seating", "kitchen", "bathroom", "electronics", "hobby", "decor", "lighting", "outdoor"]

const ITEMS := {
	# ---------------------------------------------------------------- spaní
	"mattress_bazaar": {"name": "Matrace z bazaru", "desc": "Skvrny neřeš. Záda ano.", "cat": "sleep",
		"price": 390, "w": 1.0, "d": 2.0, "h": 0.2, "tag": "bed", "cap": 1,
		"use": [[-0.95, 0.3]], "pose": [[0.0, 0.0]], "quality": 0.7, "appeal": -2, "place": "indoor",
		"style": "mattress", "model": "", "color": "#8c8270"},
	"bed_single_pine": {"name": "Jednolůžko Borovice", "desc": "Rovná záda, rovné dny.", "cat": "sleep",
		"price": 3490, "w": 1.0, "d": 2.25, "h": 0.8, "tag": "bed", "cap": 1,
		"use": [[-0.95, 0.3]], "pose": [[0.0, 0.0]], "quality": 1.0, "appeal": 1, "place": "indoor",
		"style": "bed", "model": "bed_single", "color": "#5c86a6"},
	"bed_double_nocturne": {"name": "Manželská postel Nocturne", "desc": "Dost místa na dva. Nebo na jednoho a ticho.", "cat": "sleep",
		"price": 14900, "w": 1.75, "d": 2.25, "h": 0.9, "tag": "bed", "cap": 2,
		"use": [[-0.55, 1.65], [0.55, 1.65]], "pose": [[-0.4, 0.0], [0.4, 0.0]], "quality": 1.25, "appeal": 3, "place": "indoor",
		"style": "bed", "model": "bed_double", "color": "#7c5c8c"},
	# ---------------------------------------------------------------- sezení
	"sofa_bazaar": {"name": "Rozvrzaný gauč z bazaru", "desc": "Prý jen trochu pere psem.", "cat": "seating",
		"price": 650, "w": 2.0, "d": 1.0, "h": 0.85, "tag": "sofa", "cap": 2,
		"use": [[-0.5, 1.0], [0.5, 1.0]], "pose": [[-0.5, 0.3], [0.5, 0.3]], "quality": 0.75, "appeal": -1, "place": "indoor",
		"style": "sofa", "model": "", "color": "#6b5a3e"},
	"sofa_lagom": {"name": "Sedačka Lagom", "desc": "Šedá jako pondělí, ale pohodlná.", "cat": "seating",
		"price": 8900, "w": 2.25, "d": 1.0, "h": 0.85, "tag": "sofa", "cap": 2,
		"use": [[-0.5, 1.0], [0.5, 1.0]], "pose": [[-0.5, 0.32], [0.5, 0.32]], "quality": 1.05, "appeal": 2, "place": "indoor",
		"style": "sofa", "model": "sofa", "color": "#40668c"},
	"armchair_wingback": {"name": "Ušák po babičce", "desc": "Voní naftalínem a vzpomínkami.", "cat": "seating",
		"price": 2400, "w": 1.0, "d": 1.0, "h": 1.1, "tag": "sofa", "cap": 1,
		"use": [[0.0, 1.0]], "pose": [[0.0, 0.25]], "quality": 1.0, "appeal": 2, "place": "indoor",
		"style": "armchair", "model": "", "color": "#8c3b3b"},
	# ---------------------------------------------------------------- kuchyň
	"fridge_old": {"name": "Hučící lednice (rok 2004)", "desc": "V noci zní jako vzdálená dálnice.", "cat": "kitchen",
		"price": 1200, "w": 0.75, "d": 0.75, "h": 1.7, "tag": "fridge", "cap": 1,
		"use": [[0.0, 0.95]], "pose": [], "quality": 0.85, "appeal": -1, "place": "indoor",
		"style": "fridge", "model": "", "color": "#d8d2bf"},
	"fridge_polar": {"name": "Lednice Polar", "desc": "Tichá, chladná, spolehlivá. Lepší než ex.", "cat": "kitchen",
		"price": 12500, "w": 1.0, "d": 0.75, "h": 2.0, "tag": "fridge", "cap": 1,
		"use": [[0.0, 1.0]], "pose": [], "quality": 1.0, "appeal": 1, "place": "indoor",
		"style": "fridge", "model": "fridge", "color": "#ebebe6"},
	"hotplate": {"name": "Dvouplotýnkový vařič", "desc": "Těstoviny, polévka z pytlíku, těstoviny.", "cat": "kitchen",
		"price": 690, "w": 0.75, "d": 0.5, "h": 0.85, "tag": "stove", "cap": 1,
		"use": [[0.0, 0.85]], "pose": [], "quality": 0.75, "appeal": -1, "place": "indoor",
		"style": "hotplate", "model": "", "color": "#3a3a3d"},
	"stove_oven": {"name": "Sporák s troubou", "desc": "Konečně pečené brambory.", "cat": "kitchen",
		"price": 9900, "w": 1.0, "d": 0.75, "h": 0.9, "tag": "stove", "cap": 1,
		"use": [[0.0, 1.0]], "pose": [], "quality": 1.1, "appeal": 1, "place": "indoor",
		"style": "stove", "model": "", "color": "#ebebe6"},
	# ---------------------------------------------------------------- koupelna
	"shower_cabin": {"name": "Sprchový kout", "desc": "Nejlepší místo na brečení, kde to nikdo neslyší.", "cat": "bathroom",
		"price": 7800, "w": 1.0, "d": 1.0, "h": 2.1, "tag": "shower", "cap": 1,
		"use": [[0.0, 0.1]], "pose": [], "quality": 1.0, "appeal": 1, "place": "indoor",
		"style": "shower", "model": "", "color": "#e6eef2"},
	# ---------------------------------------------------------------- elektronika
	"tv_crt": {"name": "Stará CRT televize", "desc": "Obraz bliká, zprávy jsou stejně špatné.", "cat": "electronics",
		"price": 300, "w": 0.75, "d": 0.5, "h": 1.05, "tag": "tv", "cap": 2,
		"use": [[-0.5, 2.2], [0.5, 2.2]], "pose": [], "quality": 0.8, "appeal": -1, "place": "indoor",
		"style": "crt", "model": "", "color": "#2c2c2e"},
	"tv_flat": {"name": "Plochá televize 55\"", "desc": "Černé zrcadlo v obýváku.", "cat": "electronics",
		"price": 11990, "w": 1.5, "d": 0.5, "h": 1.35, "tag": "tv", "cap": 2,
		"use": [[-0.5, 2.3], [0.5, 2.3]], "pose": [], "quality": 1.15, "appeal": 2, "place": "indoor",
		"style": "tv", "model": "", "color": "#141416"},
	# ---------------------------------------------------------------- zábava a sport
	"treadmill_used": {"name": "Běžecký pás (použitý)", "desc": "Předchozí majitel na něm sušil prádlo.", "cat": "hobby",
		"price": 3900, "w": 0.75, "d": 1.75, "h": 1.35, "tag": "treadmill", "cap": 1,
		"use": [[0.0, 0.0]], "pose": [], "quality": 0.9, "appeal": 0, "place": "indoor",
		"style": "treadmill", "model": "", "color": "#1d1d20"},
	"bookshelf_oak": {"name": "Knihovna z masivu", "desc": "Knihy, které jednou přečteš.", "cat": "hobby",
		"price": 4200, "w": 1.5, "d": 0.5, "h": 2.0, "tag": "bookshelf", "cap": 1,
		"use": [[0.0, 0.95]], "pose": [], "quality": 1.0, "appeal": 2, "place": "indoor",
		"style": "shelf", "model": "", "color": "#6b4426"},
	# ---------------------------------------------------------------- dekorace
	"plant_monstera": {"name": "Pokojová monstera", "desc": "Jediná věc v bytě, o kterou se někdo stará.", "cat": "decor",
		"price": 590, "w": 0.5, "d": 0.5, "h": 1.2, "tag": "", "cap": 0,
		"use": [], "pose": [], "quality": 1.0, "appeal": 3, "place": "any",
		"style": "plant", "model": "", "color": "#2f6b34"},
	"rug_wool": {"name": "Vlněný koberec", "desc": "Schová fleky po minulém nájemníkovi.", "cat": "decor",
		"price": 1900, "w": 2.0, "d": 1.5, "h": 0.02, "tag": "", "cap": 0,
		"use": [], "pose": [], "quality": 1.0, "appeal": 2, "place": "indoor", "layer": "floor",
		"style": "rug", "model": "", "color": "#8c4a3a"},
	"trash_bags": {"name": "Pytle s odpadky", "desc": "Někdo je měl vynést. Nikdo je nevynesl.", "cat": "decor",
		"price": 0, "w": 0.75, "d": 0.5, "h": 0.6, "tag": "", "cap": 0,
		"use": [], "pose": [], "quality": 1.0, "appeal": -3, "place": "any",
		"style": "trash", "model": "", "color": "#1a1a1c"},
	# ---------------------------------------------------------------- osvětlení
	"lamp_floor": {"name": "Stojací lampa", "desc": "Teplé světlo na dlouhé večery.", "cat": "lighting",
		"price": 1290, "w": 0.5, "d": 0.5, "h": 1.6, "tag": "", "cap": 0,
		"use": [], "pose": [], "quality": 1.0, "appeal": 1, "place": "indoor",
		"style": "lamp", "model": "", "color": "#c9b48a", "light": true},
	# ---------------------------------------------------------------- zahrada
	"bench_garden": {"name": "Zahradní lavička", "desc": "Na kouření a dlouhé telefonáty.", "cat": "outdoor",
		"price": 2490, "w": 1.5, "d": 0.75, "h": 0.85, "tag": "sofa", "cap": 2,
		"use": [[-0.4, 0.85], [0.4, 0.85]], "pose": [[-0.4, 0.15], [0.4, 0.15]], "quality": 0.8, "appeal": 2, "place": "outdoor",
		"style": "bench", "model": "", "color": "#7a5534"},
	"grill_garden": {"name": "Zahradní gril", "desc": "Sousedi to ucítí. A přijdou.", "cat": "outdoor",
		"price": 3290, "w": 0.75, "d": 0.75, "h": 1.0, "tag": "stove", "cap": 1,
		"use": [[0.0, 0.95]], "pose": [], "quality": 0.95, "appeal": 1, "place": "outdoor",
		"style": "grill", "model": "", "color": "#2a2a2c"},
	"planter_raised": {"name": "Vyvýšený záhon", "desc": "Rajčata, bylinky a terapie zdarma.", "cat": "outdoor",
		"price": 1490, "w": 2.0, "d": 1.0, "h": 0.45, "tag": "", "cap": 0,
		"use": [], "pose": [], "quality": 1.0, "appeal": 2, "place": "outdoor",
		"style": "planter", "model": "", "color": "#5a3d24"},
}

const ACTION_TAGS := ["bed", "sofa", "fridge", "stove", "shower", "tv", "bookshelf", "treadmill"]
const PLACES := ["indoor", "outdoor", "any"]
const STYLES := ["mattress", "bed", "sofa", "armchair", "fridge", "hotplate", "stove", "shower", "crt", "tv",
	"treadmill", "shelf", "plant", "rug", "trash", "lamp", "bench", "grill", "planter"]


static func has(id: Variant) -> bool:
	return typeof(id) in [TYPE_STRING, TYPE_STRING_NAME] and (ITEMS as Dictionary).has(String(id))


static func get_item(id: String) -> Dictionary:
	return (ITEMS as Dictionary).get(id, {})


static func layer(id: String) -> String:
	return String(get_item(id).get("layer", "solid"))


static func ids_in(cat: String) -> Array:
	var out: Array = []
	for k in ITEMS:
		if String(ITEMS[k]["cat"]) == cat:
			out.append(k)
	out.sort_custom(func(a, b): return int(ITEMS[a]["price"]) < int(ITEMS[b]["price"]) \
		or (int(ITEMS[a]["price"]) == int(ITEMS[b]["price"]) and String(a) < String(b)))
	return out


## Kontrola konzistence katalogu (test + start hry). Prázdné pole = v pořádku.
static func validate(cell: float) -> Array:
	var errs: Array = []
	for id in ITEMS:
		var it: Dictionary = ITEMS[id]
		for k in ["name", "desc", "cat", "price", "w", "d", "h", "tag", "cap", "use", "pose", "quality", "appeal", "place", "style", "model", "color"]:
			if not it.has(k):
				errs.append("%s: chybí %s" % [id, k])
		if not errs.is_empty():
			continue
		if not (CATEGORIES as Dictionary).has(String(it["cat"])):
			errs.append("%s: neznámá kategorie" % id)
		if int(it["price"]) < 0 or int(it["price"]) > 1000000:
			errs.append("%s: cena mimo rozsah" % id)
		for k in ["w", "d"]:
			var v: float = float(it[k])
			if v < cell or v > 4.0 or absf(v / cell - roundf(v / cell)) > 1e-6:
				errs.append("%s: %s není násobek buňky" % [id, k])
		if String(it["tag"]) != "" and not ACTION_TAGS.has(String(it["tag"])):
			errs.append("%s: neznámý tag" % id)
		if String(it["tag"]) != "" and (int(it["cap"]) < 1 or (it["use"] as Array).size() < 1):
			errs.append("%s: objekt s akcí potřebuje kapacitu a bod použití" % id)
		if String(it["tag"]) == "" and (int(it["cap"]) != 0 or not (it["use"] as Array).is_empty()):
			errs.append("%s: dekorace nemá body použití" % id)
		if (it["use"] as Array).size() > 4 or (it["pose"] as Array).size() > 4:
			errs.append("%s: příliš mnoho bodů" % id)
		if float(it["quality"]) < 0.6 or float(it["quality"]) > 1.3:
			errs.append("%s: kvalita mimo 0,6..1,3" % id)
		if int(it["appeal"]) < -3 or int(it["appeal"]) > 6:
			errs.append("%s: atmosféra mimo -3..6" % id)
		if not PLACES.has(String(it["place"])):
			errs.append("%s: neznámé umístění" % id)
		if not STYLES.has(String(it["style"])):
			errs.append("%s: neznámý styl" % id)
		if String(it.get("layer", "solid")) not in ["solid", "floor"]:
			errs.append("%s: neznámá vrstva" % id)
		if String(it.get("layer", "solid")) == "floor" and String(it["tag"]) != "":
			errs.append("%s: koberec nemůže mít akce" % id)
		if not Color.html_is_valid(String(it["color"])):
			errs.append("%s: neplatná barva" % id)
	return errs
