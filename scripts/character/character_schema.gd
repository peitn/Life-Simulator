extends RefCounted
## Schéma CharacterData v2 – JEDINÝ popis toho, jaká pole postava má, jaké mají rozsahy,
## výchozí hodnoty a katalogy povolených hodnot. Používá ho validátor (server i import),
## náhodný generátor, migrace i budoucí editor (posuvníky se generují ze schématu).
##
## Zásady (tvorba postavy, viz ROADMAP (0) a review ChatGPT ve zprávě 38):
##  - tělo, gramatický rod, genderová identita, orientace, hlas a oblečení jsou NEZÁVISLÉ osy,
##    žádná pole se navzájem automaticky neodvozují;
##  - žádná volba „rasa“ ani etnické předvolby – kůže je spojitý fyzikální model
##    (melanin / podtón / prokrvení), vlasy a oči taky;
##  - všechna oblečení a účesy jsou dostupná pro jakékoli tělo a identitu;
##  - postavy jsou dospělé (18+);
##  - citlivé soukromé údaje (predispozice, traumata) mají obsahový štítek a respektují
##    nastavení obsahu; nevyplněno = výchozí (bez predispozic).
##
## Typy specifikací polí:
##   ["f", min, max, výchozí]     – číslo (float)
##   ["i", min, max, výchozí]     – celé číslo
##   ["b", výchozí]               – bool
##   ["e", katalog, výchozí]      – jedna hodnota z katalogu (Dictionary id -> popisek)
##   ["set", katalog, max]        – podmnožina katalogu bez opakování
##   ["name", min_len, max_len]   – jméno (písmena, mezera, spojovník, apostrof, tečka)
##   ["text", max_len, víceřádkový?] – volný text (bez řídicích/bidi znaků; v BBCode UI escapovat přes CharacterValidator.display_safe)
##   ["color", výchozí]           – barva "#rrggbb"
## Pole, která v datech chybí, doplní validátor výchozí hodnotou (kromě povinných jmen).

## v2 (běh 9): obličej má 3 explicitní osy asymetrie místo jedné velikosti (asym_eyes / asym_mouth /
##     asym_jaw), body.head_size (velikost hlavy nezávislá na výšce), jizvy/tetování s volbou „hidden“
##     (nevykreslí se ostatním hráčům), důlek v bradě 0..1, hranaté závorky v textech povolené.
##     Migrace v1 → v2: CharacterCodec.migrate.
## v3 (běh 10, C4): skin.detail_seed – explicitní „rozmístění“ pih, znamének, jizev a tetování (editor:
##     tlačítko „jiné rozmístění“), nikdy ze jména. Migrace v2 → v3 ho jednou odvodí z náhodného uid postavy.
const VERSION := 3

const GRAMMAR := {"m": "on", "f": "ona", "n": "ono", "pl": "oni"}

const GENDER_IDENTITY := {
	"neuvedeno": "Neuvedeno", "muz": "Muž", "zena": "Žena", "nebinarni": "Nebinární",
	"genderfluidni": "Genderfluidní", "agender": "Agender", "jine": "Jiné (vlastní popis)",
}
## Koho postava přitahuje (romanticky); prázdná množina + aromantic = nikoho. Výchozí: neuvedeno = prázdné.
const ATTRACTION := {"muzi": "Muži", "zeny": "Ženy", "nebinarni": "Nebinární lidé"}

const FACE_MORPHS := {
	"head_width": "Šířka hlavy", "head_height": "Výška hlavy", "forehead_slope": "Sklon čela",
	"brow_ridge": "Nadočnicové oblouky", "brow_height": "Výška obočí",
	"eye_size": "Velikost očí", "eye_tilt": "Sklon očí", "eye_distance": "Vzdálenost očí",
	"eye_depth": "Hloubka očí", "eyelid_hood": "Převislá víčka",
	"nose_length": "Délka nosu", "nose_width": "Šířka nosu", "nose_bridge": "Hřbet nosu",
	"nose_tip": "Špička nosu", "nose_tip_angle": "Natočení špičky",
	"cheekbones": "Lícní kosti", "cheeks_fullness": "Plnost tváří",
	"jaw_width": "Šířka čelisti", "jaw_angle": "Úhel čelisti",
	"chin_length": "Délka brady", "chin_width": "Šířka brady", "chin_cleft": "Důlek v bradě",
	"mouth_width": "Šířka úst", "lip_upper": "Horní ret", "lip_lower": "Dolní ret", "philtrum": "Žlábek pod nosem",
	"ear_size": "Velikost uší", "ear_angle": "Odstávající uši", "neck_width": "Šířka krku",
}

