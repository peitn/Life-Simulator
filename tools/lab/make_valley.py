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


BLOCK_CAP = 8   # engine: jeden dům (9 chytrých objektů) – víc než 8 obyvatel vede k saturaci stresu z tlačenice (viz docs)


def pack_blocks(households):
    """Domácnosti → „bloky“ (≤ BLOCK_CAP obyvatel), každý blok = jeden dům v enginu. Nejdřív first-fit decreasing v rámci
    komunity, pak sloučení nedoplněných bloků napříč komunitami. Deterministické (řazení podle velikosti a id)."""
    blocks = []   # {"members": [...], "households": [...], "communities": set}
    for comm in [c["id"] for c in COMMUNITIES]:
        hs = sorted([h for h in households if h["community"] == comm], key=lambda h: (-len(h["members"]), h["id"]))
        local = []
        for h in hs:
            for b in local:
                if len(b["members"]) + len(h["members"]) <= BLOCK_CAP:
                    b["members"] += h["members"]; b["households"].append(h["id"])
                    break
            else:
                b = {"members": list(h["members"]), "households": [h["id"]], "communities": {comm}}
                local.append(b)
        blocks += local
    merged = []
    for b in sorted(blocks, key=lambda b: (-len(b["members"]), b["households"][0])):
        for m in merged:
            if len(m["members"]) + len(b["members"]) <= BLOCK_CAP:
                m["members"] += b["members"]; m["households"] += b["households"]; m["communities"] |= b["communities"]
                break
        else:
            merged.append({"members": list(b["members"]), "households": list(b["households"]), "communities": set(b["communities"])})
    out = {}
    for i, b in enumerate(sorted(merged, key=lambda b: b["households"][0])):
        out["blk_%02d" % (i + 1)] = {"members": b["members"], "households": sorted(b["households"]), "communities": sorted(b["communities"])}
    return out


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
    blocks = pack_blocks(households)
    pop = {"version": 1, "seed": seed, "order": [c["identity"]["first_name"] + " " + c["identity"]["last_name"] for c in chars],
           "blocks": blocks, "n": len(chars), "communities": COMMUNITIES and [{"id": c["id"], "title": c["title"]} for c in COMMUNITIES],
           "groups": [{"id": g["id"], "title": g["title"], "job": g["job"]} for g in WORK_GROUPS],
           "households": households, "agents": pop_agents, "relations": rel_pairs,
           "note": "Fiktivní populace; rozdělení a pravděpodobnosti jsou návrhové předpoklady (game_balance), ne data o lidech."}
    return chars, pop


SOURCE = "Obecní rada Údolí"


def pick_named(pop):
    """Deterministicky vybere jednotlivce pro cílené události (bez náhody): krize = nejchudší člen s depresivní predispozicí
    (jinak nejchudší), radost = nejchudší člen bez predispozic; bereavement domácnost = první domácnost s ≥ 4 členy."""
    ag = pop["agents"]
    names = sorted(ag.keys())
    dep = [n for n in names if "depression" in ag[n]["predispositions"]]
    pool = dep if dep else names
    crisis = sorted(pool, key=lambda n: (ag[n]["wealth_class"], n))[0]
    lucky_pool = [n for n in names if not ag[n]["predispositions"] and n != crisis]
    lucky = sorted(lucky_pool, key=lambda n: (ag[n]["wealth_class"], n))[0]
    big = [h for h in pop["households"] if len(h["members"]) >= 4]
    return crisis, lucky, sorted(h["id"] for h in big)[0], sorted(h["id"] for h in big)[-1]


