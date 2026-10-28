extends RefCounted
## CzechG2P – rule-based Czech grapheme-to-phoneme conversion for the in-game TTS.
##
## Fully offline and deterministic. Input is untrusted text (speech-bubble lines, editor
## sample sentences, network-replicated public speech); every function is total: odd
## Unicode, emoji, control characters, huge numbers or empty strings never crash and
## never produce unbounded output.
##
## Phoneme symbols (one Array entry each) follow readable Czech phonetic transcription:
##   vowels      a e i o u, long á é í ó ú, diphthongs ou au eu, syllabic r̩ l̩ m̩ as "r" "l" "m"
##               flagged by syllabify() (the symbol itself stays the consonant)
##   plosives    p b t d ť ď k g
##   affricates  c (ts) dz č dž
##   fricatives  f v s z š ž x h, ř (voiced trill-fricative), ř̊ (voiceless)
##   sonorants   m n ň ŋ l r j
## Word boundaries are "|" and phrase punctuation tokens are ",", ".", "?", "!", "…", ";", ":".
##
## Rules implemented (standard Bohemian pronunciation):
##   ch → x; y/ý → i/í; ů → ú; w → v; q → kv; x → ks;
##   bě pě vě fě → bje pje vje fje; mě → mňe; dě tě ně → ďe ťe ňe;
##   di ti ni dí tí ní → ďi ťi ňi ďí ťí ňí (dy ty ny stay hard);
##   diphthongs ou au eu; dž / dz affricates;
##   n before k/g → ŋ;
##   regressive voicing assimilation inside obstruent clusters, also across a word
##   boundary inside one phrase (v is only a target, never a trigger);
##   final devoicing before a pause / sonorant / vowel; v → f before voiceless;
##   ř is devoiced after or before a voiceless obstruent and finally; sh → sx;
##   one-consonant prepositions (k s v z) are proclitics glued to the next word.

const MAX_CHARS := 200
const VOWELS := ["a", "e", "i", "o", "u", "á", "é", "í", "ó", "ú", "ou", "au", "eu"]
const LONG_VOWELS := ["á", "é", "í", "ó", "ú"]
const DIPHTHONGS := ["ou", "au", "eu"]
const SONORANTS := ["m", "n", "ň", "ŋ", "l", "r", "j"]
const PUNCT := [",", ".", "?", "!", "…", ";", ":"]
## Voiced ↔ voiceless obstruent pairs.
const VOICED_OF := {"p": "b", "t": "d", "ť": "ď", "k": "g", "f": "v", "s": "z", "š": "ž",
	"x": "h", "c": "dz", "č": "dž", "ř̊": "ř"}
const VOICELESS_OF := {"b": "p", "d": "t", "ď": "ť", "g": "k", "v": "f", "z": "s", "ž": "š",
	"h": "x", "dz": "c", "dž": "č", "ř": "ř̊"}
## One-consonant prepositions pronounced together with the following word.
const PROCLITIC_1 := ["k", "s", "v", "z"]
## Syllabic prepositions that take the stress of the following word (stress unit).
const PROCLITIC_STRESS := ["na", "do", "od", "po", "pro", "při", "za", "ze", "ve", "ke", "se", "ku",
	"bez", "nad", "pod", "před", "přes", "u", "o", "ob", "mezi", "skrz"]
## Unstressed enclitics (attach to the previous stress unit).
const ENCLITICS := ["se", "si", "mi", "ti", "mu", "ho", "jsem", "jsi", "jsme", "jste", "by", "bych",
	"bys", "bychom", "byste", "je", "jí", "ji", "jim", "nám", "vám", "ně", "tě", "mě", "ses", "sis", "tu", "už"]
## Interrogative words that make a "?" sentence a wh-question (falling contour).
const WH_WORDS := ["kdo", "co", "kde", "kdy", "proč", "jak", "kam", "odkud", "kolik", "který", "která",
	"které", "kterou", "kterého", "kterým", "čí", "čím", "čem", "komu", "koho", "kom", "kým", "čeho", "čemu",
	"jaký", "jaká", "jaké", "jakou", "jakého", "kudy", "nač", "zač", "odkdy", "dokdy", "kampak", "copak",
	"kdopak", "jakpak", "pročpak", "kdepak", "kolikrát", "jakže", "cože"]
const ONES := ["nula", "jedna", "dva", "tři", "čtyři", "pět", "šest", "sedm", "osm", "devět"]
const TEENS := ["deset", "jedenáct", "dvanáct", "třináct", "čtrnáct", "patnáct", "šestnáct",
	"sedmnáct", "osmnáct", "devatenáct"]