## Asymetrie obličeje (každý skutečný obličej je trochu nesouměrný; znaménko = která strana).
const FACE_ASYMMETRY := {"asym_eyes": "Asymetrie očí", "asym_mouth": "Asymetrie nosu a úst", "asym_jaw": "Asymetrie čelisti"}

const BODY_ZONES := {
	"oblicej": "Obličej", "krk": "Krk", "hrudnik": "Hrudník", "bricho": "Břicho", "zada": "Záda",
	"leva_paze": "Levá paže", "prava_paze": "Pravá paže", "leva_ruka": "Levá ruka", "prava_ruka": "Pravá ruka",
	"leva_noha": "Levá noha", "prava_noha": "Pravá noha",
}
const TATTOO_DESIGNS := {
	"text": "Nápis", "kvetina": "Květina", "geometricky": "Geometrický", "zvire": "Zvíře",
	"abstraktni": "Abstraktní", "symbol": "Symbol", "ornament": "Ornament", "portret": "Portrét",
}

const HAIR_STYLES := {
	"holy": "Oholená hlava", "strih_nakratko": "Na ježka", "kratke": "Krátké", "kratke_kudrny": "Krátké kudrny",
	"undercut": "Undercut", "stredni": "Středně dlouhé", "mikado": "Mikádo", "dlouhe_rovne": "Dlouhé rovné",
	"dlouhe_vlnite": "Dlouhé vlnité", "kudrnate": "Kudrnaté", "afro": "Afro", "copanky": "Copánky (box braids)",
	"cornrows": "Cornrows", "dredy": "Dredy", "drdol": "Drdol", "culik": "Culík",
}
## Dlouhé účesy (pro dočasnou volbu sítě vlasů do C4).
const LONG_HAIR := ["stredni", "mikado", "dlouhe_rovne", "dlouhe_vlnite", "kudrnate", "afro", "copanky", "dredy", "drdol", "culik"]
const BROW_STYLES := {"prirozene": "Přirozené", "huste": "Husté", "tenke": "Tenké", "rovne": "Rovné", "oblouk": "Oblouk", "srostle": "Srostlé"}
const FACIAL_HAIR := {
	"zadne": "Žádné", "strniste": "Strniště", "knir": "Knír", "bradka": "Bradka", "kozi_bradka": "Kozí bradka",
	"plnovous": "Plnovous", "licousy": "Licousy",
}
const GLASSES := {"zadne": "Žádné", "kulate": "Kulaté", "hranate": "Hranaté", "tenke": "Tenké obroučky", "silne": "Silné obroučky"}

const OUTFIT_CATEGORIES := {
	"bezne": "Běžné", "pracovni": "Pracovní", "spolecenske": "Společenské", "spani": "Na spaní", "sport": "Sport",
}
## Oblečení není vázané na tělo ani identitu – každý kus jde na kohokoli.
const TOPS := {
	"tricko": "Tričko", "tilko": "Tílko", "kosile": "Košile", "halenka": "Halenka", "svetr": "Svetr", "rolak": "Rolák",
	"mikina": "Mikina", "sako": "Sako s košilí", "saty": "Šaty", "pyzamo": "Pyžamo", "sportovni": "Sportovní tričko",
}
const BOTTOMS := {
	"dziny": "Džíny", "kalhoty": "Kalhoty", "oblekove": "Oblekové kalhoty", "kratasy": "Kraťasy", "sukne": "Sukně",
	"teplaky": "Tepláky", "leginy": "Legíny", "pyzamo": "Pyžamové kalhoty", "zadne": "— (šaty)",
}
const SHOES := {
	"tenisky": "Tenisky", "polobotky": "Polobotky", "kozacky": "Kozačky", "lodicky": "Lodičky", "sandaly": "Sandály",
	"pracovni": "Pracovní boty", "bacory": "Bačkory", "bosy": "Naboso",
}

