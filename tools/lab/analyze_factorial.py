#!/usr/bin/env python3
"""Laboratoř M1c: analýza faktoriálního experimentu 2×2 (počáteční přátelství 0/50 × stresor ne/ano), párově podle seedu.
Soubory: out_<arm>_<seed>.json, arm ∈ r0s0, r50s0, r0s1, r50s1. Pro každý seed se spočítají tři kontrasty:
  rel     = hlavní efekt přátelství   = průměr(r50*) − průměr(r0*)
  stresor = hlavní efekt stresoru     = průměr(*s1) − průměr(*s0)
  inter   = interakce (r50s1−r0s1) − (r50s0−r0s0); záporná u stresových metrik = přátelství stres tlumí („buffering")
Pak průměr přes seedy, SD, 95% interval (t), exaktní permutační test se záměnou znamének (při n>14 Monte Carlo 200 000
s pevným seedem). Jen v rámci modelu; fiktivní agenti."""
import glob, itertools, json, math, os, random, re, statistics, sys

METRICS = ["peak_stress", "mean_stress_post", "final_stress", "mean_mood", "final_mood", "argument_share",
           "final_relationship", "talks"]
ARMS = ["r0s0", "r50s0", "r0s1", "r50s1"]
T975 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228,
        11: 2.201, 12: 2.179, 13: 2.160, 14: 2.145, 15: 2.131, 19: 2.093, 29: 2.045}


def load(d):
    runs = {}
    for f in glob.glob(os.path.join(d, "out_*_*.json")):
        m = re.search(r"out_(r\d+s\d)_(\d+)\.json$", f)
        if m:
            r = json.load(open(f))
            if r.get("ok"):
                runs[(m.group(1), int(m.group(2)))] = r["summary"]
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
            "p_signflip": round(p, 4), "dz": round(md / sd, 3) if sd and sd > 0 else None}


def main():
    d = sys.argv[1]
    runs = load(d)
    seeds = sorted({s for (_, s) in runs if all((a, s) in runs for a in ARMS)})
    out = {"n_seeds": len(seeds), "seeds": seeds, "cell_means": {}, "effects": {},
           "note": "Platí jen v rámci modelu (fiktivní agenti). Kontrasty jsou párové podle seedu."}
    for m in METRICS:
        cell = {a: round(statistics.mean(runs[(a, s)][m] for s in seeds), 4) for a in ARMS}
        out["cell_means"][m] = cell
        v = {a: [runs[(a, s)][m] for s in seeds] for a in ARMS}
        rel = [((v["r50s0"][i] + v["r50s1"][i]) - (v["r0s0"][i] + v["r0s1"][i])) / 2 for i in range(len(seeds))]
        st = [((v["r0s1"][i] + v["r50s1"][i]) - (v["r0s0"][i] + v["r50s0"][i])) / 2 for i in range(len(seeds))]
        it = [(v["r50s1"][i] - v["r0s1"][i]) - (v["r50s0"][i] - v["r0s0"][i]) for i in range(len(seeds))]
        out["effects"][m] = {"rel": stats(rel), "stresor": stats(st), "interakce": stats(it)}
    json.dump(out, open(sys.argv[2] if len(sys.argv) > 2 else os.path.join(d, "analysis_factorial.json"), "w"), indent=1, ensure_ascii=False)
    print("seedů: %d" % len(seeds))
    print("%-19s %-26s %-26s %-26s" % ("metrika", "přátelství (hl. efekt)", "stresor (hl. efekt)", "interakce"))
    for m in METRICS:
        e = out["effects"][m]
        f = lambda x: "%7.2f [%6.2f,%6.2f] p=%.3f" % (x["mean"], x["ci95"][0], x["ci95"][1], x["p_signflip"])
        print("%-19s %-26s %-26s %-26s" % (m, f(e["rel"]), f(e["stresor"]), f(e["interakce"])))
    print("\nprůměry buněk (r0s0 / r50s0 / r0s1 / r50s1):")
    for m in METRICS:
        c = out["cell_means"][m]
        print("%-19s %s" % (m, "  ".join("%8.3f" % c[a] for a in ARMS)))


if __name__ == "__main__":
    main()