const TENS := ["", "", "dvacet", "třicet", "čtyřicet", "padesát", "šedesát", "sedmdesát",
	"osmdesát", "devadesát"]
const HUNDREDS := ["", "sto", "dvě stě", "tři sta", "čtyři sta", "pět set", "šest set",
	"sedm set", "osm set", "devět set"]
## Letters the normaliser keeps (after lower-casing and composition).
const LETTERS := "aábcčdďeéěfghiíjklmnňoópqrřsštťuúůvwxyýzž"
## Foreign letters folded to the closest Czech grapheme.
const FOLD := {"ä": "e", "ö": "é", "ü": "í", "ß": "s", "à": "a", "â": "a", "ã": "a", "å": "o",
	"ç": "c", "è": "e", "ê": "e", "ë": "e", "ì": "i", "î": "i", "ï": "i", "ñ": "ň", "ò": "o",
	"ô": "o", "õ": "o", "ø": "o", "ù": "u", "û": "u", "ÿ": "y", "ł": "l", "ľ": "l", "ĺ": "l",
	"ŕ": "r", "ś": "s", "ź": "z", "ż": "ž", "ć": "č", "ń": "ň", "ą": "a", "ę": "e", "ő": "ó", "ű": "ú"}
## Combining diacritics (NFD input) → composed letter.
const COMBINE := {
	0x0301: {"a": "á", "e": "é", "i": "í", "o": "ó", "u": "ú", "y": "ý"},
	0x030C: {"c": "č", "d": "ď", "e": "ě", "n": "ň", "r": "ř", "s": "š", "t": "ť", "z": "ž"},
	0x030A: {"u": "ů"},
}


## Lower-case, compose, fold foreign letters, spell numbers, keep only Czech letters, spaces
## and phrase punctuation. Result length ≤ MAX_CHARS * 4 (number spelling expands).
static func normalize(text: Variant) -> String:
	var s: String = text if typeof(text) == TYPE_STRING else ""
	if s.length() > MAX_CHARS:
		s = s.substr(0, MAX_CHARS)
	s = s.to_lower()
	var out := ""
	var digits := ""
	var prev_space := true
	for i in s.length():
		var code := s.unicode_at(i)
		var ch := String.chr(code)
		if code >= 48 and code <= 57:
			digits += ch
			continue
		if digits != "":
			out += (" " if not prev_space else "") + number_words_any(digits) + " "
			prev_space = true
			digits = ""
		if COMBINE.has(code):
			if out.length() > 0:
				var last := out.substr(out.length() - 1)
				var table: Dictionary = COMBINE[code]
				if table.has(last):
					out = out.substr(0, out.length() - 1) + String(table[last])
			continue
		if FOLD.has(ch):
			ch = FOLD[ch]
		if LETTERS.find(ch) >= 0:
			out += ch
			prev_space = false
		elif ch == "…":
			out += " … "
			prev_space = true
		elif ch in [",", ".", "?", "!", ";", ":"]:
			out += " " + ch + " "
			prev_space = true
		elif ch in ["-", "–", "—", "(", ")", "\"", "„", "“", "”", "/"]:
			# Dashes and brackets act as a soft continuation break; quotes as space.
			if ch in ["–", "—", "(", ")"]:
				out += " , "
			elif not prev_space:
				out += " "
			prev_space = true
		elif not prev_space:
			# Whitespace, emoji, symbols, control characters → one separator.
			out += " "
			prev_space = true
	if digits != "":
		out += " " + number_words_any(digits) + " "
	# Collapse repeated dots into an ellipsis and squeeze whitespace.
	out = out.replace(" .  . ", " … ").replace(". .", "…")
	var parts := out.split(" ", false)
	var res := PackedStringArray()
	for p in parts:
		if p == "." and res.size() > 0 and res[res.size() - 1] == ".":
			res[res.size() - 1] = "…"
			continue
		if p == "…" and res.size() > 0 and (res[res.size() - 1] == "." or res[res.size() - 1] == "…"):
			res[res.size() - 1] = "…"
			continue
		res.append(p)
	return " ".join(res)


