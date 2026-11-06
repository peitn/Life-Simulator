#!/usr/bin/env python3
"""Laboratoř M1b: analýza párového experimentu low vs high (stejný seed v obou podmínkách).
Použití: analyze_experiment.py <adresář s out_low_<seed>.json a out_high_<seed>.json> [výstup.json]
Vypíše pro každou metriku: průměr low/high, párový rozdíl, SD rozdílu, 95% interval (t), exaktní permutační
(sign-flip) p-hodnotu a velikost účinku (dz). Jen v rámci modelu; fiktivní agenti."""
import glob, itertools, json, math, os, re, statistics, sys

METRICS = ["mean_stress", "final_stress", "high_stress_share", "mean_mood", "final_mood",
           "mean_relationship", "final_relationship", "argument_share", "talks", "arguments"]
T975 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228,
        11: 2.201, 12: 2.179, 13: 2.160, 14: 2.145, 15: 2.131, 19: 2.093, 29: 2.045}


def load(d):
    runs = {}
    for f in sorted(glob.glob(os.path.join(d, "out_*_*.json"))):
        m = re.search(r"out_(low|high)_(\d+)\.json$", f)
        if not m:
            continue
        r = json.load(open(f))
        if r.get("ok"):
            runs[(m.group(1), int(m.group(2)))] = r
    return runs


def main():
    d = sys.argv[1]
    runs = load(d)
    seeds = sorted({s for (c, s) in runs if ("low", s) in runs and ("high", s) in runs})
    n = len(seeds)
    out = {"n_seeds": n, "seeds": seeds, "metrics": {}, "note": "Platí jen v rámci modelu (fiktivní agenti). "
           "Manipulace = initial_support + initial_relationship dohromady; neodděluje jejich příspěvky."}
    for m in METRICS:
        lo = [runs[("low", s)]["summary"][m] for s in seeds]
        hi = [runs[("high", s)]["summary"][m] for s in seeds]
        diff = [h - l for h, l in zip(hi, lo)]
        md = statistics.mean(diff)
        sd = statistics.stdev(diff) if n > 1 else float("nan")
        t = T975.get(n - 1, 1.96)
        half = t * sd / math.sqrt(n) if n > 1 else float("nan")
        obs = abs(md)
        cnt = tot = 0
        for signs in itertools.product([1, -1], repeat=n):
            tot += 1
            if abs(sum(s * x for s, x in zip(signs, diff)) / n) >= obs - 1e-12:
                cnt += 1
        out["metrics"][m] = {"low": round(statistics.mean(lo), 4), "high": round(statistics.mean(hi), 4),
            "low_sd": round(statistics.stdev(lo), 4) if n > 1 else None, "high_sd": round(statistics.stdev(hi), 4) if n > 1 else None,
            "diff": round(md, 4), "diff_sd": round(sd, 4), "ci95": [round(md - half, 4), round(md + half, 4)],
            "p_signflip": round(cnt / tot, 4), "dz": round(md / sd, 3) if sd and sd > 0 else None}
    json.dump(out, open(sys.argv[2] if len(sys.argv) > 2 else os.path.join(d, "analysis.json"), "w"), indent=1, ensure_ascii=False)
    print("seedů: %d  %s" % (n, seeds))
    print("%-20s %9s %9s %9s %18s %8s %6s" % ("metrika", "low", "high", "rozdíl", "95% CI", "p(flip)", "dz"))
    for m, v in out["metrics"].items():
        print("%-20s %9.3f %9.3f %9.3f [%7.3f,%7.3f] %8.3f %6s" % (m, v["low"], v["high"], v["diff"], v["ci95"][0], v["ci95"][1], v["p_signflip"], v["dz"]))


if __name__ == "__main__":
    main()
