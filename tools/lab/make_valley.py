#!/usr/bin/env python3
"""Generátor fiktivní oblasti "Údolí" (výzkumný běh v1): N obyvatel, domácnosti, komunity, pracovní skupiny,
různorodé osobnostní/psychické profily, investorské profily, počáteční vztahy. Plně deterministický ze seedu
(random.Random, žádné čtení času ani prostředí). Výstup:
  <out>/udoli_v1_household.json   pole postav ve formátu Main.HOUSEHOLD (validuje Schema/Validator hry)
  <out>/udoli_v1_population.json  metadata: skupiny, komunity, domácnosti, ekonomika agentů, počáteční vztahy
Použití: python3 tools/lab/make_valley.py --seed 20261 --n 100 --out tools/lab/experiments
Vše jsou FIKTIVNÍ postavy; rozdělení a pravděpodobnosti jsou návrhové předpoklady (game_balance), ne data o lidech."""
import argparse
import json
import os
import random

FEM = ["Jana", "Eva", "Hana", "Lenka", "Petra", "Marie", "Lucie", "Kateřina", "Veronika", "Tereza", "Alena", "Monika", "Zuzana",
       "Barbora", "Michaela", "Ivana", "Markéta", "Dagmar", "Olga", "Božena", "Renata", "Simona", "Klára", "Adéla", "Nikola",
       "Vlasta", "Irena", "Libuše", "Gabriela", "Denisa", "Radka", "Martina", "Šárka", "Andrea", "Jitka", "Romana"]
MAS = ["Jan", "Petr", "Pavel", "Martin", "Tomáš", "Jakub", "Lukáš", "Michal", "David", "Ondřej", "Josef", "Jiří", "Karel",
       "Milan", "Václav", "Zdeněk", "Marek", "Filip", "Radek", "Roman", "Štěpán", "Vojtěch", "Adam", "Daniel", "Miroslav",
       "Aleš", "Libor", "Robert", "Dominik", "Patrik", "Ladislav", "Oldřich", "Matěj", "Viktor", "Igor", "Bohumil"]
SUR = ["Novák", "Svoboda", "Dvořák", "Černý", "Procházka", "Kučera", "Veselý", "Horák", "Němec", "Marek", "Pokorný", "Král",
       "Růžička", "Beneš", "Fiala", "Sedláček", "Doležal", "Zeman", "Kolář", "Navrátil", "Čermák", "Urban", "Vaněk", "Blažek",
       "Kříž", "Kovář", "Bartoš", "Vlček", "Polák", "Šimek", "Holub", "Jelínek", "Mareš", "Krejčí", "Hruška", "Sochor",
       "Havlík", "Štěpánek", "Musil", "Malý", "Straka", "Toman", "Bureš", "Soukup", "Hájek", "Rybář", "Kopecký", "Lang"]

# velikosti domácností (součet 100): rozmanité komunity i jedinci
SIZES = [1] * 8 + [2] * 8 + [3] * 5 + [4] * 5 + [5] * 3 + [6] * 2 + [7] * 2