## Czech cardinal number words for 0..9999 (counting form; 1 = "jedna", 2 = "dva").
static func number_words(n: int) -> String:
	if n < 0 or n > 9999:
		return ""
	if n < 10:
		return ONES[n]
	var parts := PackedStringArray()
	var th := n / 1000
	var rest := n % 1000
	if th > 0:
		if th == 1:
			parts.append("tisíc")
		elif th <= 4:
			parts.append(["", "", "dva", "tři", "čtyři"][th] + " tisíce")
		else:
			parts.append(ONES[th] + " tisíc")
	var h := rest / 100
	rest = rest % 100
	if h > 0:
		parts.append(HUNDREDS[h])
	if rest > 0:
		if rest < 10:
			parts.append(ONES[rest])
		elif rest < 20:
			parts.append(TEENS[rest - 10])
		else:
			parts.append(TENS[rest / 10])
			if rest % 10 > 0:
				parts.append(ONES[rest % 10])
	return " ".join(parts)


## Digit run of any length: ≤ 4 digits (and no leading zero) as a number, otherwise digit by digit.
static func number_words_any(digits: String) -> String:
	if digits.length() > 0 and digits.length() <= 4 and not (digits.length() > 1 and digits[0] == "0"):
		return number_words(int(digits))
	var parts := PackedStringArray()
	for i in mini(digits.length(), 24):
		parts.append(ONES[int(digits[i])])
	return " ".join(parts)


## Tokens: words and punctuation from normalize().
static func tokens(text: Variant) -> PackedStringArray:
	return normalize(text).split(" ", false)


## Letters of one word → raw phoneme list (no assimilation yet).
static func word_to_phonemes(word: String) -> Array:
	var out: Array = []
	var i := 0
	var n := word.length()
	while i < n:
		var c := word[i]
		var nx := word[i + 1] if i + 1 < n else ""
		match c:
			"c":
				if nx == "h":
					out.append("x")
					i += 2
					continue
				out.append("c")
			"d":
				if nx == "ž":
					out.append("dž")
					i += 2
					continue
				if nx == "ě":
					out.append_array(["ď", "e"])
					i += 2
					continue
				if nx == "i" or nx == "í":
					out.append("ď")
				else:
					out.append("d")
			"t":
				if nx == "ě":
					out.append_array(["ť", "e"])
					i += 2
					continue
				if nx == "i" or nx == "í":
					out.append("ť")
				else:
					out.append("t")
			"n":
				if nx == "ě":
					out.append_array(["ň", "e"])
					i += 2
					continue
				if nx == "i" or nx == "í":
					out.append("ň")
				else:
					out.append("n")
			"m":
				if nx == "ě":
					out.append_array(["m", "ň", "e"])
					i += 2
					continue
				out.append("m")
			"b", "p", "v", "f":
				out.append(c)
				if nx == "ě":
					out.append_array(["j", "e"])
					i += 2
					continue
			"ě":
				out.append("e")
			"y":
				out.append("i")
			"ý":
				out.append("í")
			"ů":
				out.append("ú")
			"w":
				out.append("v")
			"q":
				out.append_array(["k", "v"])
			"x":
				out.append_array(["k", "s"])
			"o", "a", "e":
				# ou is always a diphthong; au only word-initially (auto, august – not na-učit);
				# eu not in the ne- prefix (ne-umím), but neutrální keeps the diphthong.
				var diph: bool = nx == "u" and (c == "o" or (c == "a" and i == 0)
					or (c == "e" and not (i == 1 and word.begins_with("neu") and not word.begins_with("neutr"))))
				if diph:
					out.append(c + "u")
					i += 2
					continue
				out.append(c)
			"ň", "ď", "ť":
				out.append(c)
			_:
				out.append(c)
		i += 1
	# n before velar plosive → ŋ.
	for k in range(out.size() - 1):
		if out[k] == "n" and (out[k + 1] == "k" or out[k + 1] == "g"):
			out[k] = "ŋ"
	return out


static func is_vowel(p: String) -> bool:
	return VOWELS.has(p)


static func is_obstruent(p: String) -> bool:
	return VOICED_OF.has(p) or VOICELESS_OF.has(p)


static func is_voiced_obstruent(p: String) -> bool:
	return VOICELESS_OF.has(p)


## Voicing triggers: every obstruent except v (v assimilates but does not cause assimilation).
static func _is_trigger(p: String) -> bool:
	return is_obstruent(p) and p != "v" and p != "ř" and p != "ř̊"


static func _set_voice(p: String, voiced: bool) -> String:
	if voiced and VOICED_OF.has(p):
		return VOICED_OF[p]
	if not voiced and VOICELESS_OF.has(p):
		return VOICELESS_OF[p]
	return p


