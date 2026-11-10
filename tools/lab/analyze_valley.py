#!/usr/bin/env python3
"""Analýza výzkumného běhu "Údolí" (lab_cli po blocích → souhrny po týdnech/měsících, po profilech, reakce na události).
Vstup: <runs>/<rameno>_s<seed>/blk_XX.json (rameno: events | control), tools/lab/experiments/udoli_v1_population.json
Výstup: <out>/analysis.json + malé CSV (weekly_all.csv, monthly_by_<strata>.csv, event_response.csv, agent_weekly.csv.gz).
Jen model s fiktivními agenty; intervaly jsou bootstrap přes agenty (agenti uvnitř bloku NEJSOU nezávislí a jde o jediný seed na rameno
→ intervaly jsou optimistické, viz docs/lab/RESEARCH_RUN_v1.md).
Použití: python3 tools/lab/analyze_valley.py <runs> <out> [--seeds 20310]"""
import argparse, csv, glob, gzip, json, os
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXP = os.path.join(ROOT, "tools/lab/experiments")
ARR = ["stress", "mood", "rel_mean", "rel_neg", "rel_pos", "pressure", "worry", "balance", "portfolio_value", "employed"]


def load_arm(d, pop):
    order = pop["order"]
    idx = {n: i for i, n in enumerate(order)}
    files = sorted(glob.glob(os.path.join(d, "blk_*.json")))
    if not files:
        return None
    res = None
    econ0 = None
    consistent = True
    elapsed = 0.0
    applied = {}
    for f in files:
        r = json.load(open(f, encoding="utf-8"))
        assert r.get("ok"), f
        snaps = r["snapshots"]
        D = len(snaps)
        if res is None:
            res = {k: np.full((D, len(order)), np.nan) for k in ARR}
            res["emotion"] = [[""] * len(order) for _ in range(D)]
            res["talks"] = np.zeros(D); res["args"] = np.zeros(D); res["good"] = np.zeros(D); res["bad"] = np.zeros(D)
            res["rumors"] = np.zeros(D); res["gshared"] = np.zeros(D)
            res["days"] = np.array([s["day"] for s in snaps])
            econ0 = [s.get("econ") for s in snaps]
            res["econ"] = econ0
            res["market"] = np.array([s.get("market_index_pm", 0) for s in snaps], dtype=float)
            res["stress_sources"] = {}
        cols = [idx[n] for n in r["agents"]]
        for k in ARR:
            if k in snaps[0]:
                for t, s in enumerate(snaps):
                    res[k][t, cols] = s[k]
        for t, s in enumerate(snaps):
            for j, c in enumerate(cols):
                res["emotion"][t][c] = s["emotion"][j]
            res["talks"][t] += s["talks"]; res["args"][t] += s["arguments"]
            res["good"][t] += s["events_good"]; res["bad"][t] += s["events_bad"]
            res["rumors"][t] += s["rumors"]; res["gshared"][t] += s["gossip_shared"]
            if s.get("econ") != econ0[t]:
                consistent = False
        for k, v in r.get("stress_sources_total", {}).items():
            res["stress_sources"][k] = res["stress_sources"].get(k, 0.0) + v
        for a in r.get("applied_interventions", []):
            key = (a["day"], a["label"], a["kind"])
            applied[key] = applied.get(key, 0) + a["affected"]
        elapsed += float(r.get("elapsed_s", 0.0))
    res["econ_consistent_across_blocks"] = consistent
    res["blocks"] = len(files)
    res["elapsed_s"] = elapsed
    res["applied"] = applied
    return res


def selector_mask(sel, pop):
    ag = pop["agents"]
    order = pop["order"]
    items = [sel] if isinstance(sel, str) else sel
    m = np.zeros(len(order), dtype=bool)
    for i, n in enumerate(order):
        a = ag[n]
        for t in items:
            hit = False
            if t == "all" or t == n:
                hit = True
            elif ":" in t:
                pre, arg = t.split(":", 1)
                hit = {"group": a["group"] == arg, "community": a["community"] == arg, "household": a["household"] == arg,
                       "profile": a["profile"] == arg, "wealth": str(a["wealth_class"]) == arg, "pred": arg in a["predispositions"]}.get(pre, False)
                if pre == "age":
                    lo, hi = [int(x) for x in arg.split("-")]
                    hit = lo <= a["age"] <= hi
            if hit:
                m[i] = True
                break
    return m


