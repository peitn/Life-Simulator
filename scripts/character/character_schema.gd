extends RefCounted
## Schéma CharacterData (verze VERSION níže) – JEDINÝ popis toho, jaká pole postava má, jaké mají rozsahy,
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
##   ["axes", katalog, min, max]   – slovník {osa z katalogu: číslo v rozsahu}; chybějící osa = odvozená
## Pole, která v datech chybí, doplní validátor výchozí hodnotou (kromě povinných jmen).

## v2 (běh 9): obličej má 3 explicitní osy asymetrie místo jedné velikosti (asym_eyes / asym_mouth /
##     asym_jaw), body.head_size (velikost hlavy nezávislá na výšce), jizvy/tetování s volbou „hidden“
##     (nevykreslí se ostatním hráčům), důlek v bradě 0..1, hranaté závorky v textech povolené.
##     Migrace v1 → v2: CharacterCodec.migrate.
## v3 (běh 10, C4): skin.detail_seed – explicitní „rozmístění“ pih, znamének, jizev a tetování (editor:
##     tlačítko „jiné rozmístění“), nikdy ze jména. Migrace v2 → v3 ho jednou odvodí z náhodného uid postavy.
## v4 (běh 13): body.neck_length −1..1 (délka krku ±15 mm ≈ ±17 %, 0 = anatomicky upravená výchozí délka).
##     Migrace v3 → v4 doplní 0; ostatní proporce se nemění.
## v5 (běh 20, 1. osa psychiky): personality.hexaco {osa: −1..1} (volitelná explicitní osobnost; chybějící osa se
##     odvodí z rysů) a personality.psyche_seed 0..65535 (individualita psychiky, explicitní, nikdy ze jména). Obojí
##     soukromé. Migrace v4 → v5: hexaco {} a seed jednou z náhodného uid (CharacterCodec._v4_to_v5).
## v6 (běh 21, C3++): detaily obličeje ve skupině face – řasy (lash_length / lash_density / lash_curl 0..1, výchozí
##     0,5 = dosavadní vzhled), zuby (teeth_shade odstín skloviny, teeth_gap mezera mezi horními jedničkami,
##     teeth_crooked mírně vybočené zuby; 0 = rovné) a makeup.mascara. Vše veřejné (je vidět). Migrace v5 → v6
##     doplní výchozí hodnoty (CharacterCodec._v5_to_v6), vzhled migrované postavy se nemění.
## v7 (běh 22, C4c mikrodetail kůže): skin.type (typ pleti: normální / suchá / smíšená / mastná – určuje, KDE se maz
##     a suchost projeví: T-zóna vs. tváře a tělo), skin.oiliness a skin.dryness 0..1 (síla). Čistě vzhled → veřejné.
##     Nezávislé na rodu, identitě, tónu kůže i jménu. Migrace v6 → v7 doplní výchozí „normální“ pleť
##     (CharacterCodec._v6_to_v7); drsnost T-zóny zůstane blízko dřívější (−0,065 proti −0,08).
## v8: continuous personality sliders and optional psyche dispositions. Legacy traits remain for migration/presets.
## v9 (27. 10. 2026, psychika A): mind.neuro – volitelný neurodivergentní profil (ADHD, autistické osy, tiky,
##     náročnost čtení) jako nezávislé spojité posuvníky 0..1 (chybějící osa = 0 = bez výrazné odlišnosti)
##     a mind.interest_focus (oblast hlubokého zájmu). Soukromé. Migrace v8 → v9 doplní {} a výchozí zájem.
## v10 (psychika B): mind.memory – schopnosti sociální a afektivní paměti (retention / precision /
##     emotional_weight, 0..1, chybějící = 0,5 = průměr). Soukromé. Migrace v9 → v10 doplní {}.
## v11 (psychika C): mind.mood – průběh nálady (bipolární spektrum, cyklotymní a dystymní průběh) jako
##     spojité posuvníky 0..1 (chybějící = 0 = bez sklonu). Soukromé. Migrace v10 → v11 doplní {}.
## v12 (psychika I): mind.thoughts – styl vnitřního hlasu (sklon k ruminaci, ke starostem, k nadějným
##     myšlenkám), 0..1, chybějící = 0,5 = průměr. Soukromé. Migrace v11 → v12 doplní {}.
## v13 (psychika D): mind.accents – zvýrazněné osobnostní rysy (0..1, 0 = bez akcentu) a mind.accent_labels
##     (volitelný soukromý výklad názvem). Soukromé. Migrace v12 → v13 doplní {} a false.
## v14 (psychika E): predispozice ocd a social_anxiety (katalog) a mind.ocd_theme (čeho se pochybnost
##     týká). Soukromé. Migrace v13 → v14 doplní výchozí téma.
## v15 (psychika F): predispozice addiction a mind.substances – zvyk na látky a činnosti (0..1, 0 = AI je sama
##     nezačne). Herní obecné kategorie, žádné dávky. Soukromé. Migrace v14 → v15 doplní {}.
const VERSION := 15

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

