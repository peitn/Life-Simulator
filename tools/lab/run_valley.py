#!/usr/bin/env python3
"""Ovladač výzkumného běhu "Údolí": pro každé rameno (events/control), seed a blok spustí jeden proces lab_cli (sériově, 2 CPU).
Výstupy: <out>/<arm>_s<seed>/<blok>.json + log. Přeskočí hotové bloky (lze přerušit a navázat). Pokud existuje soubor
<out>/PAUSE, před spuštěním dalšího bloku čeká (aby šly mezitím spouštět jiné Godot procesy).
Použití: python3 tools/lab/run_valley.py <godot> <out> --arms events,control --seeds 20310 [--days 180]"""
import argparse, json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("godot")
    ap.add_argument("out")
    ap.add_argument("--arms", default="events,control")
    ap.add_argument("--seeds", default="20310")
    ap.add_argument("--days", type=int, default=0, help="0 = celý scénář; jinak kratší běh (--stop-day, jen pro zkoušku)")
    a = ap.parse_args()
    exp = os.path.join(ROOT, "tools/lab/experiments")
    pop = json.load(open(os.path.join(exp, "udoli_v1_population.json"), encoding="utf-8"))
    blocks = sorted(pop["blocks"].keys())
    log = open(os.path.join(a.out, "driver.log"), "a", encoding="utf-8")
    def say(m):
        line = time.strftime("%H:%M:%S ") + m
        print(line, flush=True); log.write(line + "\n"); log.flush()
    for arm in a.arms.split(","):
        scen = "res://tools/lab/experiments/udoli_v1.json" if arm == "events" else "res://tools/lab/experiments/udoli_v1_control.json"
        for seed in [int(x) for x in a.seeds.split(",")]:
            d = os.path.join(a.out, "%s_s%d" % (arm, seed))
            os.makedirs(d, exist_ok=True)
            for b in blocks:
                outp = os.path.join(d, b + ".json")
                if os.path.exists(outp):
                    continue
                while os.path.exists(os.path.join(a.out, "PAUSE")):
                    time.sleep(10)
                t0 = time.time()
                cmd = [a.godot, "--headless", "--path", ROOT, "res://tools/lab/lab_cli.tscn", "--", "--scenario=" + scen,
                       "--block=" + b, "--seed=%d" % seed, "--out=" + outp + ".part"]
                if a.days:
                    cmd += ["--stop-day=%d" % a.days, "--checkpoint-out=" + os.path.join(d, b + ".cp")]
                r = subprocess.run(cmd, capture_output=True, text=True)
                ok = r.returncode == 0 and os.path.exists(outp + ".part")
                if ok:
                    os.replace(outp + ".part", outp)
                else:
                    open(os.path.join(d, b + ".err"), "w").write(r.stdout[-3000:] + r.stderr[-3000:])
                say("%s s%d %s ok=%s %.0fs" % (arm, seed, b, ok, time.time() - t0))
    say("HOTOVO")

if __name__ == "__main__":
    main()
