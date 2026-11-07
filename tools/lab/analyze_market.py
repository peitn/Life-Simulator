#!/usr/bin/env python3
"""Fiktivní burza: párová analýza výstupu market_demo (market_runs.csv).
Použití: analyze_market.py <adresář s market_runs.csv> [výstupní adresář]
Dvě předem určené rodiny kontrastů (párově podle seedu; exaktní sign-flip test jako v analyze_experiment.py):
  A) účinek šoku uvnitř profilu:  metrika(scénář) − metrika(baseline)
  B) rozdíl profilů uvnitř scénáře: panic − passive (a momentum − passive)
Pro každý kontrast: průměrný rozdíl, SD, 95% interval (t), p (sign-flip), Holm-upravené p v rámci rodiny a metriky, dz.
POZOR: seedy jsou simulační replikace v jednom vymyšleném modelu; p-hodnota říká jen, jak konzistentní je rozdíl napříč seedy
v tomto modelu, nikoli nic o reálných trzích či lidech. Rozdíl škály/parametrů modelu (game_balance) mění výsledky."""
import csv, itertools, json, math, os, statistics, sys

T975 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228,
        11: 2.201, 12: 2.179, 13: 2.160, 14: 2.145, 15: 2.131, 19: 2.093, 29: 2.045}
METRICS_A = ["twr_pm", "mdd_pm", "wealth_change", "pressure_mtm_post"]
METRICS_B = ["twr_pm", "mdd_pm", "fees", "volume"]


def load(d):
    runs = {}
    with open(os.path.join(d, "market_runs.csv"), newline="") as f:
        for r in csv.DictReader(f):
            runs[(int(r["seed"]), r["scenario"], r["profile"])] = {k: float(v) for k, v in r.items() if k not in ("seed", "scenario", "profile")}
    return runs


def signflip(diff):
    n = len(diff)
    md = statistics.mean(diff)
    obs = abs(md)
    cnt = tot = 0
    for signs in itertools.product([1, -1], repeat=n):
        tot += 1
        if abs(sum(s * x for s, x in zip(signs, diff)) / n) >= obs - 1e-12:
            cnt += 1
    sd = statistics.stdev(diff) if n > 1 else float("nan")
    half = T975.get(n - 1, 1.96) * sd / math.sqrt(n) if n > 1 else float("nan")
    return {"n": n, "mean_diff": md, "sd": sd, "ci_lo": md - half, "ci_hi": md + half, "p": cnt / tot,
            "dz": (md / sd) if sd and sd > 0 else None}


def holm(rows):
    order = sorted(range(len(rows)), key=lambda i: rows[i]["p"])
    m = len(rows)
    run = 0.0
    for rank, i in enumerate(order):
        run = max(run, min(1.0, (m - rank) * rows[i]["p"]))
        rows[i]["p_holm"] = run


def main():
    d = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else d
    runs = load(d)
    seeds = sorted({k[0] for k in runs})
    scen = sorted({k[1] for k in runs}, key=lambda s: (s != "baseline", s))
    profs = sorted({k[2] for k in runs})
    rows = []
    for m in METRICS_A:
        fam = []
        for sc in scen:
            if sc == "baseline":
                continue
            for p in profs:
                diff = [runs[(s, sc, p)][m] - runs[(s, "baseline", p)][m] for s in seeds]
                r = signflip(diff)
                r.update({"family": "A_shock_vs_baseline", "metric": m, "scenario": sc, "a": p, "b": "baseline"})
                fam.append(r)
        holm(fam)
        rows += fam
    for m in METRICS_B:
        for other in ("passive",):
            for a in ("panic", "momentum", "contrarian", "disposition"):
                fam = []
                for sc in scen:
                    diff = [runs[(s, sc, a)][m] - runs[(s, sc, other)][m] for s in seeds]
                    r = signflip(diff)
                    r.update({"family": "B_profile_vs_passive", "metric": m, "scenario": sc, "a": a, "b": other})
                    fam.append(r)
                holm(fam)
                rows += fam
    cols = ["family", "metric", "scenario", "a", "b", "n", "mean_diff", "sd", "ci_lo", "ci_hi", "p", "p_holm", "dz"]
    with open(os.path.join(out, "market_contrasts.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for r in rows:
            w.writerow([r[c] if not isinstance(r[c], float) else round(r[c], 4) for c in cols] if r["dz"] is not None else
                       [r[c] if not isinstance(r[c], float) else round(r[c], 4) for c in cols[:-1]] + [""])
    json.dump({"seeds": seeds, "n_tests": len(rows), "note": "p z exaktního sign-flip testu přes seedy (2^n); Holm v rámci rodiny×metrika(×profil). "
               "Simulační replikace jednoho vymyšleného modelu; neříká nic o reálných trzích."},
              open(os.path.join(out, "market_analysis_meta.json"), "w"), ensure_ascii=False, indent=1)
    print("seedů: %d  testů: %d" % (len(seeds), len(rows)))
    for fam, m in (("B_profile_vs_passive", "twr_pm"), ("B_profile_vs_passive", "mdd_pm")):
        print("\n%s %s (a − passive; průměr přes seedy; * = p_holm < 0.05)" % (fam, m))
        print("%-12s" % "profil" + "".join(" %12s" % s[:12] for s in scen))
        for a in ("panic", "momentum", "contrarian", "disposition"):
            line = "%-12s" % a
            for sc in scen:
                r = next(x for x in rows if x["family"] == fam and x["metric"] == m and x["scenario"] == sc and x["a"] == a)
                line += " %11.1f%s" % (r["mean_diff"], "*" if r["p_holm"] < 0.05 else " ")
            print(line)
    print("\nA_shock_vs_baseline twr_pm (scénář − baseline; * = p_holm < 0.05)")
    print("%-12s" % "profil" + "".join(" %12s" % s[:12] for s in scen if s != "baseline"))
    for p in profs:
        line = "%-12s" % p
        for sc in scen:
            if sc == "baseline":
                continue
            r = next(x for x in rows if x["family"] == "A_shock_vs_baseline" and x["metric"] == "twr_pm" and x["scenario"] == sc and x["a"] == p)
            line += " %11.1f%s" % (r["mean_diff"], "*" if r["p_holm"] < 0.05 else " ")
        print(line)


if __name__ == "__main__":
    main()