## Phrase-level assimilation on a flat list of phonemes with "|" word boundaries and
## punctuation tokens (pauses). Mutates and returns the list.
static func assimilate(seq: Array) -> Array:
	var n := seq.size()
	# 1) sh → sx (Bohemian standard): h after a voiceless obstruent becomes x.
	for i in range(1, n):
		if seq[i] == "h":
			var j := i - 1
			while j >= 0 and seq[j] == "|":
				j -= 1
			if j >= 0 and is_obstruent(seq[j]) and not is_voiced_obstruent(seq[j]) and seq[j] != "ř̊":
				seq[i] = "x"
	# 2) Regressive voicing: walk right-to-left; each obstruent takes the voicing of the next
	#    obstruent trigger within the same phrase (crossing "|" boundaries); before a pause,
	#    sonorant or vowel a word-final obstruent is voiceless (final devoicing).
	var i := n - 1
	var next_voicing := 0  # 0 = none (sonorant/vowel/word-internal), 1 = voiced trigger, -1 = voiceless trigger / pause
	var boundary_seen := true
	next_voicing = -1
	while i >= 0:
		var p: String = seq[i]
		if PUNCT.has(p):
			next_voicing = -1
			boundary_seen = true
		elif p == "|":
			boundary_seen = true
			if next_voicing == 0:
				next_voicing = -1  # word-final before vowel/sonorant → devoiced
		elif is_obstruent(p):
			if next_voicing == 1:
				seq[i] = _set_voice(p, true)
			elif next_voicing == -1:
				seq[i] = _set_voice(p, false)
			if _is_trigger(seq[i]):
				next_voicing = 1 if is_voiced_obstruent(seq[i]) else -1
			elif seq[i] == "f":
				next_voicing = -1
			elif seq[i] == "v":
				# v neither voices nor devoices what precedes it.
				next_voicing = 0
			boundary_seen = false
		else:
			next_voicing = 0
			boundary_seen = false
		i -= 1
	# 3) ř after a voiceless obstruent (třeba, při = ř̊ only after voiceless) → ř̊.
	for k in range(1, n):
		if seq[k] == "ř":
			var j := k - 1
			while j >= 0 and seq[j] == "|":
				j -= 1
			if j >= 0 and is_obstruent(seq[j]) and not is_voiced_obstruent(seq[j]):
				seq[k] = "ř̊"
	return seq


## Full G2P: text → flat phoneme list with "|" word separators and punctuation tokens.
## Proclitic one-letter prepositions (k s v z) are joined to the next word.
static func phonemes(text: Variant) -> Array:
	var toks := tokens(text)
	var seq: Array = []
	var glue := false
	for t in toks:
		if PUNCT.has(t):
			if seq.size() > 0 and seq[seq.size() - 1] == "|":
				seq.pop_back()
			seq.append(t)
			glue = false
			continue
		if seq.size() > 0 and not glue and not PUNCT.has(seq[seq.size() - 1]):
			seq.append("|")
		var ph := word_to_phonemes(t)
		seq.append_array(ph)
		glue = PROCLITIC_1.has(t)
	return assimilate(seq)


## Readable transcription string, e.g. "led" → "let", "obchod" → "opxot". Words joined by
## spaces, punctuation kept.
static func transcribe(text: Variant) -> String:
	var seq := phonemes(text)
	var out := ""
	for p in seq:
		if p == "|":
			out += " "
		elif PUNCT.has(p):
			out += p + " "
		else:
			out += String(p)
	return out.strip_edges().replace("  ", " ")


