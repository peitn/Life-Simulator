extends RefCounted
## Katalog akcí. Každá akce je inzerována objektem (`object` = tag chytrého objektu),
## jinou postavou (`object` = "sim") nebo je dostupná kdekoli (`object` = "").
##
## Klíče:
##   effects     – celková změna potřeb za celou akci (rozpočítá se po minutách)
##   rate        – změna potřeb za herní hodinu (pro akce s proměnnou délkou)
##   until_full  – akce končí, když daná potřeba dosáhne maxima
##   suppress    – faktor úbytku potřeb během akce (spánek zpomalí hlad…)
##   posture     – stand / sit / lie (vizuální poloha + lokace)
##   interruptible – lze přerušit (kritickou potřebou nebo pozváním k hovoru)
##   moodlet     – [id, popisek, emoce, síla, trvání v min] po dokončení
##   sound       – smyčka z res://audio/sfx přehrávaná 3D u objektu během akce
##   memory      – zápis do paměti, pokud byl zážitek dost silný (moodlet × rysy ≥ 14)
##   player_only – akci si AI sama nevybere, jen na příkaz hráče
##   forced_outcome – "negative" = sociální interakce vždy skončí konfliktem
##   coping      – id copingu v MentalState.COPINGS (účinek na stres/úzkost po dokončení)
##   usable_in_panic – hráč ji může zadat i během panické ataky (přeruší ji)
##   involuntary – mimovolný stav (panická ataka): AI ani hráč ji nevybírá, spouští ji simulace
##   approach_only – jde za postavou, která je zaneprázdněná (pomoc při atace), bez hovoru
##   content     – obsahový štítek pro nastavení (addiction, mental_health…)
##   leisure     – coping, který se dělá i bez stresu jako běžná zábava (procházka, scrollování)
##   effort      – námaha ZAČÍT (0..1); bez klíče se odvodí z tagů (viz effort()). V depresi
##                 roste bariéra iniciace úměrně námaze – akce se nezakáže, jen „stojí víc“.
##   system      – interní stav (váhání „nemůže se dokopat“): AI ani hráč ji nezadává

