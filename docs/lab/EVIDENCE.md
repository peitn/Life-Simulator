# Laboratoř sociální a psychologické dynamiky – vědecké podklady (validační, devalidační, protichůdné)

Účel: epistemická synchronizace. Ke každému konstruktu modelu zapsat, co ho podporuje, co ho zpochybňuje a co zůstává nevyřešené. Neprezentovat jako klinické ani prediktivní. Stav 6. 11. 2026.

**Jak číst značky.** [OVĚŘENO] = obsah zdroje jsem v této relaci skutečně načetla a shrnuji jen to, co v něm stálo. [JEN NÁZEV] = ve vyhledávání jsem našla pouze název/odkaz, obsah nebyl ověřen (stránka zablokovala načtení), nelze z něj citovat závěry. [Z PAMĚTI] = obecná znalost bez ověření, před použitím ověřit. Do metodiky patří jen [OVĚŘENO]; zbytek je seznam k doověření.

## 1. Sociální opora a stres (konstrukt `mental.support`, `rel_ledger`, podpora při coping)
Podpora (OVĚŘENO – Vila 2021, Frontiers in Psychology 12, přehled 23 metaanalýz):
- Opora souvisí s nižším výskytem nemocí a úmrtností; autor označuje velikosti účinků za „vysoce konzistentní". Experimenty s obrázky blízkých osob ukazují potlačení strachové reakce (bezpečnostní signál); blízké osoby snižují kortizolovou odpověď na laboratorní stresor (Trier Social Stress Test).

Zpochybnění a protichůdná data (OVĚŘENO – tentýž přehled):
- Smith a kol. (1994): slabá souhrnná korelace 0,15 pro zdravotní výsledky. Holt-Lunstad a kol. (2010): *přijatá* opora nebyla významná, významná byla *vnímaná* opora a osamělost. Shor a kol. (2013, 2015): opora od přátel a kontakt s rodinou nevýznamné, u mužů nevýznamné. Barth a kol. (2010): strukturální opora nevýznamná pro ischemickou chorobu srdeční. Kuiper a kol. (2015), Penninkilampi a kol. (2018): u demence nevýznamné.
- Kardiovaskulární reaktivita (sympatiko-adrenální) je nekonzistentní; mohou zkreslovat pohybové artefakty.
- Převážně korelační data → obrácená kauzalita (špatné zdraví zmenšuje sociální vazby) a třetí proměnné (věk, SES).
- Opora byla měřena 26 různými způsoby; jen 2 metaanalýzy použily doporučené funkčně-strukturální dělení → srovnání je obtížné. Moderace pohlavím a věkem.
- Přehled sám obsahuje nesrovnalosti v číslech (účastníci 1 458 vs 1 478 milionů; OR 1,50 vs 1,53) → citovat opatrně.

Důsledek pro model: rozlišovat *vnímanou* a *přijatou* oporu (model má `mental.support` i konkrétní akt `receive_support`); nepoužívat jedinou „sílu opory" a neslibovat efekt na zdraví. Efekt v simulaci je předpoklad modelu, ne zjištění.

Klasika stress-buffering vs. hlavní efekt: Cohen & Wills 1985, Psychological Bulletin [JEN NÁZEV / Z PAMĚTI – obsah nenačten]. Doověřit, za jakých podmínek platí vyrovnávání (buffering) a kdy hlavní efekt.

## 2. Emoce – 19 os místo „základních šesti" (konstrukt `emotional_state`)
Podpora (OVĚŘENO – Cowen, Sauter, Tracy, Keltner 2019, Psychological Science in the Public Interest 20(1)):
- Šest základních emocí je jen malá podmnožina; prožitek i výraz zahrnují zhruba 24–28 rozlišitelných kategorií a jejich směsi (27 u prožitku z videí, 28 u výrazu). Ani šest základních, ani valence+arousal nevysvětlí víc než ~30 % vysvětlitelné variance. Kategorie lépe předpovídají shodu mezi kulturami v hlasové prozodii než obecné hodnocení. Přibližně 50 % výrazu je sdíleno napříč kulturami, ~25 % kulturně specifické.

Zpochybnění (OVĚŘENO – tentýž článek): autoři sami uznávají, že kritika (Barrett a kol.) pokusů s nuceným výběrem a univerzality je „často oprávněná"; výpočet „30 %" vychází z jejich vlastních studií a z jejich vlastního modelu jako reference (částečně kruhové); počet kategorií je „dolní odhad" závislý na podnětech; část důkazů „in press". Konstruktivistický pohled (Barrett: emoce jako konstruovaná z valence a arousalu) zůstává konkurenčním modelem [Z PAMĚTI/JEN NÁZEV].

Důsledek: 19 os je rozumná střední cesta, ne ověřený fakt. Model by měl umět spustit variantu jen s valencí+arousalem a porovnat (alternativní modely).