const TRAIT_COST := {
	"optimista": 2, "aktivni": 1, "pedant": 1, "spolecensky": 1, "samotar": 1, "gurman": 1, "hravy": 1, "knihomol": 1,
	"lenoch": 0, "brucoun": 0, "zarlivy": 0, "vznetlivy": 0, "cynik": 0, "impulzivni": 0, "uzkostlivy": 0,
}
const TRAIT_BUDGET := 4
const MIN_TRAITS := 1
const MAX_TRAITS := 5

const ASPIRATIONS := {
	"rodina": "Rodinné zázemí", "kariera": "Kariéra", "penize": "Finanční jistota", "pratele": "Spousta přátel",
	"tvorba": "Tvořit něco svého", "klid": "Klidný život", "uznani": "Uznání", "nezavislost": "Nezávislost",
	"napravit": "Napravit minulost",
}
const MAX_ASPIRATIONS := 2

const FAMILY := {
	"neuvedeno": "Neuvedeno", "oba_rodice": "Oba rodiče", "jeden_rodic": "Jeden rodič", "prarodice": "Prarodiče",
	"pestouni": "Pěstouni", "detsky_domov": "Dětský domov",
}
const CHILDHOOD := {
	"neuvedeno": "Neuvedeno", "klidne": "Klidné", "chude": "V chudobě", "prisne": "Přísné", "chaoticke": "Chaotické",
	"stehovani": "Časté stěhování", "zanedbane": "Citově zanedbané",
}
## Předchozí práce jako obory (bez rodových tvarů povolání).
const PAST_WORK := {
	"prodej": "Prodej", "gastro": "Gastro", "sklad": "Sklad a logistika", "kancelar": "Kancelář", "doprava": "Doprava",
	"it": "IT", "zdravotnictvi": "Zdravotnictví", "skolstvi": "Školství", "remeslo": "Řemeslo", "umeni": "Umění a kultura",
	"brigady": "Brigády", "podnikani": "Podnikání", "studium": "Studium", "bez_prace": "Bez práce",
}
const MAX_PAST_WORK := 3

## Predispozice duševního zdraví, které simulace umí (ostatní přibudou s jejich systémy).
## Popisy dopadů ukazuje editor – nikdy nejde o bonus ani trest a nesouvisí s identitou.
const PREDISPOSITIONS := {
	"anxiety": {"label": "Úzkostná porucha", "content": "mental_health",
		"effects": "Citlivější reakce na stres a spouštěče, možné panické ataky; pomáhá dýchání, opora a postupná expozice."},
	"depression": {"label": "Depresivní porucha", "content": "mental_health",
		"effects": "Sklon k obdobím skleslosti: méně radosti a energie začít; pomáhá aktivita, kontakt, spánek a čas."},
}
## Traumata v příběhu postavy (dopady přibudou se systémem paměti a spouštěčů – PTSD).
const TRAUMAS := {
	"ztrata_blizkeho": {"label": "Ztráta blízkého člověka", "content": "mental_health"},
	"rozchod": {"label": "Bolestný rozchod nebo zrada", "content": "mental_health"},
	"sikana": {"label": "Šikana", "content": "mental_health"},
	"nehoda": {"label": "Vážná nehoda", "content": "mental_health"},
	"vyhozeni": {"label": "Náhlá ztráta práce", "content": "mental_health"},
	"chudoba": {"label": "Dlouhodobá chudoba nebo exekuce", "content": "mental_health"},
	"domaci_nasili": {"label": "Domácí násilí v rodině", "content": "mental_health"},
}
const MAX_TRAUMAS := 3