def build_scenario(seed, pop, days=180):
    """Scénář výzkumného běhu v1: 6 měsíců, všechny relevantní systémy zapnuty, 18 kalendářních a cílených událostí.
    day = dny od startu běhu (8:00 herního dne day+1). Ekonomické události: den ekonomiky; projeví se od herního dne day+1."""
    crisis, lucky, hh_bereave, hh_flood = pick_named(pop)
    A = lambda d, **kw: dict({"day": d, "source": SOURCE}, **kw)
    iv = [
        A(5, kind="moodlet", target="all", strength=-6, minutes=10080, emotion="smutny", label="Zimní tma a mrazy", category="sezónní"),
        A(5, kind="stressor", target="all", amount=3, label="Zimní tma a mrazy", category="sezónní"),
        A(12, kind="stressor", target=["wealth:0", "wealth:1"], amount=9, label="Zimní účty za energie", category="sezónní/finanční"),
        A(20, kind="stressor", target="group:dilna", amount=20, label="Oznámení o propouštění v Dílně", category="ekonomická/skupinová"),
        A(28, kind="stressor", target="household:" + hh_bereave, amount=45, label="Úmrtí v rodině (domácnost %s)" % hh_bereave, category="životní/skupinová"),
        A(28, kind="moodlet", target="household:" + hh_bereave, strength=-18, minutes=4320, emotion="smutny", label="Smutek v rodině", category="životní/skupinová"),
        A(35, kind="relation", a="community:dilny", b="community:stara_ctvrt", delta=-18, label="Spor o hluk z dílen", category="sociální/hádka"),
        A(55, kind="stressor", target=crisis, amount=55, label="Individuální krize (jeden agent)", category="životní/jednotlivec"),
        A(60, kind="moodlet", target="all", strength=14, minutes=4320, emotion="stastny", label="Masopustní slavnost", category="sociální/oslava"),
        A(60, kind="relation", a="all", b="all", delta=4, label="Masopustní slavnost", category="sociální/oslava"),
        A(70, kind="stressor", target=["group:obchodni_rada", "group:kuryrni_sluzba"], amount=8, label="Recese: pokles tržeb obchodů a kurýrů", category="ekonomická/skupinová"),
        A(85, kind="relation", a="community:dilny", b="community:stara_ctvrt", delta=15, label="Smíření po sporu o hluk", category="sociální/smíření"),
        A(90, kind="stressor", target="all", amount=6, label="Termín daňového přiznání", category="kalendářní"),
        A(95, kind="moodlet", target=lucky, strength=16, minutes=4320, emotion="stastny", label="Výhra v tombole (jeden agent)", category="životní/jednotlivec"),
        A(110, kind="moodlet", target="group:technicky_ustav", strength=10, minutes=4320, emotion="stastny", label="Odměny v Technickém ústavu", category="ekonomická/skupinová"),
        A(120, kind="stressor", target="age:65-95", amount=16, label="Chřipková vlna u starších", category="zdravotní/skupinová"),
        A(130, kind="moodlet", target="all", strength=12, minutes=4320, emotion="stastny", label="Letní festival", category="sociální/oslava"),
        A(130, kind="relation", a="all", b="all", delta=3, label="Letní festival", category="sociální/oslava"),
        A(140, kind="stressor", target="all", amount=5, label="Vedro", category="sezónní"),
        A(150, kind="stressor", target="community:recni_nabrezi", amount=38, label="Povodeň na Říčním nábřeží", category="přírodní/skupinová"),
        A(150, kind="moodlet", target="community:recni_nabrezi", strength=-14, minutes=10080, emotion="smutny", label="Škody po povodni", category="přírodní/skupinová"),
        A(152, kind="relation", a="community:recni_nabrezi", b="community:recni_nabrezi", delta=10, label="Sousedská solidarita po povodni", category="sociální/smíření"),
        A(165, kind="relation", a="group:urad", b="group:technicky_ustav", delta=-25, label="Hádka úřadu s Technickým ústavem", category="sociální/hádka"),
        A(165, kind="stressor", target=["group:urad", "group:technicky_ustav"], amount=10, label="Hádka úřadu s Technickým ústavem", category="sociální/hádka"),
        A(175, kind="relation", a="group:urad", b="group:technicky_ustav", delta=14, label="Smíření úřadu a ústavu", category="sociální/smíření"),
    ]
    eco_events = [
        {"type": "layoffs", "day": 20, "share_pm": 300, "label": "Propouštění (Dílna a okolí)", "source": SOURCE},
        {"type": "path", "day": 42, "days": 5, "total_pm": -350, "scope": "market", "label": "Krach na burze −35 %", "source": SOURCE},
        {"type": "vol", "day": 47, "days": 20, "mult_pm": 2000, "label": "Zvýšená volatilita po krachu", "source": SOURCE},
        {"type": "rates", "day": 70, "loan_rate_add_bp": 400, "label": "Recese: dražší úvěry", "source": SOURCE},
        {"type": "div_cut", "day": 70, "days": 60, "cut_pm": 400, "scope": "market", "label": "Recese: škrt dividend", "source": SOURCE},
        {"type": "layoffs", "day": 72, "share_pm": 200, "label": "Recese: druhá vlna propouštění", "source": SOURCE},
        {"type": "path", "day": 100, "days": 20, "total_pm": 250, "scope": "market", "label": "Růst burzy +25 %", "source": SOURCE},
    ]
    iv.sort(key=lambda e: (e["day"], e["label"]))
    return {
        "name": "udoli_v1", "seed": seed, "days": days, "long_run": True, "snapshot_hours": 24, "snapshot_mode": "compact",
        "household_file": "res://tools/lab/experiments/udoli_v1_household.json",
        "population_file": "res://tools/lab/experiments/udoli_v1_population.json",
        "settings": {"mental_health": "full", "intrusive_thoughts": 3, "distortion_fx": True, "distortion_strength": 1.0,
                     "addiction": True, "profanity": True, "adult_intimacy": True, "sh_ed_topics": False},
        "economy": {"enabled": True, "market": True, "use_population": True, "events": eco_events},
        "interventions": iv,
    }


def control_of(sc):
    """Kontrolní rameno: stejná populace, nastavení, ekonomika a seed, ale BEZ intervencí a BEZ událostí burzy/ekonomiky."""
    c = json.loads(json.dumps(sc))
    c["name"] = sc["name"] + "_control"
    c["interventions"] = []
    c["economy"].pop("events", None)
    return c


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
    if a.n == 100:
        # sim seed odvozen z generátorového seedu; scénář se zapisuje vedle dat
        with open(os.path.join(a.out, a.prefix + ".json"), "w", encoding="utf-8") as f:
            json.dump(build_scenario(a.seed, pop), f, ensure_ascii=False, indent=1, sort_keys=False)
        with open(os.path.join(a.out, a.prefix + "_control.json"), "w", encoding="utf-8") as f:
            json.dump(control_of(build_scenario(a.seed, pop)), f, ensure_ascii=False, indent=1, sort_keys=False)
    print("OK n=%d domácností=%d vztahů=%d" % (len(chars), len(pop["households"]), len(pop["relations"])))


if __name__ == "__main__":
    main()
