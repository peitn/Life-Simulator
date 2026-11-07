extends RefCounted
## Katalog FIKTIVNÍ akciové burzy: firmy, investorské profily, výchozí konfigurace.
## Všechny firmy, tickery (přípona "-G" = game) i čísla jsou VYMYŠLENÉ a patří do `game_balance`.
## Žádná skutečná firma, ticker ani tržní data; nic z toho není kalibrováno na reálné trhy (viz docs/economy_market.md).
## Ceny jsou v tisícinách krejcaru ("millikr"): 1 kr = 1000 mkr; obchoduje se za cenu zaokrouhlenou dolů na celé kr.
## Výnosy se počítají v ppm (1 000 000 = 100 %), pravděpodobnosti/váhy v permille (pm), poplatky v bp.

const SECTORS := ["energy", "finance", "consumer", "health", "industry", "tech"]

## beta_pm = citlivost na společný tržní faktor (1000 = 1,0); idio_sd_ppm = denní směrodatná odchylka vlastního šumu;
## div_yield_pm = roční dividendový výnos v promilích ceny; px0_kr = počáteční cena v kr.
const FIRMS := [
	{"id": "ZLE-G", "name": "Zelenka Energie (fikce)", "sector": "energy", "beta_pm": 900, "idio_sd_ppm": 9000, "drift_ppm": 250, "div_yield_pm": 45, "px0_kr": 640, "float": 6000},
	{"id": "BRH-G", "name": "Břeh Finance (fikce)", "sector": "finance", "beta_pm": 1150, "idio_sd_ppm": 10000, "drift_ppm": 280, "div_yield_pm": 38, "px0_kr": 920, "float": 6000},
	{"id": "MRK-G", "name": "Mrkvička Potraviny (fikce)", "sector": "consumer", "beta_pm": 600, "idio_sd_ppm": 6500, "drift_ppm": 200, "div_yield_pm": 42, "px0_kr": 480, "float": 6000},
	{"id": "LVR-G", "name": "Lovor Obchody (fikce)", "sector": "consumer", "beta_pm": 1150, "idio_sd_ppm": 11000, "drift_ppm": 270, "div_yield_pm": 24, "px0_kr": 710, "float": 6000},
	{"id": "HBT-G", "name": "Habitat Zdraví (fikce)", "sector": "health", "beta_pm": 700, "idio_sd_ppm": 8000, "drift_ppm": 260, "div_yield_pm": 22, "px0_kr": 1180, "float": 6000},
	{"id": "KOT-G", "name": "Kotlina Těžba (fikce)", "sector": "industry", "beta_pm": 1250, "idio_sd_ppm": 13000, "drift_ppm": 280, "div_yield_pm": 35, "px0_kr": 560, "float": 6000},
	{"id": "DMS-G", "name": "Domovník Stavby (fikce)", "sector": "industry", "beta_pm": 1050, "idio_sd_ppm": 10000, "drift_ppm": 240, "div_yield_pm": 30, "px0_kr": 830, "float": 6000},
	{"id": "NVX-G", "name": "Nevotrix Software (fikce)", "sector": "tech", "beta_pm": 1450, "idio_sd_ppm": 17000, "drift_ppm": 330, "div_yield_pm": 6, "px0_kr": 1450, "float": 6000},
]

const PROFILE_IDS := ["cautious", "balanced", "momentum", "contrarian", "panic", "passive", "disposition"]

