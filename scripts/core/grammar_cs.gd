extends RefCounted
## Česká gramatika podle GRAMATICKÉHO RODU postavy (volba hráče, nezávislá na těle i identitě).
##   "m"  – on   (šel, unavený, můj kamarád)
##   "f"  – ona  (šla, unavená, moje kamarádka)
##   "n"  – ono  (šlo, unavené) – neutrální tvary
##   "pl" – oni  (šli, unavení) – množné tvary, které část nebinárních lidí v češtině používá
## Vztahová podstatná jména nemají v češtině neutrální rod – pro "n" a "pl" se používají opisy
## s „osoba“ (blízká osoba), které fungují gramaticky s ženským přivlastňovacím „moje“.

const GRAMMARS := ["m", "f", "n", "pl"]
const LABELS := {"m": "on (mužský rod)", "f": "ona (ženský rod)", "n": "ono (střední rod)", "pl": "oni (množné tvary)"}
const PRONOUN := {"m": "on", "f": "ona", "n": "ono", "pl": "oni"}
## Koncovka příčestí minulého: udělal / udělala / udělalo / udělali
const PAST := {"m": "", "f": "a", "n": "o", "pl": "i"}
## Koncovka tvrdých přídavných jmen: unavený / unavená / unavené / unavení
const ADJ := {"m": "ý", "f": "á", "n": "é", "pl": "í"}


static func valid(g) -> bool:
	return typeof(g) == TYPE_STRING and GRAMMARS.has(g)


static func norm(g) -> String:
	return String(g) if valid(g) else "m"


static func past(g) -> String:
	return PAST[norm(g)]


static func adj(g) -> String:
	return ADJ[norm(g)]


static func pronoun(g) -> String:
	return PRONOUN[norm(g)]


## Sloupec v tabulkách podstatných jmen [mužský, ženský, neutrální opis].
static func noun_col(g) -> int:
	match norm(g):
		"f":
			return 1
		"n", "pl":
			return 2
	return 0


## Přivlastňovací zájmeno k podstatnému jménu ze sloupce noun_col (můj kamarád / moje kamarádka / moje blízká osoba).
static func my(g) -> String:
	return "můj" if noun_col(g) == 0 else "moje"


## Nahradí značky v textu: „(a)“ a „{g}“ → koncovka příčestí, „{y}“ → koncovka přídavného jména.
static func form(text: String, g) -> String:
	return text.replace("(a)", past(g)).replace("{g}", past(g)).replace("{y}", adj(g))


## Ukázkové věty pro náhled v editoru (review ChatGPT 49: hráč má vidět, jak bude čeština o postavě mluvit,
## než rod potvrdí). Rod je volba GRAMATIKY, ne tvrzení o identitě; editor ho nechá vybrat výslovně.
static func preview(g, name: String) -> PackedStringArray:
	var col := noun_col(g)
	var friend: String = ["kamarád", "kamarádka", "blízká osoba"][col]
	return PackedStringArray([
		form("%s se vrátil(a) domů unaven{y}." % name, g),
		"%s je %s %s." % [name, my(g), friend],
		form("%s by si dal(a) kafe." % name, g),
	])