## Detaily obličeje (v6): [popisek, specifikace]. Nejsou to tvarové morfy lebky (FaceMorphs.DETAIL_FIELDS je převádí
## na morfy řas a zubů; odstín zubů je jen barva).
const FACE_DETAILS := {
	"lash_length": ["Délka řas", ["f", 0.0, 1.0, 0.5]],
	"lash_density": ["Hustota řas", ["f", 0.0, 1.0, 0.5]],
	"lash_curl": ["Natočení řas", ["f", 0.0, 1.0, 0.5]],
	"teeth_shade": ["Odstín zubů", ["f", 0.0, 1.0, 0.25]],
	"teeth_gap": ["Mezera mezi předními zuby", ["f", 0.0, 1.0, 0.0]],
	"teeth_crooked": ["Nerovné zuby", ["f", 0.0, 1.0, 0.0]],
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
## Typ pleti (v7). Popisky pro editor; předvolba = typické [oiliness, dryness] (editor je nastaví při volbě typu,
## hráč je pak může doladit – obě osy zůstávají nezávislé). Randomizér losuje kolem předvoleb.
const SKIN_TYPES := {"normal": "Normální", "dry": "Suchá", "combination": "Smíšená", "oily": "Mastná"}
const SKIN_TYPE_PRESETS := {"normal": [0.35, 0.25], "dry": [0.15, 0.65], "combination": [0.6, 0.4], "oily": [0.75, 0.12]}

const OUTFIT_CATEGORIES := {
	"bezne": "Běžné", "pracovni": "Pracovní", "spolecenske": "Společenské", "spani": "Na spaní", "sport": "Sport",
}
## Oblečení není vázané na tělo ani identitu – každý kus jde na kohokoli.
const TOPS := {
	"zadne": "Bez vrchního dílu (anatomie)", "tricko": "Tričko", "tilko": "Tílko", "kosile": "Košile", "halenka": "Halenka", "svetr": "Svetr", "rolak": "Rolák",
	"mikina": "Mikina", "sako": "Sako s košilí", "saty": "Šaty", "pyzamo": "Pyžamo", "sportovni": "Sportovní tričko",
	"punk_vesta": "Punková vesta", "metal_tricko": "Metalové tričko", "emo_mikina": "Emo mikina",
	"goth_korset": "Goth korzet", "kawaii_svetr": "Kawaii svetr", "harajuku_bunda": "Harajuku bunda",
	"grunge_kosile": "Grunge košile", "visualkei_sako": "Visual kei sako",
	"kawaii_kocici_mikina": "Růžová kawaii mikina s kočičíma ušima",
}
const BOTTOMS := {
	"dziny": "Džíny", "kalhoty": "Kalhoty", "oblekove": "Oblekové kalhoty", "kratasy": "Kraťasy", "sukne": "Sukně",
	"teplaky": "Tepláky", "leginy": "Legíny", "pyzamo": "Pyžamové kalhoty", "zadne": "— (šaty)",
	"punk_kostka": "Punková kostkovaná sukně", "goth_sukne": "Goth dlouhá sukně",
	"kawaii_sukne": "Kawaii skládaná sukně", "harajuku_sukne": "Harajuku sukně",
	"metal_dziny": "Metalové džíny", "emo_dziny": "Emo džíny", "grunge_dziny": "Grunge džíny",
	"visualkei_kalhoty": "Visual kei kalhoty",
}
const SHOES := {
	"tenisky": "Tenisky", "polobotky": "Polobotky", "kozacky": "Kozačky", "lodicky": "Lodičky", "sandaly": "Sandály",
	"pracovni": "Pracovní boty", "bacory": "Bačkory", "bosy": "Naboso",
	"punk_kanady": "Punkové kanady", "metal_kanady": "Metalové kanady",
	"goth_platformy": "Goth platformy", "emo_tenisky": "Emo tenisky",
	"kawaii_boty": "Kawaii boty", "harajuku_platformy": "Harajuku platformy",
	"grunge_kanady": "Grunge kanady", "visualkei_boty": "Visual kei boty",
}

## Osobnost – 6 os (HEXACO-like, −1..1): nízký pól ↔ vysoký pól. Rysy jsou předvolby nad nimi (PsycheModel.TRAIT_P).
const HEXACO := {
	"honesty": "Poctivost", "emotionality": "Emocionalita", "extraversion": "Extraverze",
	"agreeableness": "Přívětivost", "conscientiousness": "Svědomitost", "openness": "Otevřenost",
}

## Each traditional trait is an independent 0..1 slider. The old trait budget applies to legacy presets only.
const TRAIT_SLIDERS := {
	"lenoch": "Lenost", "aktivni": "Aktivita", "pedant": "Pořádkumilovnost",
	"spolecensky": "Společenskost", "samotar": "Potřeba samoty", "gurman": "Gurmánství",
	"hravy": "Hravost", "knihomol": "Záliba ve čtení", "optimista": "Optimismus",
	"brucoun": "Podrážděnost", "zarlivy": "Žárlivost", "vznetlivy": "Vznětlivost",
	"cynik": "Cynismus", "impulzivni": "Impulzivita", "uzkostlivy": "Úzkostlivost",
}
## Optional enduring dimensions, not current symptoms or diagnostic labels.
const PSYCHE_SLIDERS := {
	"threat_sensitivity": "Citlivost na hrozby",
	"hypervigilance": "Hypervigilance (zvýšená ostražitost)",
	"social_threat": "Očekávání sociálního odmítnutí",
	"rejection_reactivity": "Emoční citlivost na odmítnutí",
	"impulsivity": "Impulzivní reagování",
	"regulation_capacity": "Schopnost regulace emocí",
	"predictability_need": "Potřeba předvídatelnosti",
	"sensory_sensitivity": "Hypersenzitivita (smyslová citlivost)",
	"energy_baseline": "Obvyklá energie",
	"reward_sensitivity": "Citlivost na odměnu a radost",
	"cognitive_flexibility": "Kognitivní flexibilita",
}

## Neurodivergentní profil (v9): každá osa je samostatný posuvník 0..1, 0 = bez výrazné odlišnosti. Nejde o
## diagnózu ani šablonu – dvě postavy se stejnou „nálepkou“ mají jiný profil. Silné stránky (hyperfokus,
## hloubka zájmů, přímost) jsou osy stejně jako obtíže. Potřeba předvídatelnosti a rutiny je už
## v dispositions.predictability_need (nezdvojuje se).
const NEURO_SLIDERS := {
	"attention_drift": "Těkavá pozornost",
	"working_memory": "Přetížení pracovní paměti",
	"task_initiation": "Obtížné zahájení úkolů",
	"action_impulsivity": "Impulzivní jednání (nejdřív udělat)",
	"hyperfocus": "Hyperfokus (silná stránka)",
	"time_blindness": "Časová slepota (vnímání času)",
	"sens_sound": "Citlivost na zvuky",
	"sens_light": "Citlivost na světlo",
	"sens_touch": "Citlivost na dotek a blízkost lidí",
	"social_energy": "Sociální vyčerpání (energie na lidi)",
	"interest_depth": "Hloubka zájmu (monotropní zájem, silná stránka)",
	"direct_communication": "Přímá a doslovná komunikace",
	"masking_cost": "Maskování – cena za přizpůsobování se",
	"tic_tendency": "Sklon k tikům",
	"reading_effort": "Čtení a psaní stojí víc úsilí",
}
## Schopnosti paměti (v10): 0,5 = průměr; chybějící osa = 0,5. Mění vyhasínání a jistotu vzpomínek o lidech.
const MEMORY_SLIDERS := {
	"retention": "Paměť: jak dlouho si věci pamatuje",
	"precision": "Paměť: jak přesně si vybaví, co se stalo",
	"emotional_weight": "Paměť: jak silně si nese emoce z minulých událostí",
}
## Průběh nálady (v11): predispozice, ne diagnóza. Typ „I / II / cyklotymie / dystymie“ vzniká kombinací os.
const MOOD_SLIDERS := {
	"bipolar_tendency": "Sklon k výkyvům nálady (epizody nahoru i dolů)",
	"elevation_ceiling": "Jak vysoko může zvýšená fáze vystoupat (hypomanie → mánie)",
	"cycling": "Rychlé a mělčí střídání nálad",
	"chronic_low": "Dlouhodobě nízká nálada (bez epizod)",
	"sleep_sensitivity": "Jak moc nálada reaguje na nedostatek spánku",
}
## Vnitřní hlas (v12): 0,5 = průměr. Myšlenky vznikají z událostí a stavu; posuvníky mění jen jejich sílu.
const THOUGHT_SLIDERS := {
	"rumination": "Sklon přemítat dokola (ruminace)",
	"worry": "Sklon k starostem o budoucnost",
	"hope": "Nadějné a vlídné myšlenky",
}
## Osobnostní akcenty (v13): konfigurovatelná osobnost se zvýrazněnými rysy, ne „přepínač poruchy“.
const ACCENT_SLIDERS := {
	"abandonment": "Citlivost na opuštění a emoční výkyvy",
	"suspicious": "Podezíravost a nedůvěra",
	"attention": "Potřeba pozornosti",
	"perfectionism": "Perfekcionismus a rigidita",
	"avoidance": "Vyhýbavost a zábrany (strach z kritiky)",
	"dependency": "Závislost na druhých",
	"grandiosity": "Grandiozita a potřeba obdivu",
	"detachment": "Odstup a citový chlad",
}
## Oblast hlubokého zájmu (hloubka zájmu je posuvník; tady jen kam směřuje).
const INTEREST_FOCUS := {
	"reading": "Knihy a texty", "cooking": "Vaření", "exercise": "Pohyb a sport",
	"screens": "Filmy, seriály a hry", "nature": "Procházky a příroda",
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
	"ocd": {"label": "Obsedantně-kompulzivní porucha", "content": "mental_health",
		"effects": "Vtíravá pochybnost a nutkavá činnost s krátkou úlevou; smyčku zmírňuje postupné odolávání nutkání a opora."},
	"addiction": {"label": "Sklon k závislosti", "content": "mental_health",
		"effects": "Návyk na látky nebo činnosti vzniká rychleji a chuť se vrací se stresem; pomáhá opora, omezení a odborná pomoc."},
	"social_anxiety": {"label": "Sociální úzkostná porucha", "content": "mental_health",
		"effects": "Strach z posuzování a odmítnutí, napětí před setkáním a přehrávání rozhovorů; pomáhá zkušenost, že to šlo, a blízcí lidé."},
}
## Zvyk na návykové látky a činnosti (v15) – herní kategorie s obecnými jmény (Mlha, Jiskra, Útlum).
const SUBSTANCE_SLIDERS := {
	"caffeine": "Zvyk: káva", "nicotine": "Zvyk: cigarety", "alcohol": "Zvyk: alkohol",
	"sedative": "Zvyk: Mlha (tlumivá látka)", "stimulant": "Zvyk: Jiskra (povzbuzující látka)",
	"painkiller": "Zvyk: Útlum (tlumivý lék proti bolesti)", "gaming": "Zvyk: hraní her", "gambling": "Zvyk: sázení",
}
## Téma obsedantní pochybnosti (v14).
const OCD_THEMES := {"checking": "Kontrolování (sporák, dveře)", "contamination": "Čistota a znečištění",
	"order": "Pořádek a souměrnost"}
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
		"sexual_attracted_to": ["set", ATTRACTION, 3],  # independent of romantic attraction
		"libido": ["f", 0.0, 1.0, 0.5],  # independent of asexuality
		"drive_dysregulation": ["f", 0.0, 1.0, 0.0], # non-diagnostic preoccupation
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
		"neck_length": ["f", -1.0, 1.0, 0.0],   # délka krku (±15 mm ≈ ±17 %), nezávislá na výšce, rodu i identitě
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
		"type": ["e", SKIN_TYPES, "normal"],    # v7: kde se projeví maz a suchost (T-zóna / tváře / tělo)
		"oiliness": ["f", 0.0, 1.0, 0.35],      # v7: maz → lesk a větší póry (hlavně T-zóna)
		"dryness": ["f", 0.0, 1.0, 0.25],       # v7: suchost → matnost, mikroreliéf, u velmi suché šupinky
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
		"mascara": ["f", 0.0, 1.0, 0.0],
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
		"traits": ["traits"], # legacy presets; ignored when trait_levels is populated
		"trait_levels": ["axes", TRAIT_SLIDERS, 0.0, 1.0], # private scalar intensities
		"aspirations": ["set", ASPIRATIONS, MAX_ASPIRATIONS],
		"hexaco": ["axes", HEXACO, -1.0, 1.0],          # soukromé; {} = vše z rysů
		"psyche_seed": ["i", 0, 65535, 0],             # soukromé; individualita psychiky (PsycheModel)
	}},
	"story": {"fields": {
		"family": ["e", FAMILY, "neuvedeno"],
		"childhood": ["e", CHILDHOOD, "neuvedeno"],
		"past_work": ["set", PAST_WORK, MAX_PAST_WORK],
		"hometown": ["text", 40],
		"backstory": ["text", 600, true],
	}},
	"mind": {"content": "mental_health", "fields": {
		## Stable private belief, not a transient emotion, diagnosis or visible mood meter.
		"self_defectiveness": ["f", 0.0, 1.0, 0.0],
		"predispositions": ["predisp"], # 0..1 per condition; already continuous
		"dispositions": ["axes", PSYCHE_SLIDERS, 0.0, 1.0],
		"neuro": ["axes", NEURO_SLIDERS, 0.0, 1.0],        # v9: neurodivergentní profil (0 = bez odlišnosti)
		"interest_focus": ["e", INTEREST_FOCUS, "reading"], # v9: kam směřuje hluboký zájem
		"memory": ["axes", MEMORY_SLIDERS, 0.0, 1.0],      # v10: schopnosti paměti (0,5 = průměr)
		"mood": ["axes", MOOD_SLIDERS, 0.0, 1.0],          # v11: průběh nálady (0 = bez sklonu)
		"thoughts": ["axes", THOUGHT_SLIDERS, 0.0, 1.0],   # v12: styl vnitřního hlasu (0,5 = průměr)
		"accents": ["axes", ACCENT_SLIDERS, 0.0, 1.0],     # v13: osobnostní akcenty (0 = bez akcentu)
		"accent_labels": ["b", false],                     # v13: ukazovat soukromě i výkladový název
		"ocd_theme": ["e", OCD_THEMES, "checking"],         # v14: čeho se obsedantní pochybnost týká
		"substances": ["axes", SUBSTANCE_SLIDERS, 0.0, 1.0], # v15: zvyk na látky a činnosti (0 = žádný)
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


## Pole skupiny face se skládají z několika tabulek; složený slovník je v cache (volá se na každý posuvník několikrát –
## validátor, snapshot, FaceMorphs). Je jen pro čtení (make_read_only), takže ho volající nemůže omylem změnit.
static var _face_fields_cache: Dictionary = {}


static func fields(group: String) -> Dictionary:
	if group == "face":
		if not _face_fields_cache.is_empty():
			return _face_fields_cache
		var f := {}
		for k in FACE_MORPHS:
			f[k] = ["f", -1.0, 1.0, 0.0]
		f["chin_cleft"] = ["f", 0.0, 1.0, 0.0]   # důlek v bradě nemá „záporný“ směr
		for k in FACE_ASYMMETRY:
			f[k] = ["f", -1.0, 1.0, 0.0]
		for k in FACE_DETAILS:
			f[k] = (FACE_DETAILS[k][1] as Array).duplicate()
		for k in f:
			(f[k] as Array).make_read_only()
		f.make_read_only()
		_face_fields_cache = f
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
		"predisp", "axes":
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