COMMUNITIES = [
    {"id": "stara_ctvrt", "title": "Stará čtvrť", "age": (35, 78), "tiers": ["house", "flat", "flat"], "w": 22},
    {"id": "nove_sidliste", "title": "Nové sídliště", "age": (22, 55), "tiers": ["flat", "flat", "shared"], "w": 30},
    {"id": "dilny", "title": "Dílenská ulice", "age": (24, 62), "tiers": ["flat", "shared", "house"], "w": 18},
    {"id": "recni_nabrezi", "title": "Říční nábřeží", "age": (20, 48), "tiers": ["house", "flat", "flat"], "w": 14},
    {"id": "penzion_lipa", "title": "Penzion Lípa", "age": (58, 85), "tiers": ["shared", "flat"], "w": 16},
]
WORK_GROUPS = [
    {"id": "dilna", "title": "Dílna u Mostu", "job": "craftsman", "skill": 2},
    {"id": "obchodni_rada", "title": "Obchodní řada", "job": "shop_assistant", "skill": 0},
    {"id": "urad", "title": "Obecní úřad", "job": "clerk", "skill": 1},
    {"id": "technicky_ustav", "title": "Technický ústav", "job": "engineer", "skill": 3},
    {"id": "kuryrni_sluzba", "title": "Kurýrní služba", "job": "courier", "skill": 0},
    {"id": "uklid", "title": "Úklidová služba", "job": "cleaner", "skill": 0},
    {"id": "brigadnici", "title": "Brigádníci", "job": "part_timer", "skill": 0},
    {"id": "bez_prace", "title": "Bez zaměstnání", "job": "", "skill": 0},
    {"id": "duchod", "title": "Senioři (mimo práci)", "job": "", "skill": 0},
]
PROFILES = ["cautious", "balanced", "momentum", "contrarian", "panic", "passive"]
PROFILE_W = {"cautious": 22, "balanced": 26, "momentum": 12, "contrarian": 10, "panic": 12, "passive": 18}
PREDISP = {"anxiety": 0.18, "depression": 0.15, "social_anxiety": 0.10, "addiction": 0.08, "ocd": 0.04, "psychosis": 0.02}
TRAUMAS = ["ztrata_blizkeho", "rozchod", "sikana", "nehoda", "vyhozeni", "chudoba"]
ASPIR = ["rodina", "kariera", "penize", "pratele", "tvorba", "klid", "uznani", "nezavislost", "napravit"]
TRAITS = ["lenoch", "aktivni", "pedant", "spolecensky", "samotar", "gurman", "hravy", "knihomol", "optimista", "brucoun",
          "zarlivy", "vznetlivy", "cynik", "impulzivni", "uzkostlivy"]
CONFLICTS = [("spolecensky", "samotar"), ("lenoch", "aktivni"), ("optimista", "brucoun"), ("optimista", "cynik"), ("brucoun", "cynik")]
TRAIT_COST = {"optimista": 2, "aktivni": 1, "pedant": 1, "spolecensky": 1, "samotar": 1, "gurman": 1, "hravy": 1, "knihomol": 1,
              "lenoch": 0, "brucoun": 0, "zarlivy": 0, "vznetlivy": 0, "cynik": 0, "impulzivni": 0, "uzkostlivy": 0}
DISP = ["threat_sensitivity", "hypervigilance", "social_threat", "rejection_reactivity", "impulsivity", "regulation_capacity",
        "predictability_need", "sensory_sensitivity", "energy_baseline", "reward_sensitivity", "cognitive_flexibility"]
WEALTH = [  # (podíl %, min kr, max kr) – kr = krejcary; násobky 100
    (22, 2000, 9000), (33, 9000, 30000), (30, 30000, 90000), (15, 90000, 300000)]


def clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def wchoice(rng, items, weights):
    return rng.choices(items, weights=weights, k=1)[0]


def beta(rng, a, b):
    return rng.betavariate(a, b)