## Specifikace skupin. "public": true = skupina jde do veřejného vzhledového snapshotu
## (replikuje se všem); ostatní jen vlastníkovi / serveru.
const GROUPS := {
	"identity": {"public_fields": ["first_name", "last_name", "nickname", "grammar"], "fields": {
		"first_name": ["name", 1, 24],
		"last_name": ["name", 0, 24],
		"nickname": ["text", 16],
		"grammar": ["e", GRAMMAR, "m"],
		"gender_identity": ["e", GENDER_IDENTITY, "neuvedeno"],
		"gender_custom": ["text", 24],
		"attracted_to": ["set", ATTRACTION, 3],
		"aromantic": ["b", false],
		"asexual": ["b", false],
	}},
	"body": {"public": true, "fields": {
		"height_cm": ["f", 145.0, 205.0, 172.0],
		"age": ["i", 18, 95, 30],
		"frame": ["f", 0.0, 1.0, 0.5],
		"muscle": ["f", 0.0, 1.0, 0.35],
		"body_fat": ["f", 0.0, 1.0, 0.3],
		"shoulders": ["f", 0.0, 1.0, 0.5],
		"chest": ["f", 0.0, 1.0, 0.5],
		"bust": ["f", 0.0, 1.0, 0.2],
		"waist": ["f", 0.0, 1.0, 0.5],
		"hips": ["f", 0.0, 1.0, 0.5],
		"leg_length": ["f", 0.0, 1.0, 0.5],
		"head_size": ["f", -1.0, 1.0, 0.0],     # velikost hlavy vůči proporční výchozí (±6 %), nezávislá na výšce
	}},
	"face": {"public": true, "fields": {}},   # doplní se z FACE_MORPHS (−1..1) + asymmetry
	"skin": {"public": true, "fields": {
		"tone": ["f", 0.0, 1.0, 0.45],          # melanin: světlá … tmavá (spojitě)
		"undertone": ["f", -1.0, 1.0, 0.0],     # chladný (růžový) … teplý (zlatý/olivový)
		"redness": ["f", 0.0, 1.0, 0.3],        # prokrvení
		"freckles": ["f", 0.0, 1.0, 0.0],
		"moles": ["f", 0.0, 1.0, 0.15],
		"acne": ["f", 0.0, 1.0, 0.0],
		"vitiligo": ["f", 0.0, 1.0, 0.0],
		"weathering": ["f", 0.0, 1.0, 0.0],     # stárnutí kůže navíc k věku (slunce, životní styl)
		"detail_seed": ["i", 0, 65535, 0],      # rozmístění detailů kůže (explicitní atribut, ne ze jména)
	}},
	"hair": {"public": true, "fields": {
		"style": ["e", HAIR_STYLES, "kratke"],
		"melanin": ["f", 0.0, 1.0, 0.6],        # blond … černé
		"red": ["f", 0.0, 1.0, 0.15],           # feomelanin (zrzavost)
		"grey": ["f", 0.0, 1.0, 0.0],
		"dyed": ["b", false],
		"dye_color": ["color", "#7a3b8f"],
		"hairline": ["f", 0.0, 1.0, 0.0],       # ustupující vlasová linie
		"brows": ["e", BROW_STYLES, "prirozene"],
		"brow_density": ["f", 0.0, 1.0, 0.6],
		"facial": ["e", FACIAL_HAIR, "zadne"],
		"facial_density": ["f", 0.0, 1.0, 0.6],
	}},
	"eyes": {"public": true, "fields": {
		"iris": ["f", 0.0, 1.0, 0.6],           # modré … zelené … oříškové … hnědé … tmavé
		"heterochromia": ["f", 0.0, 1.0, 0.0],
	}},
	"makeup": {"public": true, "fields": {
		"eyeliner": ["f", 0.0, 1.0, 0.0],
		"eyeshadow": ["f", 0.0, 1.0, 0.0],
		"eyeshadow_color": ["color", "#6b5a7a"],
		"lipstick": ["f", 0.0, 1.0, 0.0],
		"lip_color": ["color", "#9e3a42"],
		"blush": ["f", 0.0, 1.0, 0.0],
	}},
	"aids": {"public": true, "fields": {
		"glasses": ["e", GLASSES, "zadne"],
		"hearing_aid": ["b", false],
	}},
	"voice": {"public": true, "fields": {
		"pitch": ["f", -1.0, 1.0, 0.0],
		"timbre": ["f", -1.0, 1.0, 0.0],        # tmavý … jasný
		"tempo": ["f", -1.0, 1.0, 0.0],
		"roughness": ["f", 0.0, 1.0, 0.2],
	}},
	"personality": {"public_fields": ["traits"], "fields": {
		"traits": ["traits"],
		"aspirations": ["set", ASPIRATIONS, MAX_ASPIRATIONS],
	}},
	"story": {"fields": {
		"family": ["e", FAMILY, "neuvedeno"],
		"childhood": ["e", CHILDHOOD, "neuvedeno"],
		"past_work": ["set", PAST_WORK, MAX_PAST_WORK],
		"hometown": ["text", 40],
		"backstory": ["text", 600, true],
	}},
	"mind": {"content": "mental_health", "fields": {
		"predispositions": ["predisp"],
		"traumas": ["set", TRAUMAS, MAX_TRAUMAS],
		"morning_worse": ["b", false],
	}},
}
## Skupiny se seznamy (zvláštní validace). Jizva = {zone, size[, hidden]}, tetování = {zone, design, color[, hidden]};
## hidden = true → položka zůstane jen vlastníkovi (do veřejného snapshotu nejde, ostatní ji nevidí).
## Ve veřejném snapshotu jsou jen parametry vykreslení (žádný původ ani příběh jizvy).
const MAX_SCARS := 6
const MAX_TATTOOS := 8