## Syllabify one word's phonemes. Returns Array of {"ph": [..], "nucleus": idx, "long": bool}.
## Nuclei: vowels/diphthongs; syllabic r, l (and m in "sedm"-type) between consonants or
## word-finally after a consonant.
static func syllabify(word: Array) -> Array:
	var n := word.size()
	var nucleus := []
	for i in n:
		var p: String = word[i]
		if is_vowel(p):
			nucleus.append(i)
		elif p in ["r", "l", "m"]:
			var prev_c := i > 0 and not is_vowel(word[i - 1])
			var next_c := i == n - 1 or not is_vowel(word[i + 1])
			if prev_c and next_c and (i == n - 1 or not (word[i + 1] in ["j"])):
				# m is syllabic only word-finally after a consonant (sedm, osm).
				if p != "m" or i == n - 1:
					nucleus.append(i)
	if nucleus.is_empty():
		return [{"ph": word.duplicate(), "nucleus": -1, "long": false}]
	var out: Array = []
	var start := 0
	for k in nucleus.size():
		var nuc: int = nucleus[k]
		var end := n
		if k + 1 < nucleus.size():
			var nxt: int = nucleus[k + 1]
			var cons := nxt - nuc - 1
			# Onset maximisation light: one consonant goes to the next syllable; of a cluster,
			# the last one (or two if it is obstruent + liquid/j) starts the next syllable.
			var take := 0 if cons == 0 else 1
			if cons >= 2:
				var a: String = word[nxt - 2]
				var b: String = word[nxt - 1]
				if is_obstruent(a) and b in ["r", "l", "ř", "ř̊", "j", "v"]:
					take = 2
			end = nxt - take
		var ph: Array = word.slice(start, end)
		var p_n: String = word[nuc]
		out.append({"ph": ph, "nucleus": nuc - start, "long": LONG_VOWELS.has(p_n) or DIPHTHONGS.has(p_n)})
		start = end
	return out


## Prosodic structure for the synthesiser: phrases → stress units → syllables.
## Returns Array of phrases: {"kind": "statement|question|wh|exclaim|continue|trail",
## "punct": String, "syllables": [{"ph": [...], "nucleus": i, "long": b, "stress": b,
## "unit": int, "word": String}]}.
static func prosody(text: Variant) -> Array:
	var toks := tokens(text)
	# Phonemes per token after phrase-level assimilation (same pass as phonemes()).
	var flat := phonemes(text)
	# Split flat sequence back into words aligned with non-punctuation tokens (proclitics glued).
	var words: Array = []      # [ [phonemes], token_text, is_proclitic_glued ]
	var cur: Array = []
	var phrase_ends: Array = []
	for p in flat:
		if p == "|":
			words.append(cur)
			cur = []
		elif PUNCT.has(p):
			if not cur.is_empty():
				words.append(cur)
				cur = []
			words.append(p)
		else:
			cur.append(p)
	if not cur.is_empty():
		words.append(cur)
	# Word texts in the same order (glued proclitics merged with their host word).
	var texts: Array = []
	var pending := ""
	for t in toks:
		if PUNCT.has(t):
			if pending != "":
				texts.append(pending)
				pending = ""
			texts.append(t)
			continue
		if pending != "":
			texts.append(pending + " " + t)
			pending = ""
			continue
		if PROCLITIC_1.has(t):
			pending = t
		else:
			texts.append(t)
	if pending != "":
		texts.append(pending)
	var phrases: Array = []
	var current := {"syllables": [], "words": []}
	var unit := -1
	var wi := 0
	var stress_next := false
	for idx in words.size():
		var w = words[idx]
		var txt: String = texts[idx] if idx < texts.size() else ""
		if w is String:
			current["punct"] = w
			phrases.append(current)
			current = {"syllables": [], "words": []}
			stress_next = false
			continue
		var bare := txt.get_slice(" ", txt.get_slice_count(" ") - 1)
		current["words"].append(bare)
		var sylls := syllabify(w)
		var enclitic: bool = ENCLITICS.has(bare) and not current["syllables"].is_empty() and not stress_next \
			and sylls.size() == 1
		var proclitic: bool = PROCLITIC_STRESS.has(bare) and sylls.size() <= 2
		if not enclitic and not stress_next:
			unit += 1
		for k in sylls.size():
			var sy: Dictionary = sylls[k]
			sy["unit"] = unit
			sy["word"] = bare
			sy["stress"] = k == 0 and not enclitic and not stress_next
			current["syllables"].append(sy)
		# A stressed one/two-syllable preposition carries the stress for the next word.
		stress_next = proclitic and not enclitic
		wi += 1
	if not current["syllables"].is_empty():
		current["punct"] = "."
		phrases.append(current)
	# Phrase kinds.
	for ph in phrases:
		var punct: String = ph.get("punct", ".")
		var kind := "statement"
		match punct:
			"?":
				kind = "question"
				var ws: Array = ph["words"]
				for k in mini(ws.size(), 2):
					if WH_WORDS.has(ws[k]):
						kind = "wh"
						break
			"!":
				kind = "exclaim"
			",", ";", ":":
				kind = "continue"
			"…":
				kind = "trail"
			_:
				kind = "statement"
		ph["kind"] = kind
	# Drop phrases with no syllables (stray punctuation).
	var res: Array = []
	for ph in phrases:
		if not ph["syllables"].is_empty():
			res.append(ph)
	return res
