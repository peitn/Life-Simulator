extends RefCounted
## Katalog fiktivní ekonomiky: měna, povolání (legální i abstraktní nelegální), bydlení, výchozí konfigurace.
## VŠECHNA čísla jsou `game_balance` (ladění hry), žádné nejsou empirické údaje – viz docs/economy.md.
## Částky jsou celá čísla v nejmenší jednotce fiktivní měny.

const CURRENCY_NAME := "krejcar"
const CURRENCY_SYMBOL := "kr"
const UNITS_PER_ZLOTY := 100        ## 1 zl (zlatý) = 100 kr
const WEEK := 7

## Povolání. Legální: mzda za hodinu * hodiny směny; vyplácí se denně ("day") nebo týdně ("week", v den 6 týdne).
## Nelegální (abstraktní herní proces): příjem za směnu = rng v [income_min, income_max], neodvádí se z něj daň,
## `detect_bp` = pravděpodobnost odhalení za herní den v setinách procenta (10000 = 100 %), `fine_pct` = pokuta
## v % neodhaleného příjmu, `cooldown_days` = pozastavení po odhalení.
const JOBS := {
	"cleaner": {"title": "Uklízeč/ka", "legal": true, "sector": "services", "hours_per_shift": 8, "shifts_per_week": 5, "wage_per_hour": 300, "pay_period": "week", "skill_min": 0},
	"courier": {"title": "Kurýr/ka", "legal": true, "sector": "trade", "hours_per_shift": 8, "shifts_per_week": 5, "wage_per_hour": 330, "pay_period": "day", "skill_min": 0},
	"shop_assistant": {"title": "Prodavač/ka", "legal": true, "sector": "trade", "hours_per_shift": 8, "shifts_per_week": 5, "wage_per_hour": 350, "pay_period": "week", "skill_min": 0},
	"part_timer": {"title": "Brigádník/ice", "legal": true, "sector": "services", "hours_per_shift": 6, "shifts_per_week": 3, "wage_per_hour": 320, "pay_period": "day", "skill_min": 0},
	"clerk": {"title": "Úředník/ice", "legal": true, "sector": "office", "hours_per_shift": 8, "shifts_per_week": 5, "wage_per_hour": 420, "pay_period": "week", "skill_min": 1},
	"craftsman": {"title": "Řemeslník/ice", "legal": true, "sector": "industry", "hours_per_shift": 8, "shifts_per_week": 5, "wage_per_hour": 520, "pay_period": "week", "skill_min": 2},
	"engineer": {"title": "Technik/technička", "legal": true, "sector": "office", "hours_per_shift": 8, "shifts_per_week": 5, "wage_per_hour": 780, "pay_period": "week", "skill_min": 3},
	"black_market_runner": {"title": "Pochůzkář černého trhu (abstraktní)", "legal": false, "sector": "underground", "shifts_per_week": 3, "income_min": 2500, "income_max": 6000, "detect_bp": 120, "fine_pct": 150, "cooldown_days": 14},
	"smuggler_crew": {"title": "Pašerácká četa (abstraktní)", "legal": false, "sector": "underground", "shifts_per_week": 2, "income_min": 6000, "income_max": 16000, "detect_bp": 220, "fine_pct": 200, "cooldown_days": 21},
}

## Bydlení: týdenní nájem a energie (povinnosti na účet "sink:rent" / "sink:utilities").
const HOUSING := {
	"shared": {"rent_weekly": 4500, "utilities_weekly": 1000},
	"flat": {"rent_weekly": 7500, "utilities_weekly": 1300},
	"house": {"rent_weekly": 12500, "utilities_weekly": 2000},
}
const TIERS := ["shared", "flat", "house"]
const SINKS := ["sink:rent", "sink:utilities", "sink:food"]

## Výchozí konfigurace (vše game_balance). Čísla *_bp jsou setiny procenta (10000 = 100 %).
const DEFAULT_CONFIG := {
	"food_daily": 400,
	"rent_due_dow": 1,
	"utilities_due_dow": 4,
	"tax_mode": "progressive",                       ## "progressive" | "flat" | "none"
	"tax_brackets": [[8000, 0], [20000, 1500], [-1, 2800]],   ## týdenní pásma: [horní mez (-1 = bez mezi), sazba v bp]
	"flat_rate_bp": 1800,
	"benefit_weekly": 4000,
	"bank_capital": 3000000,
	"loan_max": 50000,
	"loan_min_credit": 400,
	"loan_max_active": 2,
	"loan_starter_cap": 5000,
	"loan_income_multiple": 8,                       ## strop dluhu = max(starter_cap, násobek * týdenní příjem)
	"loan_rate_table": [[700, 1200], [500, 2000], [0, 3200]],   ## [min. skóre, roční sazba v bp]
	"loan_period_days": 30,
	"loan_min_floor": 500,
	"loan_min_pct_bp": 1500,
	"loan_default_after": 3,
	"credit_start": 600,
	"credit_ontime": 5,
	"credit_missed": -20,
	"credit_default": -150,
	"credit_paid_off": 25,
	"credit_fine": -30,
	"detect_record_bonus_pct": 25,
	"detect_cap_bp": 2500,
	"residual_detect_bp": 40,
	"residual_fine_pct": 150,
	"residual_cooldown_days": 14,
	"arrears_reserve_days": 2,
	"pressure_runway_days": 30,
	"pressure_debt_saturation_pct": 200,             ## dluh = 200 % 28denního příjmu => složka dluhu = 1
	"pressure_missed_saturation": 6,
	"pressure_w_runway": 450,
	"pressure_w_debt": 300,
	"pressure_w_missed": 250,
	"poverty_runway_days": 14,
	"high_pressure_pm": 600,
	"mint_on_shortfall": true,
	"recycle_sinks": true,
	"treasury_burn_above": 0,                        ## 0 = vypnuto
	"auto_policy": true,
	"hire_bp": 1500,
	"layoff_bp": 10,
	"illegal_share_bp": 1500,
	"borrow_runway_days": 2,
	"borrow_days_of_cost": 14,
	"surplus_repay_days": 20,
	"endowment_min": 3000,
	"endowment_max": 40000,
	"employed_start_bp": 8500,
	"extra_jobs": {},
}
