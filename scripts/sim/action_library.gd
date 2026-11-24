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
	# Difficult communication can damage trust; abuse never improves intimacy consent.
	{"id": "reproach", "label": "Vyčítá", "object": "sim", "duration": 15.0,
		"effects": {"social": 2.0}, "tags": ["social", "pressure"], "pressure_kind": "reproach", "base_appeal": 0.3},
	{"id": "guilt_trip", "label": "Vyvolává vinu", "object": "sim", "duration": 15.0,
		"effects": {}, "tags": ["social", "pressure"], "pressure_kind": "guilt_trip", "base_appeal": 0.05},
	{"id": "blame_shift", "label": "Přehazuje odpovědnost", "object": "sim", "duration": 15.0,
		"effects": {}, "tags": ["social", "pressure"], "pressure_kind": "blame_shift", "base_appeal": 0.02},
	{"id": "emotional_blackmail", "label": "Citově vydírá", "object": "sim", "duration": 15.0,
		"effects": {}, "tags": ["social", "pressure"], "pressure_kind": "emotional_blackmail", "base_appeal": 0.0},
	{"id": "stonewalling", "label": "Odmítá komunikovat", "object": "sim", "duration": 12.0,
		"effects": {}, "tags": ["social", "pressure"], "pressure_kind": "stonewalling", "base_appeal": 0.3},
	# Private, consensual, adult-only encounter: two independent offers before action.
	{"id": "intimacy_offer", "label": "Projeví zájem o intimitu", "object": "sim", "duration": 0.0,
		"effects": {}, "tags": ["intimacy"], "content": "adult_intimacy", "player_only": true, "special": true},
	{"id": "intimacy_withdraw", "label": "Odvolá souhlas", "object": "sim", "duration": 0.0,
		"effects": {}, "tags": ["intimacy"], "content": "adult_intimacy", "player_only": true, "special": true},
	{"id": "adult_consensual_sex", "label": "Stráví intimní chvíli (mimo záběr)", "object": "sim", "duration": 45.0,
		"effects": {}, "tags": ["intimacy", "social"], "posture": "stand", "content": "adult_intimacy",
		"interruptible": true, "private_presentation": "fade_to_black", "player_only": true},
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
	# OCD (psychika E): nutkavá činnost (AI jen s obsesí; popisek podle tématu) a odolání nutkání.
	{
		"id": "compulsion", "label": "Nutkavě něco kontroluje", "object": "", "duration": 12.0,
		"effects": {}, "tags": ["compulsion", "solo"], "posture": "stand",
		"base_appeal": 4.0, "effort": 0.0, "content": "mental_health", "psyche_gate": "ocd_ritual",
	},
	{
		"id": "resist_urge", "label": "Odolává nutkání", "object": "", "duration": 20.0,
		"effects": {"comfort": -2.0}, "tags": ["coping", "quiet", "solo"], "posture": "stand",
		"base_appeal": 1.0, "effort": 0.4, "content": "mental_health", "psyche_gate": "ocd_resist",
	},
	# Návykové látky a činnosti (psychika F): obecné herní kategorie, žádné dávky ani způsob užití. AI je volí
	# jen se zvykem nebo chutí (psyche_gate); hráč je může zadat, je-li povolen obsah „závislosti“.
	{"id": "use_caffeine", "label": "Dá si kávu", "object": "", "duration": 10.0, "effects": {"energy": 6.0, "fun": 2.0},
		"tags": ["substance", "solo"], "posture": "stand", "base_appeal": 3.0, "effort": 0.1, "content": "addiction",
		"substance": "caffeine", "psyche_gate": "substance:caffeine"},
	{"id": "use_nicotine", "label": "Dá si cigaretu", "object": "", "duration": 8.0, "effects": {"comfort": 2.0},
		"tags": ["substance", "solo"], "posture": "stand", "base_appeal": 3.0, "effort": 0.0, "content": "addiction",
		"substance": "nicotine", "psyche_gate": "substance:nicotine"},
	{"id": "use_sedative", "label": "Užije Mlhu", "object": "", "duration": 20.0, "effects": {"comfort": 8.0, "fun": 4.0, "energy": -4.0},
		"tags": ["substance", "solo"], "posture": "stand", "base_appeal": 3.0, "effort": 0.0, "content": "addiction",
		"substance": "sedative", "psyche_gate": "substance:sedative"},
	{"id": "use_stimulant", "label": "Užije Jiskru", "object": "", "duration": 10.0, "effects": {"energy": 12.0, "fun": 6.0},
		"tags": ["substance", "solo"], "posture": "stand", "base_appeal": 3.0, "effort": 0.0, "content": "addiction",
		"substance": "stimulant", "psyche_gate": "substance:stimulant"},
	{"id": "use_painkiller", "label": "Užije Útlum", "object": "", "duration": 10.0, "effects": {"comfort": 12.0},
		"tags": ["substance", "solo"], "posture": "stand", "base_appeal": 3.0, "effort": 0.0, "content": "addiction",
		"substance": "painkiller", "psyche_gate": "substance:painkiller"},
	{"id": "play_games", "label": "Hraje hry", "object": "", "duration": 60.0, "effects": {"fun": 26.0, "energy": -3.0},
		"tags": ["fun", "screen", "solo"], "posture": "sit", "base_appeal": 1.0, "effort": 0.1, "content": "addiction",
		"substance": "gaming", "psyche_gate": "substance:gaming"},
	{"id": "gamble", "label": "Sází online", "object": "", "duration": 30.0, "effects": {"fun": 10.0},
		"tags": ["fun", "solo"], "posture": "stand", "base_appeal": 1.0, "effort": 0.0, "content": "addiction",
		"substance": "gambling", "psyche_gate": "substance:gambling"},
	{"id": "cut_down", "label": "Rozhodne se to omezit", "object": "", "duration": 10.0, "effects": {"comfort": -1.0},
		"tags": ["coping", "quiet", "solo"], "posture": "stand", "base_appeal": 2.0, "effort": 0.4, "content": "addiction",
		"psyche_gate": "cut_down"},
	# Vyhledat odbornou pomoc (linka, poradna, terapie – mimo záběr). Hráč ji může zadat vždy; AI jen
	# s důvodem (psyche_gate: ruminace, beznaděj, později závislost či psychotické prožívání).
	{
		"id": "seek_help", "label": "Vyhledá odbornou pomoc", "object": "", "duration": 30.0,
		"effects": {"comfort": 4.0}, "tags": ["coping", "support_seeking", "solo"], "posture": "stand",
		"coping": "seek_help", "base_appeal": 0.0, "effort": 0.3, "content": "mental_health", "psyche_gate": "help",
	},
	# --- vztahy: cesta zpět z konfliktu
	{
		"id": "apologize", "label": "Omlouvá se", "object": "sim", "duration": 15.0,
		"effects": {"social": 6.0}, "tags": ["social", "repair"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.6,
	},
	# --- dusno / studená válka: vyříkat si to (může to i vybuchnout; ColdWar + SimAgent._start_clear_air)
	{
		"id": "clear_air", "label": "Chce si to vyříkat", "object": "sim", "duration": 25.0,
		"effects": {"social": 4.0}, "tags": ["social", "repair", "conflict"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.8,
	},
	# --- romantické vztahy (Romance + SimAgent._start_romance): pozvat na rande, rozejít se.
	# Ne „flirt jako minihra“: odpověď závisí na vztahu, důvěře, náladě a přitažlivosti cíle; košem se dostává.
	{
		"id": "ask_out", "label": "Zve na rande", "object": "sim", "duration": 20.0,
		"effects": {"social": 6.0, "fun": 2.0}, "tags": ["social", "romance"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.8,
	},
	{
		"id": "break_up", "label": "Rozchází se", "object": "sim", "duration": 25.0,
		"effects": {"social": 2.0, "fun": -6.0}, "tags": ["social", "romance", "conflict"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.9,
	},
	# --- nevěra a žárlivost (Infidelity + SimAgent._start_flirt/_start_secret_date/_start_confront_cheating).
	# Flirt s vlastním partnerem je hezký; s cizím zakládá jiskru. Tajná schůzka je náznak (fade-to-black),
	# jen se zadaným a s jiskrou. Konfrontace jen s vlastním partnerem/partnerkou.
	{
		"id": "flirt", "label": "Flirtuje", "object": "sim", "duration": 12.0,
		"effects": {"social": 5.0, "fun": 4.0}, "tags": ["social", "romance"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.4,
	},
	{
		"id": "secret_date", "label": "Tajná schůzka", "object": "sim", "duration": 60.0,
		"effects": {"social": 10.0, "fun": 10.0, "energy": -5.0}, "tags": ["social", "romance", "secret"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.6,
	},
	{
		"id": "confront_cheating", "label": "Konfrontuje kvůli nevěře", "object": "sim", "duration": 25.0,
		"effects": {"social": 2.0, "fun": -6.0}, "tags": ["social", "romance", "conflict"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.85,
	},
	# --- rivalita (Rivalry + SimAgent._start_slander/_start_hatchet). Pomluva: cíl = POSLUCHAČ, soka vybírá
	# autorita (nejsilnější rivalita). Posluchač to může prokouknout a donést oběti. Hra pomluvu neodměňuje.
	{
		"id": "slander_rival", "label": "Pomlouvá soka", "object": "sim", "duration": 15.0,
		"effects": {"social": 3.0}, "tags": ["social", "conflict", "rivalry"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.5,
	},
	# Usmíření se sokem (oběma směry rivalita opadne, přibude respekt) – nebo odmítnutí.
	{
		"id": "bury_hatchet", "label": "Zakopává válečnou sekeru", "object": "sim", "duration": 20.0,
		"effects": {"social": 5.0}, "tags": ["social", "repair", "rivalry"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.8,
	},
	# --- drby: vyříkat si to se zdrojem (jen když postava ví, od koho řeči šly) a popřít je před druhými
	{
		"id": "confront_gossip", "label": "Vyříkává si drby", "object": "sim", "duration": 20.0,
		"effects": {"social": 2.0}, "tags": ["social", "conflict"], "posture": "stand",
		"base_appeal": 0.0, "effort": 0.7,
	},
	{
		"id": "deny_gossip", "label": "Popírá drby o sobě", "object": "sim", "duration": 15.0,
		"effects": {"social": 4.0}, "tags": ["social"], "posture": "stand",
		"player_only": true, "effort": 0.5,
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
		# --- práce (Career, K1, 24. 11. 2026). Směny jsou mimo parcelu: postava dojde na chodník a zmizí
		# („away“ – mimo všechny vzdálenostní kontroly), po směně se vrátí. AI si je nevybírá přes planner
		# (player_only) – do práce ji posílá Career.ai_choice podle rozvrhu oboru. Blokace (rozvrh, nemocenská,
		# souboj o povýšení) řeší server přes main.career_command_block.
		{
			"id": "work_shift", "label": "V práci", "object": "", "duration": 480.0,
			"rate": {"hunger": 4.0, "social": 3.0}, "suppress": {"hygiene": 0.6, "comfort": 0.5, "fun": 1.1, "energy": 1.1},
			"tags": ["work"], "posture": "away", "interruptible": false, "player_only": true, "away": true,
			"career": true, "effort": 0.6,
		},
		{
			"id": "work_hard", "label": "V práci (maká naplno)", "object": "", "duration": 480.0,
			"rate": {"hunger": 4.0, "social": 2.0}, "suppress": {"hygiene": 0.7, "comfort": 0.5, "fun": 1.2, "energy": 1.3},
			"tags": ["work"], "posture": "away", "interruptible": false, "player_only": true, "away": true,
			"career": true, "effort": 0.8,
		},
		{
			"id": "work_slack", "label": "V práci (fláká se)", "object": "", "duration": 480.0,
			"rate": {"hunger": 4.0, "social": 4.0}, "suppress": {"hygiene": 0.5, "comfort": 0.4, "fun": 0.9, "energy": 0.9},
			"tags": ["work"], "posture": "away", "interruptible": false, "player_only": true, "away": true,
			"career": true, "effort": 0.4,
		},
		# Intrika proti konkurenci v souboji o povýšení (jen během souboje; může prasknout – výtka, oběť se to dozví).
		{
			"id": "work_scheme", "label": "V práci (intrikuje)", "object": "", "duration": 480.0,
			"rate": {"hunger": 4.0, "social": 3.0}, "suppress": {"hygiene": 0.6, "comfort": 0.5, "fun": 1.0, "energy": 1.15},
			"tags": ["work"], "posture": "away", "interruptible": false, "player_only": true, "away": true,
			"career": true, "effort": 0.6,
		},
		# Nemocenská (i kvůli psychice – důvod zůstává soukromý; šéf reaguje podle oboru: pochopení / stigma).
		{
			"id": "call_in_sick", "label": "Volá do práce, že dnes nepřijde", "object": "", "duration": 10.0,
			"effects": {}, "tags": ["work", "solo"], "posture": "stand", "player_only": true, "career": true, "effort": 0.1,
		},
		{
			"id": "job_search", "label": "Hledá práci (inzeráty, telefony)", "object": "", "duration": 90.0,
			"effects": {"fun": -6.0}, "tags": ["work", "solo"], "posture": "stand", "player_only": true, "career": true,
			"effort": 0.7,
		},
		{
			"id": "quit_job", "label": "Dává výpověď", "object": "", "duration": 15.0,
			"effects": {}, "tags": ["work", "solo"], "posture": "stand", "player_only": true, "career": true, "effort": 0.6,
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
	"reproach": ["Když se tohle opakuje, mrzí mě to.", "Přijde mi, že na to zůstávám sám/sama."],
	"guilt_trip": ["Po tom všem, co jsem pro tebe udělal(a)…", "Tohle mi snad vážně uděláš?"],
	"blame_shift": ["Já za to nemůžu, to ty.", "Kdybys neudělal(a) tamto, nic se nestalo."],
	"emotional_blackmail": ["Jestli ti na mně záleží, uděláš to, co chci.", "Když odmítneš, tak už se mnou nepočítej."],
	"stonewalling": ["O tom se prostě nebudu bavit.", "Nemám ti co říct."],
	"slander_blocked": ["Hele… vlastně nic. Zapomeň na to.", "Ale nic, to je jedno."],
	"slander_swayed": ["Fakt? Tak to bych neřekl(a)…", "No to mě poser. Tak to si dám bacha."],
	"slander_doubted": ["Hm. Nevím, nevím.", "To se mi moc nezdá, ale dobře."],
	# Posluchač je postava jiného hráče: o tom, zda uvěří, rozhodne hráč (SlanderPolicy) – replika je neutrální.
	"slander_pending": ["Hm. To si musím nechat projít hlavou.", "Jo? …No, uvidíme.", "Tohle se mi poslouchá blbě."],
	"slander_saw_through": ["Proč mi to vlastně říkáš? Máte spolu něco?", "Tohle je pod tvoji úroveň. Fakt.",
		"Víš co, tohle nechci poslouchat."],
	"hatchet": ["Hele… nechceme toho nechat? Ta válka mezi náma je k ničemu.", "Co kdybysme to zakopali? Já už nemám sílu."],
	"hatchet_accepted": ["…jo. Asi máš pravdu. Fajn.", "Dobře. Ale ber to vážně.", "Tak jo. Ruku na to."],
	"hatchet_refused": ["To si děláš srandu? Po tom všem?", "Ne. Na tohle je moc brzo.", "Jdi někam."],
	"hatchet_not_now": ["Dej mi pokoj. Už jsme to řešili.", "Ne. Ještě ne."],
	"hatchet_no_rivalry": ["Mezi náma přece nic není.", "Jakou válku? O čem to mluvíš?"],
	"clear_air": ["Hele, takhle to dál nejde. Musíme si promluvit.", "Můžeme si sednout a probrat to? Bez řvaní.",
		"Už tejden spolu skoro nemluvíme. Mě to sere."],
	"clear_air_breakthrough": ["…dobře. Taky mi to chybělo. Promiň.", "Máš pravdu, byl(a) jsem kretén. Zkusíme to znova.",
		"Uf. Fajn. Konečně."],
	"clear_air_truce": ["Dobře, příměří. Ale nečekej, že je to vyřešený.", "Tak jo. Zatím.", "Uvidíme. Dej mi čas."],
	"clear_air_blowup": ["Ty si ještě budeš něco vyčítat MNĚ? To si děláš prdel.", "Víš co? Seru na to. Na všechno.",
		"Takže zase já, jo? Jako vždycky!"],
	"clear_air_not_now": ["Teď ne. Fakt ne.", "Už jsme to dneska zkoušeli."],
	"clear_air_nothing": ["O co jde? Já nic nemám.", "Mezi námi je přece všechno v pohodě, ne?"],
	"ask_out": ["Hele… nechceš někdy zajít na víno? Jen my dva.", "Nebudu chodit kolem horký kaše – líbíš se mi.",
		"Nechceš se mnou jít na rande? Jako fakt rande."],
	"ask_out_yes": ["…jo. Jo, klidně. Myslel(a) jsem, že se nikdy nezeptáš.", "Ty vole, konečně. Jasně že jo.",
		"Tak jo. Ale platíš ty."],
	"ask_out_not_yet": ["Teď ne… ale neříkám nikdy.", "Dej mi trochu času, jo?", "Uvidíme. Fakt nevím."],
	"ask_out_no": ["Promiň, ale takhle to necítím.", "Jsi fajn, ale ne. Fakt ne.", "Radši zůstaneme kamarádi, jo?"],
	"ask_out_taken": ["Mám někoho. Víš to.", "Sorry, už s někým jsem."],
	"ask_out_pushy": ["Kolikrát ti to mám říkat? NE.", "Ty fakt neslyšíš? Nech toho, sakra.", "Už mě to začíná srát. Dej mi pokoj."],
	"ask_out_not_now": ["Teď ne. Už jsme to probírali.", "Dej tomu čas, jo?"],
	"ask_out_already": ["Vždyť spolu chodíme, ty trubko.", "To jako vážně? My dva už jsme spolu."],
	"break_up": ["Musím ti něco říct… takhle to dál nejde. Končím to.", "Nechci už s tebou bejt. Promiň.",
		"Je konec. Nezlob se, ale je konec."],
	"break_up_hurt": ["…cože? Ty si ze mě děláš srandu.", "To mi děláš teď? Fakt teď?", "Já… dobře. Asi jsem to čekal(a)."],
	"break_up_angry": ["Tak táhni. Seru na tebe.", "Víš co, ty hajzle? Stejně jsi za nic nestál(a).",
		"Celou dobu jsi mi lhal(a), že jo? Kurva."],
	"break_up_relief": ["Jo. Asi máš pravdu.", "Upřímně? Taky jsem na to myslel(a).", "Dobře. Bude to tak lepší."],
	"break_up_nothing": ["Rozejít? Vždyť spolu ani nechodíme.", "O čem to mluvíš?"],
	# Nevěra: (a) = rod mluvčího, pokud není u klíče uvedeno jinak.
	"flirt": ["Sluší ti to dneska. Fakt.", "Víš, že máš hezkej úsměv? Nekecám.", "Kdyby to šlo… no nic. Zapomeň na to."],
	"flirt_reciprocated": ["Hm… ty taky nejsi k zahození.", "Přestaň, nebo se začnu červenat.", "Jo? Tak mi to někdy řekni bez svědků."],
	"flirt_brushed_off": ["Haha. Jo. Dobře.", "Hele, nech toho, jo?", "Tohle radši ne."],
	"flirt_uncomfortable": ["Ehm… tohle je mi nepříjemný.", "Tak takhle ne. Fakt ne."],
	"flirt_own_partner": ["Ty jeden… pojď sem.", "Pořád to na mě funguje, víš to?", "Tak tohle mi říkej častějc."],
	"secret_date": ["Nikdo se to nesmí dozvědět, jasný?", "Vím o místě, kde nás nikdo nezná.", "Jen dneska. Naposled. Slibuju."],
	"secret_date_yes": ["…tohle je strašná blbost. Kdy?", "Jo. Ale nikdo se to nedozví."],
	"secret_date_no": ["Ne. Tohle neudělám.", "To jako vážně? Ne.", "Ty máš někoho. Ne."],
	"secret_date_blocked": ["Tajně? Proč tajně?", "O čem to mluvíš?", "Tohle radši ne."],
	## (a) = rod přistiženého.
	"caught": ["Co to sakra je?! Tohle mi děláš?!", "Takže tohle. Tohle jsi mi celou dobu dělal(a).", "Ty… vy dva? Kurva."],
	## (a) = rod obviněného.
	"confront_cheating": ["Kde jsi včera byl(a)? A nelži mi.", "Já to vím. Tak to konečně řekni.", "S kým si to pořád píšeš?"],
	"confront_confess": ["…jo. Je to pravda. Promiň.", "Nechtěl(a) jsem, aby to takhle dopadlo.", "Jo. Stalo se to. Nevím, co ti mám říct."],
	"confront_denied": ["Prosím tě, nic se neděje.", "Byl(a) jsem v práci. Fakt.", "Zase s tímhle? Nic není."],
	"confront_caught_lying": ["…dobře. Dobře! Jo. A co jako?", "Do prdele… Jo. Je to pravda."],
	"confront_innocent": ["Ty mě sleduješ? Ty mi fakt nevěříš?", "Nic nemám. Nic! Ale tvoje žárlivost mě ničí."],
	"confront_not_partners": ["O čem to mluvíš? Vždyť spolu nechodíme."],
	## (a) = rod nevěrníka (oslovený).
	"betrayed": ["Vypadni mi z očí.", "Jak jsi mi to mohl(a) udělat?", "Ty hajzle. Ty zasranej hajzle."],
	"jealous_partner": ["Hele, co to bylo? S kým si to tady flirtuješ?", "Fakt? Přímo přede mnou?"],
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
	"awkward": [
		"Eh… no, asi nic.",
		"Tak se měj.",
		"Promiň, nevím, co na to říct.",
	],
	"misunderstanding": [
		"Počkej, to jsem tak nemyslel(a).",
		"Asi jsme se nepochopili.",
		"To zní úplně jinak, než jak jsem to myslel(a).",
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
	## Drby – konfrontace zdroje ((a) = rod mluvčího; odpovídá obviněný).
	"confront_open": [
		"Hele, slyšel(a) jsem, co o mně roznášíš.",
		"Můžeš mi vysvětlit, proč o mně mluvíš za zády?",
		"Prej o mně vykládáš kraviny. Tak mi to řekni do očí.",
	],
	"confront_admit": [
		"…jo. Promiň. Nemělo to ode mě jít dál.",
		"Máš pravdu. Neměl(a) jsem to říkat. Řeknu lidem, jak to bylo.",
	],
	"confront_deny": [
		"Já? Ani omylem. Kdo ti tohle napovídal?",
		"Nic jsem neříkal(a). Fakt nevím, o čem mluvíš.",
		"To si vymýšlíš. Mě do toho netahej.",
	],
	"confront_escalate": [
		"A co jako? Někdo to říct musel!",
		"Nebudeš mě tu vyslýchat, kurva.",
		"Ty si fakt myslíš, že se všechno točí kolem tebe?",
	],
	## Popření drbu ((a) = rod mluvčího).
	"deny_open": [
		"To, co se o mně povídá, není pravda.",
		"Neposlouchej ty řeči. Takhle to nebylo.",
	],
	"deny_believed": [
		"Dobře. Věřím ti.",
		"Jo, mně to taky přišlo divný.",
	],
	"deny_doubted": [
		"Hm. Uvidíme.",
		"Já nevím… lidi to říkají dost jistě.",
	],
	"deny_caught": [
		"Viděl(a) jsem to na vlastní oči. Nekecej mi.",
		"Fakt mi budeš lhát do očí?",
	],
	## Svědek ataky paniky: zapírání bere jako stud, ne jako lež.
	"deny_caught_gentle": [
		"Hele, já u toho byl(a). Nemusíš se za to stydět.",
		"To je v pohodě. Stává se to, fakt.",
	],
	"deny_nothing": [
		"Jaký řeči? Nic jsem neslyšel(a).",
		"O čem to mluvíš? Nevím o ničem.",
	],
	"deny_repeat": [
		"Už jsi mi to říkal(a). Dneska už stačilo.",
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
	## Práce (Career).
		"work_leave": ["Jdu do práce.", "Tak zase do galeje.", "Kdyby mě někdo hledal, jsem v práci.", "Nechce se mi. Ale jdu."],
		"work_back": ["Jsem doma. Ani se neptej.", "Konečně doma.", "Ten šéf je fakt kretén.", "Dneska to šlo. Překvapivě."],
		"work_back_good": ["Šéf mě dneska pochválil. Fakt.", "Dobrej den v práci, kdo by to řekl."],
		"work_fired": ["Vyrazili mě. Ty vole, oni mě fakt vyrazili.", "Dostal(a) jsem padáka.", "Tak to je konec. Bez práce."],
		"work_promoted": ["Povýšili mě! Mě!", "Konečně si toho někdo všiml.", "Od zítřka mám nový místo."],
		"work_lost_race": ["Povýšili tu krysu místo mě.", "Tak jsem to prohrál(a). Kurva.", "Celý měsíce dřiny a dostane to někdo jinej."],
		"work_scheme_caught": ["Načapali mě. Mám výtku.", "Tak to se nepovedlo. Šéf zuří."],
		"work_sabotaged": ["Někdo mi v práci hází klacky pod nohy.", "Zase to padlo na mě. Kdo za tím sakra je?"],
		"call_sick": ["Dneska to nedám. Volám, že jsem marod.", "Haló, šéfe… dneska nepřijdu.", "Promiňte, dneska to fakt nepůjde."],
		"job_rejected": ["Další odmítnutí. Super.", "Ozveme se. Jasně.", "Nikdo mě nechce."],
		"job_hired": ["Vzali mě! Od zítřka makám.", "Mám práci. Konečně."],
		"quit_job": ["Končím. Dávám výpověď.", "Tak dost. Už tam nepáchnu."],
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
