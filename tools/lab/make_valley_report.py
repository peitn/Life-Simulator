#!/usr/bin/env python3
"""Z výstupů analyze_valley.py (CSV) vyrobí samostatné HTML s inline SVG grafy (bez závislostí, ~50 kB).
Použití: python3 tools/lab/make_valley_report.py docs/lab/research_run_v1 docs/lab/research_run_v1/report.html"""
import csv, json, os, sys, html

d, out = sys.argv[1], sys.argv[2]
A = json.load(open(os.path.join(d, "analysis.json"), encoding="utf-8"))
sc = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "experiments/udoli_v1.json"), encoding="utf-8"))


def rd(name):
    p = os.path.join(d, name)
    if not os.path.exists(p):
        return None
    return [{k: float(v) if k != "label" else v for k, v in r.items()} for r in csv.DictReader(open(p, encoding="utf-8"))]


ev, ct = rd("daily_all_events.csv"), rd("daily_all_control.csv")
W, H, L, R, T, B = 760, 220, 46, 12, 14, 26
C_EV, C_CT = "#1f6fb2", "#c8641e"


def line_chart(title, key, series, ymin=None, ymax=None, markers=True):
    vals = [r[key] for s in series for r in s[1]]
    lo = min(vals) if ymin is None else ymin
    hi = max(vals) if ymax is None else ymax
    if hi - lo < 1e-9:
        hi = lo + 1
    X = lambda x: L + (W - L - R) * x / 180.0
    Y = lambda y: T + (H - T - B) * (1 - (y - lo) / (hi - lo))
    g = ['<svg viewBox="0 0 %d %d" role="img" aria-label="%s">' % (W, H, html.escape(title))]
    for i in range(5):
        v = lo + (hi - lo) * i / 4
        g.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" class="grid"/><text x="%d" y="%.1f" class="ax" text-anchor="end">%.3g</text>' % (L, W - R, Y(v), Y(v), L - 5, Y(v) + 4, v))
    for dday in range(0, 181, 30):
        g.append('<text x="%.1f" y="%d" class="ax" text-anchor="middle">%d</text>' % (X(dday), H - 8, dday))
    if markers:
        for e in sc["interventions"] + sc["economy"]["events"]:
            g.append('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" class="ev"><title>den %d: %s</title></line>' % (X(e["day"]), X(e["day"]), T, H - B, e["day"], html.escape(e["label"])))
    for name, rows, col in series:
        pts = " ".join("%.1f,%.1f" % (X(r["day"]), Y(r[key])) for r in rows)
        g.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="2"/>' % (pts, col))
    g.append("</svg>")
    leg = "".join('<span><i style="background:%s"></i>%s</span>' % (col, n) for n, _, col in series)
    return '<figure><figcaption>%s</figcaption><div class="leg">%s</div>%s</figure>' % (html.escape(title), leg, "".join(g))


ser = [("události", ev, C_EV)] + ([("kontrola (bez událostí)", ct, C_CT)] if ct else [])
parts = [line_chart("Průměrný stres (0–100), denní průměr přes 100 agentů", "mean_stress", ser),
         line_chart("Průměrná nálada (−100…100)", "mean_mood", ser),
         line_chart("Průměrný vztah k ostatním v bloku", "mean_rel", ser),
         line_chart("Průměrný finanční tlak (0–1)", "mean_pressure", ser),
         line_chart("Průměrná starost z poklesu portfolia (0–1)", "mean_worry", ser),
         line_chart("Index fiktivní burzy (start = 1)", "market_index", ser),
         line_chart("Gini zůstatků", "gini", ser, 0.0, 1.0),
         line_chart("Míra chudoby", "poverty", ser, 0.0, 1.0)]
# sloupcový graf reakcí
rows = [r for r in A["event_response"]]
seen, uniq = set(), []
for r in rows:
    k = (r["day"], r["label"])
    if k not in seen:
        seen.add(k); uniq.append(r)
key = "did_stress" if "did_stress" in uniq[0] else "d_stress"
bw = 14
svg = ['<svg viewBox="0 0 760 %d" role="img" aria-label="Změna stresu po událostech">' % (len(uniq) * bw + 30)]
mx = max(abs(r[key]) for r in uniq) or 1
cx = 420
for i, r in enumerate(uniq):
    y = 10 + i * bw
    w = 250 * r[key] / mx
    svg.append('<text x="410" y="%d" class="ax" text-anchor="end">%d · %s</text>' % (y + 10, r["day"], html.escape(r["label"][:44])))
    svg.append('<rect x="%.1f" y="%d" width="%.1f" height="10" fill="%s" rx="2"><title>%s: %+.2f (n=%d)</title></rect>' % (min(cx, cx + w), y, abs(w), C_EV, html.escape(r["label"]), r[key], r["n_affected"]))
svg.append('<line x1="%d" x2="%d" y1="6" y2="%d" class="grid"/></svg>' % (cx, cx, len(uniq) * bw + 12))
cap = "Změna stresu: týden po události minus týden před (%s)" % ("rozdíl proti kontrole, diff-in-diff" if key == "did_stress" else "bez kontroly")
parts.append('<figure><figcaption>%s</figcaption>%s</figure>' % (cap, "".join(svg)))
page = """<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Údolí – výzkumný běh v1</title><style>
:root{--bg:#fff;--fg:#1d2430;--mut:#5b6573;--grid:#e3e7ee;--ev:#9aa3b2}
@media(prefers-color-scheme:dark){:root{--bg:#14181f;--fg:#e6e9ef;--mut:#9aa3b2;--grid:#2a313c;--ev:#566074}}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:15px/1.45 system-ui,sans-serif;max-width:800px}
h1{font-size:20px}figure{margin:18px 0}figcaption{font-weight:600}svg{width:100%%;height:auto}
.grid{stroke:var(--grid)}.ev{stroke:var(--ev);stroke-dasharray:3 3}.ax{fill:var(--mut);font-size:11px}
.leg span{margin-right:14px;font-size:13px;color:var(--mut)}.leg i{display:inline-block;width:12px;height:3px;margin-right:5px;vertical-align:middle}
p.n{color:var(--mut);font-size:13px}</style></head><body>
<h1>Údolí – výzkumný běh v1 (100 fiktivních agentů, 180 dní)</h1>
<p class="n">Jen model s fiktivními agenty a parametry game_balance; nic neplatí pro lidi. Svislé čárkované čáry = události (najeď myší pro popis). Jeden seed na rameno.</p>
%s</body></html>""" % "".join(parts)
open(out, "w", encoding="utf-8").write(page)
print("OK", out, len(page))