const ACTIONS: Array = [
	{
		"id": "snack", "label": "Dává si svačinu", "object": "fridge", "duration": 15.0,
		"effects": {"hunger": 24.0}, "tags": ["food", "solo"], "posture": "stand",
	},
	{
		"id": "cook", "label": "Vaří jídlo", "object": "stove", "duration": 55.0,
		"effects": {"hunger": 72.0, "fun": 6.0}, "tags": ["food", "cooking", "solo"], "posture": "stand", "sound": "sfx_stove",
		"moodlet": ["dobre_najedeny", "Dobře najedený", "stastny", 10.0, 240.0],
		"memory": "Uvařil(a) si výborné jídlo",
	},
	{
		"id": "sleep", "label": "Spí", "object": "bed", "duration": 600.0,
		"rate": {"energy": 13.0, "comfort": 8.0}, "until_full": "energy",
		"suppress": {"energy": 0.0, "comfort": 0.0, "hunger": 0.45, "fun": 0.15, "social": 0.15, "hygiene": 0.5},
		"tags": ["sleep", "rest", "solo"], "posture": "lie", "interruptible": false, "effort": 0.0,
		"moodlet": ["vyspany", "Vyspaný do růžova", "energicky", 10.0, 180.0],
	},
	{
		"id": "sleep_sofa", "label": "Spí na gauči", "object": "sofa", "duration": 480.0,
		"rate": {"energy": 9.5, "comfort": 2.0}, "until_full": "energy",
		"suppress": {"energy": 0.0, "comfort": 0.0, "hunger": 0.45, "fun": 0.15, "social": 0.15, "hygiene": 0.5},
		"tags": ["sleep", "rest", "solo"], "posture": "lie", "interruptible": false,
		"base_appeal": -6.0,
		"moodlet": ["bolava_zada", "Bolí ho záda z gauče", "nesvuj", -8.0, 240.0],
	},
	# Nouzový spánek, když jsou postele i gauč obsazené (plná domácnost): kdekoli v křesle nebo na zemi.
	# Horší než gauč, ale lepší než nespat vůbec – bez něj zůstane někdo v přeplněném bytě celé noci vzhůru.
	{
		"id": "sleep_floor", "label": "Spí v křesle", "object": "", "duration": 420.0,
		"rate": {"energy": 7.0, "comfort": 0.0}, "until_full": "energy",
		"suppress": {"energy": 0.0, "comfort": 0.6, "hunger": 0.45, "fun": 0.15, "social": 0.15, "hygiene": 0.5},
		"tags": ["sleep", "rest", "solo"], "posture": "sit", "interruptible": false,
		"base_appeal": -10.0,
		"moodlet": ["prolezeny", "Celá rozlámaná z křesla", "nesvuj", -10.0, 300.0],
	},
	{
		"id": "nap", "label": "Zdřímne si", "object": "bed", "duration": 45.0,
		"effects": {"energy": 14.0, "comfort": 6.0},
		"suppress": {"energy": 0.0, "comfort": 0.0},
		"tags": ["rest", "solo"], "posture": "lie",
	},
	{
		"id": "shower", "label": "Sprchuje se", "object": "shower", "duration": 20.0,
		"effects": {"hygiene": 78.0, "comfort": 6.0}, "tags": ["hygiene", "solo"], "posture": "stand", "sound": "sfx_shower",
		"interruptible": false,
		"moodlet": ["svezi", "Svěží po sprše", "energicky", 7.0, 120.0],
	},
	{
		"id": "watch_tv", "label": "Kouká na televizi", "object": "tv", "duration": 60.0,
		"effects": {"fun": 32.0, "comfort": 14.0}, "tags": ["fun", "rest", "solo"], "posture": "sit", "sound": "sfx_tv",
		"effort": 0.1,
	},
	{
		"id": "relax", "label": "Odpočívá na gauči", "object": "sofa", "duration": 30.0,
		"effects": {"comfort": 42.0, "energy": 4.0}, "tags": ["rest", "quiet", "solo"], "posture": "sit",
	},
	{
		"id": "read", "label": "Čte knihu", "object": "bookshelf", "duration": 50.0,
		"effects": {"fun": 22.0, "comfort": 8.0}, "tags": ["reading", "quiet", "fun", "solo"], "posture": "stand",
		"moodlet": ["zabrany", "Zabraný do knihy", "soustredeny", 8.0, 90.0],
	},
	{
		"id": "workout", "label": "Cvičí na běžeckém pásu", "object": "treadmill", "duration": 45.0,
		"effects": {"fun": 16.0, "hygiene": -22.0, "energy": -14.0, "comfort": -8.0},
		"tags": ["exercise", "fun", "solo"], "posture": "stand", "sound": "sfx_treadmill",
		"moodlet": ["endorfiny", "Příval endorfinů", "energicky", 14.0, 150.0],
		"memory": "Dal(a) si pořádný trénink",
	},
	{
		"id": "chat", "label": "Povídá si", "object": "sim", "duration": 30.0,
		"effects": {"social": 32.0, "fun": 8.0}, "tags": ["social"], "posture": "stand",
	},
	{
		"id": "insult", "label": "Uráží", "object": "sim", "duration": 12.0,
		"effects": {"social": 4.0}, "tags": ["social", "mean"], "posture": "stand",
		"player_only": true, "forced_outcome": "negative",
	},
	{
		"id": "text_friend", "label": "Píše si s kamarádem", "object": "", "duration": 20.0,
		"effects": {"social": 12.0, "fun": 3.0}, "tags": ["social", "solo"], "posture": "stand",
		"base_appeal": 0.5, "effort": 0.2,  # napsat zprávu je snazší než jít mezi lidi
	},
	{
		"id": "daydream", "label": "Sní s otevřenýma očima", "object": "", "duration": 15.0,
		"effects": {"fun": 4.0, "comfort": 3.0}, "tags": ["quiet", "solo"], "posture": "stand",
		"base_appeal": 0.3,
	},
	# --- zvládání stresu a úzkosti (zdravé i nezdravé copingy, žádný není nejlepší ve všem)
	{
		"id": "breathe", "label": "Dechové cvičení", "object": "", "duration": 10.0,
		"effects": {"comfort": 3.0}, "tags": ["coping", "quiet", "solo"], "posture": "stand",
		"coping": "breathe", "usable_in_panic": true, "base_appeal": 0.0, "effort": 0.1,
	},
	{
		"id": "go_walk", "label": "Jde se projít", "object": "", "duration": 40.0,
		"effects": {"fun": 8.0, "energy": -6.0, "comfort": -2.0}, "tags": ["coping", "solo"], "posture": "stand",
		"coping": "walk", "base_appeal": 0.0, "leisure": true, "effort": 0.6,
	},
	{
		"id": "journal", "label": "Píše si deník", "object": "", "duration": 25.0,
		"effects": {"comfort": 4.0}, "tags": ["coping", "quiet", "solo"], "posture": "stand",
		"coping": "journal", "base_appeal": 0.0, "effort": 0.35,
	},
	{
		"id": "confide", "label": "Svěřuje se", "object": "sim", "duration": 35.0,
		"effects": {"social": 20.0}, "tags": ["social", "coping"], "posture": "stand",
		"coping": "confide", "usable_in_panic": true, "base_appeal": 0.0, "effort": 0.6,
	},
	{
		"id": "doomscroll", "label": "Bezmyšlenkovitě scrolluje", "object": "", "duration": 30.0,
		"effects": {"fun": 7.0, "energy": -3.0}, "tags": ["coping", "coping_unhealthy", "solo"], "posture": "stand",
		"coping": "doomscroll", "base_appeal": 0.0, "leisure": true, "effort": 0.0,
	},
	{
		"id": "hide", "label": "Schovává se pod peřinou", "object": "bed", "duration": 60.0,
		"effects": {"comfort": 10.0}, "suppress": {"social": 1.3, "fun": 1.2},
		"tags": ["coping", "coping_unhealthy", "quiet", "solo"], "posture": "lie",
		"coping": "hide", "base_appeal": 0.0, "effort": 0.0,
	},
	{
		"id": "drink", "label": "Dává si pivo na nervy", "object": "fridge", "duration": 15.0,
		"effects": {"hunger": 4.0, "fun": 6.0}, "tags": ["coping", "coping_unhealthy", "alcohol", "solo"],
		"posture": "stand", "coping": "drink", "base_appeal": 0.0, "content": "addiction", "effort": 0.1,
	},
	# --- vztahy: cesta zpět z konfliktu
	{
		"id": "apologize", "label": "Omlouvá se", "object": "sim", "duration": 15.0,
		"effects": {"social": 6.0}, "tags": ["social", "repair"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.6,
	},
	# --- mimovolné stavy a pomoc druhým
	{
		"id": "panic", "label": "Panická ataka", "object": "", "duration": 25.0,
		"effects": {}, "tags": ["involuntary"], "posture": "stand", "interruptible": false,
		"involuntary": true, "content": "mental_health",
	},
	{
		"id": "comfort_panic", "label": "Uklidňuje", "object": "sim", "duration": 15.0,
		"effects": {"social": 8.0}, "tags": ["social", "support"], "posture": "stand",
		"approach_only": true, "player_only": true, "content": "mental_health",
	},
	# Váhání před příkazem hráče v depresi (bariéra iniciace) – zrušitelné, nikdy neodmítne příkaz.
	{
		"id": "hesitate", "label": "Nemůže se dokopat", "object": "", "duration": 10.0,
		"effects": {}, "tags": ["system"], "posture": "stand", "system": true, "effort": 0.0,
		"content": "mental_health",
	},
]

## Výchozí námaha podle tagů (když akce nemá klíč `effort`). Bere se maximum.
const TAG_EFFORT := {"exercise": 0.9, "cooking": 0.6, "hygiene": 0.5, "social": 0.5, "reading": 0.3,
	"coping": 0.3, "fun": 0.2, "food": 0.15}
## Kolik z kladného zisku zábavy se počítá do očekávané radosti (vedle moodletu).
const FUN_HEDONIC := 0.15

## Repliky do bublin. Dospělý tón – sprostá mluva patří k hádkám, ne k zábavě na něčí účet
## (žádné nadávky cílené na skutečné skupiny lidí).
const LINES := {
	"insult": [
		"Ty seš fakt kretén, víš to?",
		"Kurva, nech mě bejt.",
		"Jsi úplně k ničemu.",
		"Táhni do prdele.",
		"Každej den s tebou je za trest.",
		"Ani nádobí neumyješ, ty vole.",
	],
	"argue": [
		"To si děláš prdel?",
		"Neřvi na mě!",
		"Vždycky je to jenom o tobě.",
		"Sakra, poslouchej mě aspoň jednou.",
		"Tohle už fakt nesnesu.",
	],
	"insulted": [
		"Cože jsi to řekl(a)?!",
		"Tohle si pamatovat budu.",
		"Jdi do háje.",
		"…to bolelo.",
	],
	"panic": [
		"Nemůžu… dýchat…",
		"Ne, ne, ne…",
		"Musím ven. Hned.",
		"Co se to se mnou děje?",
	],
	## Stigma – hra ho ukazuje jako ubližující (důsledky pro vztah), ne jako vtip.
	"stigma": [
		"Zase děláš scény?",
		"Prostě se seber, vždyť se nic neděje.",
		"Tohle je jen v tvý hlavě.",
		"Uklidni se, sakra, lidi koukaj.",
	],
	"support": [
		"Jsem tady. Dýchej se mnou.",
		"Nic se ti nestane. Počkám tu.",
		"To přejde. Nikam nespěchej.",
	],
	"confide_ok": [
		"Děkuju, že mi to říkáš.",
		"To zní fakt těžce. Jsem tu.",
		"Pojď sem. Zvládneme to spolu.",
	],
	"confide_dismiss": [
		"Ty to fakt přeháníš.",
		"Každej má problémy, ne?",
		"Prostě na to nemysli.",
	],
	"jealous": [
		"Hm. Vy dva si nějak rozumíte, co?",
		"Se mnou se takhle nebavíš.",
	],
	## Omluva – (a) = rod toho, kdo se omlouvá.
	"apology": [
		"Hele… promiň. Přehnal(a) jsem to.",
		"Je mi to líto. Fakt.",
		"Byl(a) jsem kretén. Promiň mi to.",
		"Nechci, aby to mezi náma takhle bylo.",
	],
	## Reakce na omluvu – (a) = rod toho, kdo se omlouval.
	"apology_accept": [
		"Dobře. Zapomeňme na to.",
		"Díky, že jsi to řekl(a).",
		"Tak jo. Pojď sem.",
	],
	"apology_partial": [
		"Uvidíme.",
		"Hm. Tak jo… asi.",
		"Slova jsou levný. Ukaž to.",
	],
	"apology_reject": [
		"Na to ti seru.",
		"Teď ne. Fakt ne.",
		"Omluvy si strč někam.",
		"To nespravíš jedním promiň.",
	],
	"apology_spam": [
		"Zase? Přestaň s tím.",
		"Už jsi to říkal(a). Nech toho.",
	],
	"apology_none": [
		"Za co? V pohodě.",
		"Nic se nestalo, fakt.",
	],
	"hesitate": [
		"Hned… jen ještě chvilku.",
		"Za chvíli. Fakt.",
	],
	## Stížnosti z domácnosti (HouseholdDynamics) – tón oslovení, (a) = rod mluvčího.
	"complaint_noise": [
		"Můžeš se ztišit? Já se tu snažím spát, sakra.",
		"Víš, kolik je hodin? Někdo tu spí!",
	],
	"complaint_bathroom": [
		"Jak dlouho tam ještě budeš? Taky se potřebuju umýt!",
		"Koupelna není tvoje soukromá lázeň, hergot.",
	],
	"complaint_dishes": [
		"Kdo zase nechal špinavý nádobí na lince? Nejsem tvoje služka.",
		"Ten bordel po vaření se sám neumyje, víš?",
	],
	## Stížnost přijatá v klidu.
	"complaint_ok": [
		"Jo, promiň. Hned to udělám.",
		"Máš pravdu, sorry. Nevšiml(a) jsem si.",
	],
	## De-eskalace: posluchač v dobré náladě ostrý tón přejde.
	"deescalate": [
		"Hele, nechme toho. Nemá cenu se hádat.",
		"Dobře, chápu. Dneska je toho na tebe moc, co?",
		"Klid. Pojďme to probrat normálně.",
	],
}


static func get_action(id: String) -> Dictionary:
	for a in ACTIONS:
		if a["id"] == id:
			return a
	return {}


## Námaha akci začít (0..1).
static func effort(a: Dictionary) -> float:
	if a.has("effort"):
		return clampf(float(a["effort"]), 0.0, 1.0)
	var e := 0.0
	for t in a.get("tags", []):
		e = maxf(e, float(TAG_EFFORT.get(t, 0.0)))
	return e


## Nominální radost z akce (bez deprese, bez povahy): kladný moodlet + část zisku zábavy.
static func hedonic_prior(a: Dictionary) -> float:
	var p := 0.0
	var ml: Array = a.get("moodlet", [])
	if ml.size() == 5 and float(ml[3]) > 0.0:
		p += float(ml[3])
	var fun := float(a.get("effects", {}).get("fun", 0.0))
	if fun > 0.0:
		p += fun * FUN_HEDONIC
	return p


static func random_line(kind: String, rng: RandomNumberGenerator) -> String:
	var arr: Array = LINES.get(kind, [])
	if arr.is_empty():
		return ""
	return String(arr[rng.randi_range(0, arr.size() - 1)])