## Parametry profilů (pravidla chování; vše `game_balance`):
##  target_pm       základní cílový podíl akcií na likvidním majetku (hotovost + hodnota portfolia)
##  cadence         jak často (dny) se rozhoduje o rebalancování (+ posun podle agenta)
##  reserve_days    kolik dnů výdajů drží v hotovosti (nekupuje pod touto rezervou)
##  dd_exit_pm      výprodej všeho, když hodnota portfolia klesne o tolik promile od maxima za posledních dd_window dní (0 = vypnuto)
##  weights         "equal" | "defensive" | "momentum" | "dip"
##  fomo_up_pm / fomo_down_pm  práh 20denního výnosu indexu (pm) pro zvýšení / snížení cílového podílu; fomo_target_pm / fear_target_pm
##  take_profit_pm  disposition: prodej pozice se ziskem ≥ tolik pm vůči nákladům (nikdy neprodává ztrátové)
##  reenter_days    panic: po výprodeji tolik dnů mimo trh
const PROFILES := {
	"cautious": {"title": "Opatrný", "target_pm": 150, "cadence": 30, "reserve_days": 20, "dd_exit_pm": 200, "weights": "defensive", "reenter_days": 60},
	"balanced": {"title": "Vyvážený", "target_pm": 350, "cadence": 30, "reserve_days": 14, "dd_exit_pm": 0, "weights": "equal"},
	"momentum": {"title": "Momentum / honí trendy", "target_pm": 450, "cadence": 5, "reserve_days": 7, "dd_exit_pm": 0, "weights": "momentum",
		"fomo_up_pm": 60, "fomo_target_pm": 700, "fomo_down_pm": -60, "fear_target_pm": 150, "margin_ok": true},
	"contrarian": {"title": "Kontrarián", "target_pm": 350, "cadence": 5, "reserve_days": 12, "dd_exit_pm": 0, "weights": "dip",
		"fomo_up_pm": 120, "fomo_target_pm": 150, "fomo_down_pm": -80, "fear_target_pm": 600},
	"panic": {"title": "Panický", "target_pm": 400, "cadence": 10, "reserve_days": 10, "dd_exit_pm": 100, "weights": "equal", "reenter_days": 30},
	"passive": {"title": "Pasivní držitel", "target_pm": 400, "cadence": 0, "reserve_days": 14, "dd_exit_pm": 0, "weights": "equal"},
	"disposition": {"title": "Disposition (prodává zisky, drží ztráty)", "target_pm": 350, "cadence": 7, "reserve_days": 12, "dd_exit_pm": 0,
		"weights": "equal", "take_profit_pm": 100},
}

## Výchozí konfigurace burzy (vše game_balance).
const DEFAULT_CONFIG := {
	"market_sd_ppm": 7000,          # denní SD společného faktoru
	"sector_sd_ppm": 5000,          # denní SD sektorového faktoru
	"fee_bp": 50,                   # poplatek makléře (sink:market_fee)
	"fee_min": 3,                   # minimální poplatek v kr
	"trade_tax_bp": 0,              # daň z obchodu (do pokladny); scénář "rates" ji může zvýšit
	"div_tax_bp": 0,                # daň z dividend (do pokladny)
	"div_period": 91,               # dnů mezi dividendami
	"maker_capital": 20000000,      # kapitál tvůrce trhu (protistrana obchodů), mint jednorázově
	"maker_mint_on_shortfall": false,
	"impact_pm_per_pct": 8,         # dopad čistého toku: pm denního výnosu na 1 % free-floatu
	"impact_cap_ppm": 150000,
	"min_wealth_to_invest": 4000,   # pod touto likvidní hodnotou agent neinvestuje
	"distress_days": 3,             # hotovost pod 3 dny výdajů => nucený prodej
	"restore_days": 6,              # prodá tolik, aby hotovost dosáhla 6 dní výdajů
	"dd_window": 20,                # okno (dny) pro maximum hodnoty portfolia u výprodejního pravidla
	"momentum_window": 20,
	"dip_window": 60,
	"rebalance_band_pm": 25,        # práh odchylky (pm likvidního majetku) pro obchod
	"margin_enabled": false,        # volitelná marginová půjčka z existujícího loan systému
	"margin_call_pm": 1350,         # hodnota portfolia / dluh pod tímto poměrem (pm) => nucený prodej
	"margin_borrow_cap": 20000,
	"start_day": 1,
	"events": [],                   # viz docs/economy_market.md (path, vol, div_cut, rates, layoffs)
	"profile_mode": "derive",       # "derive" (ze seedu a vlastností) | "manual" (set_profile)
}
