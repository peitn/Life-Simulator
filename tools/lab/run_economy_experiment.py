#!/usr/bin/env python3
"""Laboratoř: spouštěč experimentu "ekonomika → psychika" (docs/lab/EXPERIMENT_economy_psyche_v1.md).
Tři ramena na seed: e0 = bez ekonomiky, calm = ekonomika + burza bez šoku, crash = ekonomika + burza + krach (-30 % za 3 dny) ve dni 3.
8 klonů téže postavy (tools/lab/experiments/identical8_household.json), 10 dní, snímky po 6 h.
Použití: run_economy_experiment.py <godot_binárka> <výstupní_adresář> [seedy, výchozí 301..312] [paralelně, výchozí 2]
Jeden běh = jeden proces (lab_cli.tscn). Už existující výstupy se přeskočí (lze pokračovat po přerušení)."""
import json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ARMS = ["e0", "calm", "crash"]


def scenario(arm, seed, household):
    sc = {"name": "economy_%s_%d" % (arm, seed), "seed": seed, "days": 10, "snapshot_hours": 6, "household": household}
    if arm == "calm":
        sc["economy"] = {"enabled": True, "market": True}
    elif arm == "crash":
        sc["economy"] = {"enabled": True, "market": True, "shock": {"day": 3, "total_pm": -300, "days": 3}}
    return sc


def run_one(args):
    godot, outdir, arm, seed, household = args
    out = os.path.join(outdir, "out_%s_%d.json" % (arm, seed))
    if os.path.exists(out):
        return out, "skip"
    sc_path = os.path.join(outdir, "sc_%s_%d.json" % (arm, seed))
    json.dump(scenario(arm, seed, household), open(sc_path, "w"))
    r = subprocess.run([godot, "--headless", "--path", ROOT, "res://tools/lab/lab_cli.tscn", "--",
                        "--scenario=" + sc_path, "--out=" + out], capture_output=True, text=True)
    os.remove(sc_path)
    return out, "ok" if r.returncode == 0 else "FAIL(%d)" % r.returncode


def main():
    godot, outdir = sys.argv[1], sys.argv[2]
    seeds = [int(x) for x in sys.argv[3].split(",")] if len(sys.argv) > 3 else list(range(301, 313))
    par = int(sys.argv[4]) if len(sys.argv) > 4 else 2
    os.makedirs(outdir, exist_ok=True)
    household = json.load(open(os.path.join(ROOT, "tools/lab/experiments/identical8_household.json")))
    jobs = [(godot, outdir, a, s, household) for s in seeds for a in ARMS]
    with ThreadPoolExecutor(max_workers=par) as ex:
        for out, st in ex.map(run_one, jobs):
            print(st, out, flush=True)


if __name__ == "__main__":
    main()