## 3. Adaptace/habituace a „nastavený bod" (konstrukt habituační okno 6 h, regrese k základní úrovni)
OVĚŘENO – Diener, Lucas, Scollon 2006, American Psychologist 61(4) (jen abstrakt): model hedonické pásové běžecké cesty (návrat k neutrální úrovni) vyžaduje pět oprav: nastavené body nejsou neutrální; liší se mezi lidmi (temperament); jeden člověk jich má víc (pozitivní/negativní emoce, spokojenost se životem se mohou vyvíjet různě); nastavený bod se může měnit; adaptace je individuální. Závěr „snaha zvýšit štěstí je odsouzena k nezdaru" je příliš silný.
Důsledek: regrese k jednotné základní úrovni je v rozporu s tímto zdrojem; model potřebuje individuální základní úrovně a možnost trvalého posunu po velkých událostech. Označit v dokumentaci jako omezení.

## 4. Ruminace
[JEN NÁZEV] Nolen-Hoeksema, Wisco & Lyubomirsky 2008 „Rethinking Rumination", Perspectives on Psychological Science (PMID 26158958). Obsah nenačten. Doověřit: rozdělení na brooding a reflection a jejich odlišné vztahy k depresi.

## 5. Vyčerpání vůle (ego depletion) – jen jako varování
[JEN NÁZEV] „Challenges to Ego-Depletion Research Go beyond the Replication Crisis: A Need for Tackling the Conceptual Crisis" (Frontiers in Psychology 2017, PMC5394171). Obsah nenačten, ale už název uvádí replikační i konceptuální potíže. Model by neměl používat „vyčerpání sebekontroly" jako zavedený mechanismus bez dalšího ověření (zkontrolovat, zda ho `mental_state`/autoregulace předpokládá).

## 6. Replikovatelnost sociální psychologie obecně
OVĚŘENO – Open Science Collaboration 2015, Science (podle shrnutí na AcaWiki): 97 % původních studií mělo významný výsledek, 36 % replikací; 47 % původních velikostí účinku leželo v 95% intervalu replikace; 39 % subjektivně označeno jako replikované.
OVĚŘENO – Klein a kol. 2014 (Many Labs 1), Social Psychology 45(3): z 13 testovaných efektů se 10 replikovalo konzistentně (imagined contact slabě; flag priming a currency priming ne); replikovatelnost závisela víc na efektu než na vzorku/prostředí. (Počet „10" vs „11" se v textu liší.)
Důsledek: každý parametr odvozený z jedné studie z oboru brát jako slabý prior; upřednostnit metaanalýzy a registrované replikace.

## 7. Validace agentních modelů (metodika laboratoře)
OVĚŘENO – Boero & Squazzoni 2005, JASSS 8(4): modely mají být empiricky zakotvené (kalibrace mikroúrovně, validace makroúrovně); odlišit verifikaci (kód odpovídá teorii), docking (porovnání platforem) a empirickou validaci; rovnocenné cesty (*equifinality*) – shoda makro výsledku neidentifikuje mikro mechanismus; chybí standardní metoda; mikro-data o pravidlech chování bývají nedostupná.
Důsledek: laboratoř musí odlišit (a) inženýrskou správnost (determinismus, testy – máme), (b) citlivostní analýzu, (c) kalibraci na datech – dosud NEEXISTUJE, (d) alternativní modely. Dokumentovat ODD protokol [ODD = Overview, Design concepts, Details – standard popisu ABM; Z PAMĚTI, doověřit].

## 8. Co se nepodařilo ověřit (otevřené)
- Gottmanův „poměr 5:1" a kritika předpovědi stability manželství: vyhledávání vrátilo jen popularizační weby, žádný primární zdroj → nic netvrdit. Model používá poměr dobrých a špatných interakcí; doověřit primárně.
- Dunbarovo číslo/velikost sítí, teorie vazby, Lazarus & Folkman coping – nehledáno v této rundě.
- Metaanalýza vztahu *vnímané opory* a deprese u dětí a adolescentů (Montclair) – objevila se ve výsledcích, obsah nenačten.

## 9. Přehled: konstrukt → riziko → test
| Konstrukt v modelu | Hlavní riziko z literatury | Navržená kontrola |
|---|---|---|
| Opora (vnímaná vs přijatá) | Přijatá opora často nevýznamná, vnímaná ano; kauzalita nejasná | Oddělit manipulaci vnímané opory a skutečných vztahů (faktoriální návrh) |
| 19 emocí | Konkurenční modely (6 základních; valence+arousal) | Varianta s méně osami, porovnat výsledky experimentů |
| Návrat k základní úrovni | Nastavené body se liší a mění | Individuální základní úrovně; test posunu po události |
| Habituace 6 h | Neověřeno proti datům | Citlivostní analýza délky okna |
| Vyčerpání vůle (je-li) | Replikační a konceptuální krize | Zjistit použití, případně označit jako herní balance |
| Pravděpodobnost hádek | Herní balance | Označit game_balance, citlivostní analýza |