## Limity serializace.
const MAX_CODE_LEN := 8192
const MAX_JSON_BYTES := 32768


static func fields(group: String) -> Dictionary:
	if group == "face":
		var f := {}
		for k in FACE_MORPHS:
			f[k] = ["f", -1.0, 1.0, 0.0]
		f["chin_cleft"] = ["f", 0.0, 1.0, 0.0]   # důlek v bradě nemá „záporný“ směr
		for k in FACE_ASYMMETRY:
			f[k] = ["f", -1.0, 1.0, 0.0]
		return f
	return GROUPS[group]["fields"]


static func group_names() -> Array:
	return GROUPS.keys()


## Je pole součástí veřejného snapshotu?
static func is_public(group: String, field: String) -> bool:
	var g: Dictionary = GROUPS.get(group, {})
	if bool(g.get("public", false)):
		return true
	return (g.get("public_fields", []) as Array).has(field)


static func default_value(spec: Array) -> Variant:
	match String(spec[0]):
		"f", "i":
			return spec[3]
		"b", "color":
			return spec[1]
		"e":
			return spec[2]
		"set", "traits":
			return []
		"predisp":
			return {}
		"name", "text":
			return ""
	return null


static func defaults() -> Dictionary:
	var d := {}
	for g in GROUPS:
		var gd := {}
		var fs := fields(g)
		for k in fs:
			gd[k] = default_value(fs[k])
		d[g] = gd
	d["skin"]["scars"] = []
	d["skin"]["tattoos"] = []
	d["clothing"] = default_outfits()
	return d


static func default_outfits() -> Dictionary:
	return {
		"bezne": {"top": "tricko", "bottom": "dziny", "shoes": "tenisky", "top_color": "#5b6b7a", "bottom_color": "#2f3a4a"},
		"pracovni": {"top": "kosile", "bottom": "kalhoty", "shoes": "polobotky", "top_color": "#c9cdd2", "bottom_color": "#35383d"},
		"spolecenske": {"top": "sako", "bottom": "oblekove", "shoes": "polobotky", "top_color": "#23262b", "bottom_color": "#23262b"},
		"spani": {"top": "pyzamo", "bottom": "pyzamo", "shoes": "bosy", "top_color": "#7d8fa3", "bottom_color": "#7d8fa3"},
		"sport": {"top": "sportovni", "bottom": "teplaky", "shoes": "tenisky", "top_color": "#3f7f6a", "bottom_color": "#2b2f33"},
	}


static func trait_cost(ids: Array) -> int:
	var c := 0
	for id in ids:
		c += int(TRAIT_COST.get(id, 99))
	return c
