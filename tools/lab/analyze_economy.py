#!/usr/bin/env python3
"""Laboratoř: analýza experimentu "ekonomika → psychika" (viz run_economy_experiment.py), párově podle seedu.
Soubory: out_<arm>_<seed>.json, arm ∈ e0 (bez ekonomiky), calm (ekonomika + burza), crash (ekonomika + burza + krach ve dni 3).
Kontrasty na seed:  eko = calm − e0 (efekt zapnutí ekonomiky);  krach = crash − calm (efekt krachu při zapnuté ekonomice).
Metriky se počítají ze snímků v okně po šoku (den > 3; stejné okno pro všechna ramena, aby bylo srovnatelné i u ramen bez šoku):
  post_peak_stress   největší stres kteréhokoli agenta v okně;  post_mean_stress / post_mean_mood  průměr přes agenty a snímky v okně;
  post_high_share    podíl (agent, snímek) se stresem >= 70;  final_stress / final_mood  poslední snímek;  stress_inputs  součet vstupů mostu (jen ramena s ekonomikou).
Test: exaktní permutační test se záměnou znamének (n <= 14: všech 2^n; jinak Monte Carlo 200 000, pevný seed), 95% t-interval.
Jen v rámci modelu; fiktivní agenti, herní balance. Výsledky neplatí pro lidi."""
import glob, itertools, json, math, os, random, re, statistics, sys

T975 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228,
        11: 2.201, 12: 2.179, 13: 2.160, 14: 2.145, 15: 2.131, 19: 2.093, 29: 2.045}
METRICS = ["post_peak_stress", "post_mean_stress", "post_high_share", "post_mean_mood", "final_stress", "final_mood",
           "argument_share", "stress_inputs"]
SHOCK_DAY = 3.0


def metrics(r):
    pk = 0.0
    ss = sm = 0.0
    n = hi = 0
    for s in r["snapshots"]:
        if float(s["day"]) <= SHOCK_DAY:
            continue
        for ag in s["agents"].values():
            pk = max(pk, ag["stress"])
            ss += ag["stress"]
            sm += ag["mood"]
            n += 1
            hi += ag["stress"] >= 70.0
    last = r["snapshots"][-1]["agents"].values()
    return {"post_peak_stress": pk, "post_mean_stress": ss / n, "post_high_share": hi / n, "post_mean_mood": sm / n,
            "final_stress": statistics.mean(a["stress"] for a in last), "final_mood": statistics.mean(a["mood"] for a in last),
            "argument_share": r["summary"]["argument_share"],
            "stress_inputs": r.get("economy", {}).get("stats", {}).get("stress_sum", 0.0)}


def load(d):
    runs = {}
    for f in glob.glob(os.path.join(d, "out_*_*.json")):
        m = re.search(r"out_(e0|calm|crash)_(\d+)\.json$", f)
        if m:
            r = json.load(open(f))
            if r.get("ok"):
                runs[(m.group(1), int(m.group(2)))] = metrics(r)
    return runs


def stats(xs):
    n = len(xs)
    md = statistics.mean(xs)
    sd = statistics.stdev(xs) if n > 1 else float("nan")
    half = T975.get(n - 1, 1.96) * sd / math.sqrt(n) if n > 1 else float("nan")
    obs = abs(md)
    if n <= 14:
        hits = tot = 0
        for sg in itertools.product([1, -1], repeat=n):
            tot += 1
            hits += abs(sum(a * b for a, b in zip(sg, xs)) / n) >= obs - 1e-12
        p = hits / tot
    else:
        rnd = random.Random(12345)
        hits = sum(abs(sum(rnd.choice((1, -1)) * x for x in xs) / n) >= obs - 1e-12 for _ in range(200000))
        p = (hits + 1) / 200001
    return {"mean": round(md, 4), "sd": round(sd, 4), "ci95": [round(md - half, 4), round(md + half, 4)],
            "p_signflip": round(p, 4), "dz": round(md / sd, 3) if sd and sd > 0 else None,
            "n_positive": sum(x > 1e-12 for x in xs), "n_negative": sum(x < -1e-12 for x in xs)}


def main():
    d = sys.argv[1]
    runs = load(d)
    seeds = sorted({s for (_, s) in runs if all((a, s) in runs for a in ("e0", "calm", "crash"))})
    out = {"n_seeds": len(seeds), "seeds": seeds, "cell_means": {}, "effects": {}, "p_holm_within_contrast": {},
           "note": "Platí jen v rámci modelu (fiktivní agenti, herní balance). Kontrasty jsou párové podle seedu."}
    for m in METRICS:
        out["cell_means"][m] = {a: round(statistics.mean(runs[(a, s)][m] for s in seeds), 4) for a in ("e0", "calm", "crash")}
        eko = [runs[("calm", s)][m] - runs[("e0", s)][m] for s in seeds]
        kr = [runs[("crash", s)][m] - runs[("calm", s)][m] for s in seeds]
        out["effects"][m] = {"eko": stats(eko), "krach": stats(kr)}
    for c in ("eko", "krach"):   # Holmova korekce přes metriky v rámci kontrastu (stress_inputs u eko je z konstrukce 0 vs >0, vynecháno)
        ms = [m for m in METRICS if not (c == "eko" and m == "stress_inputs")]
        ps = sorted((out["effects"][m][c]["p_signflip"], m) for m in ms)
        run_max = 0.0
        for i, (p, m) in enumerate(ps):
            run_max = max(run_max, min(1.0, p * (len(ps) - i)))
            out["p_holm_within_contrast"].setdefault(c, {})[m] = round(run_max, 4)
    json.dump(out, open(sys.argv[2] if len(sys.argv) > 2 else os.path.join(d, "analysis_economy.json"), "w"), indent=1, ensure_ascii=False)
    print("seedů: %d" % len(seeds))
    print("%-18s %-34s %-34s" % ("metrika", "eko = calm − e0", "krach = crash − calm"))
    for m in METRICS:
        e = out["effects"][m]
        f = lambda x: "%8.3f [%7.3f,%7.3f] p=%.3f" % (x["mean"], x["ci95"][0], x["ci95"][1], x["p_signflip"])
        print("%-18s %-34s %-34s" % (m, f(e["eko"]), f(e["krach"])))
    print("\nprůměry ramen (e0 / calm / crash):")
    for m in METRICS:
        c = out["cell_means"][m]
        print("%-18s %9.3f %9.3f %9.3f" % (m, c["e0"], c["calm"], c["crash"]))


if __name__ == "__main__":
    main()