def boot_ci(x, n=2000, seed=7):
    x = np.asarray(x, dtype=float)
    x = x[~np.isnan(x)]
    if len(x) == 0:
        return (float("nan"),) * 3
    rng = np.random.default_rng(seed)
    means = np.array([rng.choice(x, len(x)).mean() for _ in range(n)])
    return float(x.mean()), float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))


def window(a, d0, d1):
    """snímky s indexem dne d0..d1 (včetně); den = index (denní snímky od 0)."""
    return a[max(d0, 0):d1 + 1]


def weekly(arm, pop):
    D = arm["stress"].shape[0]
    rows = []
    for w in range((D - 1) // 7):
        s, e = 1 + 7 * w, 7 + 7 * w            # snímky konce dnů s..e (den 1 = konec prvního dne)
        sl = slice(s, e + 1)
        econ = arm["econ"][e]
        dt = arm["talks"][e] - arm["talks"][s - 1]
        da = arm["args"][e] - arm["args"][s - 1]
        n = arm["stress"].shape[1]
        rows.append({"week": w + 1, "day_from": s, "day_to": e,
                     "mean_stress": float(np.nanmean(arm["stress"][sl])), "mean_mood": float(np.nanmean(arm["mood"][sl])),
                     "high_stress_share": float(np.nanmean(arm["stress"][sl] >= 70.0)),
                     "mean_rel": float(np.nanmean(arm["rel_mean"][sl])), "neg_ties_per_agent": float(np.nanmean(arm["rel_neg"][sl])),
                     "pos_ties_per_agent": float(np.nanmean(arm["rel_pos"][sl])),
                     "talks": float(dt), "arguments": float(da), "argument_share": float(da / dt) if dt > 0 else float("nan"),
                     "arguments_per_100_agent_days": float(da / (n * 7) * 100),
                     "mean_pressure": float(np.nanmean(arm["pressure"][sl])), "mean_worry": float(np.nanmean(arm["worry"][sl])),
                     "employed_share": float(np.nanmean(arm["employed"][sl])),
                     "gini": econ["gini_pm"] / 1000.0, "poverty_rate": econ["poverty_rate_pm"] / 1000.0,
                     "deep_poverty_rate": econ["deep_poverty_rate_pm"] / 1000.0, "high_pressure_share": econ["high_pressure_share_pm"] / 1000.0,
                     "median_balance_kr": econ["median_balance"], "total_debt_kr": econ["total_debt"],
                     "market_index": float(arm["market"][e]) / 1.0e6})
    return rows


def strata(pop):
    ag = pop["agents"]
    hh_size = {h["id"]: len(h["members"]) for h in pop["households"]}
    def band(a):
        return "18-34" if a < 35 else ("35-54" if a < 55 else ("55-69" if a < 70 else "70+"))
    out = {"investor_profile": {}, "community": {}, "work_group": {}, "wealth_class": {}, "age_band": {}, "predisposition": {}, "household_size": {}}
    for i, n in enumerate(pop["order"]):
        a = ag[n]
        keys = {"investor_profile": a["profile"], "community": a["community"], "work_group": a["group"], "wealth_class": "W%d" % a["wealth_class"],
                "age_band": band(a["age"]), "predisposition": "s_predispozicí" if a["predispositions"] else "bez_predispozice",
                "household_size": "dom_%s" % ("1" if hh_size[a["household"]] == 1 else ("2-3" if hh_size[a["household"]] <= 3 else "4+"))}
        for k, v in keys.items():
            out[k].setdefault(v, []).append(i)
    return out


def monthly_by(arm, groups):
    rows = []
    D = arm["stress"].shape[0]
    for m in range(6):
        s, e = 1 + 30 * m, min(30 + 30 * m, D - 1)
        sl = slice(s, e + 1)
        for gk, gv in groups.items():
            for name, ids in sorted(gv.items()):
                ids = np.array(ids)
                rows.append({"month": m + 1, "strata": gk, "group": name, "n": len(ids),
                             "mean_stress": float(np.nanmean(arm["stress"][sl][:, ids])), "mean_mood": float(np.nanmean(arm["mood"][sl][:, ids])),
                             "high_stress_share": float(np.nanmean(arm["stress"][sl][:, ids] >= 70.0)),
                             "mean_rel": float(np.nanmean(arm["rel_mean"][sl][:, ids])),
                             "mean_pressure": float(np.nanmean(arm["pressure"][sl][:, ids])), "mean_worry": float(np.nanmean(arm["worry"][sl][:, ids])),
                             "employed_share": float(np.nanmean(arm["employed"][sl][:, ids]))})
    return rows


def event_list(sc):
    ev = []
    for e in sc["interventions"]:
        ev.append({"day": e["day"], "label": e["label"], "category": e.get("category", ""), "kind": e["kind"], "mask_sel": e.get("target", e.get("a")),
                   "mask_sel_b": e.get("b"), "detail": {k: e[k] for k in ("amount", "strength", "minutes", "delta") if k in e}})
    for e in sc["economy"].get("events", []):
        ev.append({"day": e["day"], "label": e["label"], "category": "ekonomická/trh", "kind": "econ:" + e["type"], "mask_sel": "all", "mask_sel_b": None,
                   "detail": {k: e[k] for k in ("days", "total_pm", "mult_pm", "cut_pm", "share_pm", "loan_rate_add_bp") if k in e}})
    ev.sort(key=lambda e: (e["day"], e["label"]))
    return ev


def per_agent_delta(a, ids, d, pre=7, post=7):
    """po agentech: průměr za dny d..d+post-1 minus průměr za dny d-pre..d-1 (snímek dne t = stav po t dnech)."""
    D = a.shape[0]
    p0, p1 = max(d - pre, 0), d - 1
    q0, q1 = d, min(d + post - 1, D - 1)
    base = np.nanmean(a[p0:p1 + 1][:, ids], axis=0)
    after = np.nanmean(a[q0:q1 + 1][:, ids], axis=0)
    return after - base


def event_response(arms, pop, sc):
    ev = event_list(sc)
    rows = []
    ctrl = arms.get("control")
    ex = arms["events"]
    for e in ev:
        mask = selector_mask(e["mask_sel"], pop)
        if e["mask_sel_b"] is not None:
            mask = mask | selector_mask(e["mask_sel_b"], pop)
        ids = np.where(mask)[0]
        d = int(e["day"])
        if len(ids) == 0:
            continue
        row = {"day": d, "label": e["label"], "category": e["category"], "kind": e["kind"], "n_affected": int(len(ids)),
               "detail": json.dumps(e["detail"], ensure_ascii=False), "pre_days": min(7, d)}
        for k, name in (("stress", "stress"), ("mood", "mood"), ("rel_mean", "rel"), ("pressure", "pressure"), ("worry", "worry")):
            dx = per_agent_delta(ex[k], ids, d)
            m, lo, hi = boot_ci(dx)
            row["d_%s" % name], row["d_%s_lo" % name], row["d_%s_hi" % name] = m, lo, hi
            if ctrl is not None:
                dc = per_agent_delta(ctrl[k], ids, d)
                mm, l2, h2 = boot_ci(dx - dc)
                row["did_%s" % name], row["did_%s_lo" % name], row["did_%s_hi" % name] = mm, l2, h2
                row["ctrl_d_%s" % name] = float(np.nanmean(dc))
        # špička skupinového průměru stresu v 7 dnech po události
        seg = ex["stress"][d:min(d + 7, ex["stress"].shape[0])][:, ids].mean(axis=1)
        row["peak_group_stress_7d"] = float(seg.max()) if len(seg) else float("nan")
        row["base_group_stress"] = float(np.nanmean(ex["stress"][max(d - 7, 0):d][:, ids])) if d > 0 else float("nan")
        rows.append(row)
    return rows


def crash_by_profile(arms, pop, sc):
    """Krach (první path < 0): dopad na hodnotu portfolia a starost podle investorského profilu."""
    ex = arms["events"]
    crash = [e for e in sc["economy"]["events"] if e["type"] == "path" and e["total_pm"] < 0][0]
    d0, d1 = int(crash["day"]), int(crash["day"]) + int(crash["days"])
    out = {}
    prof = {}
    for i, n in enumerate(pop["order"]):
        prof.setdefault(pop["agents"][n]["profile"], []).append(i)
    for p, ids in sorted(prof.items()):
        ids = np.array(ids)
        pv0 = ex["portfolio_value"][d0 - 1][ids]
        pv1 = ex["portfolio_value"][d1 + 1][ids]
        held = pv0 > 0
        ch = (pv1[held] - pv0[held]) / pv0[held] if held.any() else np.array([])
        out[p] = {"n": int(len(ids)), "n_with_portfolio": int(held.sum()),
                  "mean_pv_change_pct": float(ch.mean() * 100) if len(ch) else None,
                  "peak_worry_mean": float(np.nanmax(ex["worry"][d0:d1 + 12][:, ids], axis=0).mean()),
                  "d_stress_week_after": float(np.nanmean(per_agent_delta(ex["stress"], ids, d0 + 1, 7, 7))),
                  "d_mood_week_after": float(np.nanmean(per_agent_delta(ex["mood"], ids, d0 + 1, 7, 7)))}
    return out


def write_csv(path, rows, gz=False):
    if not rows:
        return
    op = gzip.open if gz else open
    with op(path, "wt", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        for r in rows:
            w.writerow({k: (round(v, 4) if isinstance(v, float) else v) for k, v in r.items()})


def agent_weekly(arm, pop):
    rows = []
    D = arm["stress"].shape[0]
    for w in range((D - 1) // 7):
        s, e = 1 + 7 * w, 7 + 7 * w
        for i, n in enumerate(pop["order"]):
            a = pop["agents"][n]
            rows.append({"week": w + 1, "agent": n, "group": a["group"], "community": a["community"], "profile": a["profile"],
                         "stress": float(np.nanmean(arm["stress"][s:e + 1, i])), "mood": float(np.nanmean(arm["mood"][s:e + 1, i])),
                         "rel_mean": float(np.nanmean(arm["rel_mean"][s:e + 1, i])), "pressure": float(np.nanmean(arm["pressure"][s:e + 1, i])),
                         "worry": float(np.nanmean(arm["worry"][s:e + 1, i])), "balance_kr": int(arm["balance"][e, i]),
                         "portfolio_kr": int(arm["portfolio_value"][e, i])})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs")
    ap.add_argument("out")
    ap.add_argument("--seed", type=int, default=20310)
    a = ap.parse_args()
    pop = json.load(open(os.path.join(EXP, "udoli_v1_population.json"), encoding="utf-8"))
    sc = json.load(open(os.path.join(EXP, "udoli_v1.json"), encoding="utf-8"))
    os.makedirs(a.out, exist_ok=True)
    arms = {}
    for arm in ("events", "control"):
        r = load_arm(os.path.join(a.runs, "%s_s%d" % (arm, a.seed)), pop)
        if r is not None:
            arms[arm] = r
    ex = arms["events"]
    out = {"seed": a.seed, "arms": {k: {"blocks": v["blocks"], "days_in_data": int(v["stress"].shape[0] - 1),
                                        "econ_consistent_across_blocks": v["econ_consistent_across_blocks"],
                                        "elapsed_s_sum_blocks": v["elapsed_s"]} for k, v in arms.items()}}
    finite = {k: bool(np.isfinite(ex[k][~np.isnan(ex[k])]).all()) for k in ARR}
    out["finite_ok"] = finite
    out["nan_cells"] = {k: int(np.isnan(ex[k]).sum()) for k in ARR}
    for armname, arm in arms.items():
        wk = weekly(arm, pop)
        write_csv(os.path.join(a.out, "weekly_%s.csv" % armname), wk)
        out.setdefault("weekly_summary", {})[armname] = {
            "mean_stress_all": float(np.nanmean(arm["stress"][1:])), "mean_mood_all": float(np.nanmean(arm["mood"][1:])),
            "high_stress_share_all": float(np.nanmean(arm["stress"][1:] >= 70.0)), "mean_rel_all": float(np.nanmean(arm["rel_mean"][1:])),
            "arguments_total": float(arm["args"][-1]), "talks_total": float(arm["talks"][-1]),
            "argument_share_total": float(arm["args"][-1] / arm["talks"][-1]),
            "final_gini": arm["econ"][-1]["gini_pm"] / 1000.0, "final_poverty": arm["econ"][-1]["poverty_rate_pm"] / 1000.0,
            "final_deep_poverty": arm["econ"][-1]["deep_poverty_rate_pm"] / 1000.0,
            "start_gini": arm["econ"][1]["gini_pm"] / 1000.0, "start_poverty": arm["econ"][1]["poverty_rate_pm"] / 1000.0,
            "final_high_pressure_share": arm["econ"][-1]["high_pressure_share_pm"] / 1000.0, "stress_sources_total": arm["stress_sources"],
            "gossip_shared_total": float(arm["gshared"][-1]), "rumors_final": float(arm["rumors"][-1]),
            "life_events_good": float(arm["good"][-1]), "life_events_bad": float(arm["bad"][-1])}
        g = strata(pop)
        write_csv(os.path.join(a.out, "monthly_by_strata_%s.csv" % armname), monthly_by(arm, g))
        write_csv(os.path.join(a.out, "agent_weekly_%s.csv.gz" % armname), agent_weekly(arm, pop), gz=True)
        # denní řada (celá populace) pro vizualizaci
        daily = []
        for t in range(arm["stress"].shape[0]):
            e = arm["econ"][t] or {}
            daily.append({"day": t, "mean_stress": float(np.nanmean(arm["stress"][t])), "mean_mood": float(np.nanmean(arm["mood"][t])),
                          "high_stress_share": float(np.nanmean(arm["stress"][t] >= 70.0)), "mean_rel": float(np.nanmean(arm["rel_mean"][t])),
                          "mean_pressure": float(np.nanmean(arm["pressure"][t])), "mean_worry": float(np.nanmean(arm["worry"][t])),
                          "gini": e.get("gini_pm", 0) / 1000.0, "poverty": e.get("poverty_rate_pm", 0) / 1000.0,
                          "market_index": float(arm["market"][t]) / 1.0e6, "arguments_cum": float(arm["args"][t]), "talks_cum": float(arm["talks"][t]),
                          "employed_share": float(np.nanmean(arm["employed"][t]))})
        write_csv(os.path.join(a.out, "daily_all_%s.csv" % armname), daily)
    rows = event_response(arms, pop, sc)
    write_csv(os.path.join(a.out, "event_response.csv"), rows)
    out["event_response"] = rows
    out["crash_by_investor_profile"] = crash_by_profile(arms, pop, sc)
    out["applied_interventions"] = [{"day": k[0], "label": k[1], "kind": k[2], "affected_agents": v} for k, v in sorted(ex["applied"].items())]
    # rozdíly mezi profily: celý běh a po šoku
    g = strata(pop)
    cmp_rows = {}
    for gk, gv in g.items():
        cmp_rows[gk] = {name: {"n": len(ids), "mean_stress": float(np.nanmean(ex["stress"][1:][:, ids])), "mean_mood": float(np.nanmean(ex["mood"][1:][:, ids])),
                               "high_stress_share": float(np.nanmean(ex["stress"][1:][:, ids] >= 70.0)),
                               "mean_pressure": float(np.nanmean(ex["pressure"][1:][:, ids])), "mean_worry": float(np.nanmean(ex["worry"][1:][:, ids])),
                               "mean_rel": float(np.nanmean(ex["rel_mean"][1:][:, ids]))} for name, ids in sorted(gv.items())}
    out["strata_events_arm"] = cmp_rows
    if "control" in arms:
        c = arms["control"]
        out["control_vs_events"] = {"mean_stress_diff": float(np.nanmean(ex["stress"][1:]) - np.nanmean(c["stress"][1:])),
                                    "mean_mood_diff": float(np.nanmean(ex["mood"][1:]) - np.nanmean(c["mood"][1:]))}
    json.dump(out, open(os.path.join(a.out, "analysis.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("analýza zapsána do", a.out)


if __name__ == "__main__":
    main()