def build(seed, n):
    rng = random.Random(seed)
    sizes = list(SIZES)
    if n != 100:  # pro měření výkonu: stejná struktura, jen jiný počet obyvatel
        sizes = []
        left = n
        pat = [1, 2, 3, 4, 5, 2, 3, 1]
        i = 0
        while left > 0:
            s = min(pat[i % len(pat)], left)
            sizes.append(s)
            left -= s
            i += 1
    rng.shuffle(sizes)
    names_used = set()
    chars, pop_agents, households, rel_pairs = [], {}, [], []
    comm_ids = [c["id"] for c in COMMUNITIES]
    comm_w = [c["w"] for c in COMMUNITIES]
    comm_by_id = {c["id"]: c for c in COMMUNITIES}
    uid_n = 0

    def new_name(fem):
        for _ in range(500):
            f = rng.choice(FEM if fem else MAS)
            s = rng.choice(SUR)
            if fem and not s.endswith("ý"):
                s2 = s + "ová" if not s.endswith("a") else s[:-1] + "ová"
            elif fem:
                s2 = s[:-1] + "á"
            else:
                s2 = s
            nm = f + " " + s2
            if nm not in names_used:
                names_used.add(nm)
                return f, s2
        raise RuntimeError("nedostatek jmen")

    for hi, size in enumerate(sizes):
        cid = wchoice(rng, comm_ids, comm_w)
        comm = comm_by_id[cid]
        hid = "dom_%02d" % (hi + 1)
        tier = rng.choice(comm["tiers"])
        lo, hi_age = comm["age"]
        base_age = rng.randint(lo, hi_age)
        members = []
        for mi in range(size):
            if mi == 0:
                age = base_age
            elif mi == 1 and size >= 2:
                age = int(clamp(base_age + rng.randint(-8, 8), 18, 90))
            else:
                age = int(clamp(base_age + rng.randint(-30, 6), 18, 90))  # dospělé děti / příbuzní / spolubydlící
            fem = rng.random() < 0.52
            first, last = new_name(fem)
            members.append((first, last, fem, age))
        hh_members = []
        for (first, last, fem, age) in members:
            uid_n += 1
            nm = first + " " + last
            # latentní osy (0..1), z nich se odvozuje osobnost, ekonomika a investorský profil
            profile = wchoice(rng, PROFILES, [PROFILE_W[p] for p in PROFILES])
            imp = {"panic": beta(rng, 5, 2), "momentum": beta(rng, 5, 2), "cautious": beta(rng, 2, 4), "passive": beta(rng, 1.5, 5),
                   "contrarian": beta(rng, 2, 3), "balanced": beta(rng, 3, 3)}[profile]
            anx = {"panic": beta(rng, 4, 2.5), "cautious": beta(rng, 4, 3)}.get(profile, beta(rng, 2, 4))
            indep = beta(rng, 5, 2) if profile == "contrarian" else beta(rng, 2, 3)
            hexaco = {k: round(clamp(rng.gauss(0, 0.45), -1, 1), 2) for k in
                      ["honesty", "emotionality", "extraversion", "agreeableness", "conscientiousness", "openness"]}
            hexaco["emotionality"] = round(clamp(hexaco["emotionality"] + (anx - 0.4) * 0.8, -1, 1), 2)
            tl = {t: round(beta(rng, 2, 2.5), 2) for t in TRAITS}
            tl["impulzivni"] = round(clamp(imp), 2)
            tl["uzkostlivy"] = round(clamp(anx), 2)
            tl["cynik"] = round(clamp(0.25 + 0.6 * indep + rng.uniform(-0.15, 0.15)), 2)
            tl["spolecensky"] = round(clamp(0.5 + hexaco["extraversion"] * 0.5 + rng.uniform(-0.2, 0.2)), 2)
            tl["samotar"] = round(clamp(0.5 - hexaco["extraversion"] * 0.5 + rng.uniform(-0.2, 0.2)), 2)
            tl["brucoun"] = round(clamp(tl["brucoun"] + (-hexaco["agreeableness"]) * 0.25), 2)
            legacy = []
            cost = 0
            for t in sorted(TRAITS, key=lambda t: -tl[t]):
                if len(legacy) >= 3 or any({t, u} in [set(c) for c in CONFLICTS] for u in legacy) or cost + TRAIT_COST[t] > 4:
                    continue
                legacy.append(t)
                cost += TRAIT_COST[t]
            disp = {k: round(beta(rng, 2, 2), 2) for k in DISP}
            disp["impulsivity"] = round(clamp(imp), 2)
            disp["threat_sensitivity"] = round(clamp(0.3 * disp["threat_sensitivity"] + 0.7 * anx), 2)
            disp["regulation_capacity"] = round(clamp(1.0 - 0.5 * imp - 0.2 * anx + rng.uniform(-0.1, 0.25)), 2)
            pred = {}
            for k, p in PREDISP.items():
                pp = p * (1.6 if k in ("anxiety", "social_anxiety") and anx > 0.6 else 1.0)
                if rng.random() < pp:
                    pred[k] = round(rng.uniform(0.35, 0.95), 2)
            mind = {"predispositions": pred, "dispositions": disp, "morning_worse": rng.random() < 0.25,
                    "traumas": rng.sample(TRAUMAS, rng.choice([1, 1, 2])) if rng.random() < 0.27 else [],
                    "self_defectiveness": round(clamp(rng.betavariate(1.2, 6)), 2)}
            if rng.random() < 0.18:
                mind["neuro"] = {k: round(rng.uniform(0.2, 0.9), 2) for k in
                                 rng.sample(["attention_drift", "hyperfocus", "sens_sound", "social_energy", "masking_cost",
                                             "direct_communication"], 3)}
            if rng.random() < 0.15:
                mind["mood"] = {"bipolar_tendency": round(rng.uniform(0.2, 0.8), 2), "cycling": round(rng.uniform(0.1, 0.7), 2)}
            mind["thoughts"] = {"rumination": round(clamp(0.5 + (anx - 0.4) * 0.8 + rng.uniform(-0.2, 0.2)), 2),
                                "worry": round(clamp(0.5 + (anx - 0.4) * 0.9 + rng.uniform(-0.2, 0.2)), 2)}
            subs = {}
            for k, p in (("caffeine", 0.5), ("nicotine", 0.2), ("alcohol", 0.3), ("gaming", 0.12), ("gambling", 0.04)):
                if rng.random() < p:
                    subs[k] = round(rng.uniform(0.2, 0.8), 2)
            if subs:
                mind["substances"] = subs
            # ekonomika
            if age >= 65:
                wg = "duchod"
            elif age < 24 and rng.random() < 0.35:
                wg = "brigadnici"
            else:
                wg = wchoice(rng, [g["id"] for g in WORK_GROUPS[:8]], [14, 16, 11, 8, 12, 12, 8, 7])
            if rng.random() < 0.06 and wg not in ("duchod", "bez_prace"):
                wg = "bez_prace"
            wgd = next(g for g in WORK_GROUPS if g["id"] == wg)
            wcls = wchoice(rng, WEALTH, [w[0] for w in WEALTH])
            endow = rng.randint(wcls[1] // 100, wcls[2] // 100) * 100
            if wg == "duchod":
                endow = int(endow * 0.8) // 100 * 100
            ch = {"uid": "%016x" % (0x5a110000 + uid_n),
                  "identity": {"first_name": first, "last_name": last, "grammar": "f" if fem else "m",
                               "gender_identity": "zena" if fem else "muz",
                               "attracted_to": rng.choice([["muzi"], ["zeny"], ["muzi", "zeny"]]) if rng.random() < 0.9 else ["zeny" if fem else "muzi"]},
                  "body": {"age": age, "height_cm": round(rng.gauss(165 if fem else 178, 6), 1)},
                  "personality": {"traits": legacy, "trait_levels": tl, "hexaco": hexaco, "psyche_seed": rng.randint(0, 65535),
                                  "aspirations": rng.sample(ASPIR, 2)},
                  "story": {"family": rng.choice(["oba_rodice", "jeden_rodic", "prarodice", "neuvedeno"]),
                            "childhood": rng.choice(["klidne", "chude", "prisne", "chaoticke", "stehovani", "klidne", "klidne"]),
                            "hometown": rng.choice(["Údolí", "Údolí", "Most", "Kladno", "Brno", "Plzeň"])},
                  "mind": mind}
            chars.append(ch)
            hh_members.append(nm)
            pop_agents[nm] = {"household": hid, "community": cid, "group": wg, "age": age, "profile": profile,
                              "tier": tier, "job": wgd["job"], "skill": wgd["skill"], "endowment": endow,
                              "shift_off": rng.randint(0, 6), "wealth_class": WEALTH.index(wcls),
                              "predispositions": sorted(pred.keys()), "traumas": mind["traumas"]}
        households.append({"id": hid, "community": cid, "tier": tier, "members": hh_members})
        # vztahy v domácnosti: pár (první dva dospělí s malým věkovým rozdílem) silně, ostatní střední
        for i in range(len(hh_members)):
            for j in range(i + 1, len(hh_members)):
                a, b = hh_members[i], hh_members[j]
                if i == 0 and j == 1 and abs(pop_agents[a]["age"] - pop_agents[b]["age"]) <= 12:
                    v = rng.randint(55, 85)
                else:
                    v = rng.randint(20, 65)
                if rng.random() < 0.08:
                    v = rng.randint(-35, 5)   # napjatý domácí vztah
                rel_pairs.append([a, b, v])
    all_names = list(pop_agents.keys())
    seen = {(a, b) for a, b, _ in rel_pairs}
    seen |= {(b, a) for a, b, _ in rel_pairs}

    def add_pair(a, b, v):
        if a == b or (a, b) in seen:
            return False
        seen.add((a, b)); seen.add((b, a))
        rel_pairs.append([a, b, v])
        return True
    # pracovní skupiny: kolegové (každý max 4 náhodné vazby, +5..+30; v malých skupinách všichni)
    for g in WORK_GROUPS:
        mem = [n for n in all_names if pop_agents[n]["group"] == g["id"]]
        for a in mem:
            for b in rng.sample(mem, min(4, len(mem))):
                add_pair(a, b, rng.randint(5, 30))
    # komunity: sousedé (každý 3 náhodné vazby, 0..+20)
    for c in COMMUNITIES:
        mem = [n for n in all_names if pop_agents[n]["community"] == c["id"]]
        for a in mem:
            for b in rng.sample(mem, min(3, len(mem))):
                add_pair(a, b, rng.randint(0, 20))
    # rivalové: ~n/8 záporných dvojic (stejná skupina nebo komunita)
    tries = 0
    nr = 0
    while nr < max(1, len(all_names) // 8) and tries < 2000:
        tries += 1
        a = rng.choice(all_names)
        pool = [n for n in all_names if n != a and (pop_agents[n]["group"] == pop_agents[a]["group"] or pop_agents[n]["community"] == pop_agents[a]["community"])]
        if not pool:
            continue
        b = rng.choice(pool)
        if (a, b) in seen:
            continue
        add_pair(a, b, -rng.randint(20, 55))
        nr += 1
    pop = {"version": 1, "seed": seed, "n": len(chars), "communities": COMMUNITIES and [{"id": c["id"], "title": c["title"]} for c in COMMUNITIES],
           "groups": [{"id": g["id"], "title": g["title"], "job": g["job"]} for g in WORK_GROUPS],
           "households": households, "agents": pop_agents, "relations": rel_pairs,
           "note": "Fiktivní populace; rozdělení a pravděpodobnosti jsou návrhové předpoklady (game_balance), ne data o lidech."}
    return chars, pop


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=20261)
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--out", default="tools/lab/experiments")
    ap.add_argument("--prefix", default="udoli_v1")
    a = ap.parse_args()
    chars, pop = build(a.seed, a.n)
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, a.prefix + "_household.json"), "w", encoding="utf-8") as f:
        json.dump(chars, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    with open(os.path.join(a.out, a.prefix + "_population.json"), "w", encoding="utf-8") as f:
        json.dump(pop, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    print("OK n=%d domácností=%d vztahů=%d" % (len(chars), len(pop["households"]), len(pop["relations"])))


if __name__ == "__main__":
    main()
