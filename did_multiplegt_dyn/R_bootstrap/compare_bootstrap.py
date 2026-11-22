"""
compare_bootstrap.py -- verdicts for the R bootstrap tests (see README.md)

Reads <results>/r_bootstrap.csv, r_status.csv and (if present) stata_manual.csv,
writes <results>/bootstrap_report.txt and bootstrap_details.csv.

Checks, per estimate (Effect_k, Av_tot_eff, Placebo_k) of every bootstrap spec:
  point        bootstrap point estimate == analytic point estimate (R)
  counts       N and switchers unchanged by bootstrap(...)
  reproducible same seed twice -> identical SE                       (A vs B)
  replay       saved resamples loaded back -> identical SE           (A vs C)
  method       saved resamples, row_replication method -> same SE    (A vs E)
  active       another seed gives another SE; SE finite and > 0      (A vs D)
  stata_point  R analytic estimate == Stata analytic estimate        (needs stata_manual.csv)
  stata_se     R bootstrap SE == Stata's SE on the SAME resamples    (needs stata_manual.csv)
  stata_boot   R SE / Stata bootstrap(reps,seed) SE within [0.5, 2]  (different draws: WARN only)
Exit code 1 if any check FAILS.

Usage: python R_bootstrap/compare_bootstrap.py [<results folder>] [--rtol 1e-6]
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent


def rd(p):
    if not p.exists():
        return []
    with open(p, newline="", encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def f(x):
    try:
        v = float(x)
        return None if math.isnan(v) else v
    except (TypeError, ValueError):
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results", nargs="?", default=str(HERE / "results"))
    ap.add_argument("--rtol", type=float, default=1e-6)
    a = ap.parse_args()
    res = Path(a.results)
    rows, status = rd(res / "r_bootstrap.csv"), rd(res / "r_status.csv")
    man = {(m["bid"], m["row"]): m for m in rd(res / "stata_manual.csv") if m.get("row")}
    man_msg = {m["bid"]: m["message"] for m in rd(res / "stata_manual.csv") if not m.get("row")}
    out = []
    meta = (res / "r_meta.txt").read_text(encoding="utf-8") if (res / "r_meta.txt").exists() else ""
    r_done = "finished_at=" in meta

    def add(bid, unit, row, check, st, x="", y="", detail=""):
        out.append(dict(bid=bid, unit=unit, row=row, check=check, status=st, value_1=x, value_2=y, detail=detail))

    def close(x, y, rtol, atol=1e-12):
        return x is not None and y is not None and abs(x - y) <= atol + rtol * abs(x)

    if not r_done:
        add("(all)", "", "", "run", "ERROR", detail="R did not finish (crash or still running): see r_console.log; "
            "specs after the last one written were not tested")
    if not rows and not status:
        add("(all)", "", "", "run", "ERROR", detail="no R bootstrap results at all")
    for s in status:
        if s["status"] != "ok":
            add(s["bid"], "", "", "run", "NOT_SUPPORTED" if s["status"] == "not_supported" else "ERROR",
                detail=s["message"])
        elif "errors:" in s["message"]:
            add(s["bid"], "", "", "run", "ERROR", detail=s["message"].split("errors:", 1)[1].strip())
    for r in rows:
        b, u, rn = r["bid"], r["unit"], r["row"]
        ea, eb = f(r["est_analytic"]), f(r["est_boot"])
        add(b, u, rn, "point", "PASS" if close(ea, eb, 1e-10) or (ea is None and eb is None) else "FAIL", r["est_analytic"], r["est_boot"])
        cnt_ok = r["n_analytic"] == r["n_boot"] and r["sw_analytic"] == r["sw_boot"]
        add(b, u, rn, "counts", "PASS" if cnt_ok else "FAIL", f"{r['n_analytic']}/{r['sw_analytic']}", f"{r['n_boot']}/{r['sw_boot']}")
        sa, sb, sc, sd, se = (f(r[k]) for k in ("se_A", "se_B", "se_C", "se_D", "se_E"))
        if sa is None:
            add(b, u, rn, "active", "FAIL" if ea is not None else "PASS", r["se_A"], "", "bootstrap SE missing")
            continue
        add(b, u, rn, "reproducible", "PASS" if close(sa, sb, 1e-12) else "FAIL", r["se_A"], r["se_B"])
        add(b, u, rn, "replay", "PASS" if close(sa, sc, 1e-10) else "FAIL", r["se_A"], r["se_C"])
        add(b, u, rn, "method", "PASS" if close(sa, se, 1e-8) else ("ERROR" if se is None else "FAIL"), r["se_A"], r["se_E"])
        act = sa > 0 and math.isfinite(sa) and sd is not None and abs(sa - sd) > 1e-12 * sa
        add(b, u, rn, "active", "PASS" if act else "FAIL", r["se_A"], r["se_D"],
            "" if act else "a different seed gave the same SE (or SE <= 0)")
        m = man.get((b, rn))
        if m is not None and u == "":
            x = f(m["est_analytic"])
            add(b, u, rn, "stata_point", "PASS" if close(x, ea, a.rtol, 1e-9) else "FAIL", m["est_analytic"], r["est_analytic"])
            sm = f(m["se_manual"])
            if sm is not None:
                ok = close(sm, sa, a.rtol, 1e-9)
                add(b, u, rn, "stata_se", "PASS" if ok else "FAIL", m["se_manual"], r["se_A"],
                    f"{m['reps_used']} of {r['reps']} replications replayed in Stata")
            sbt = f(m["se_stata_bootstrap"])
            if sbt:
                ratio = sa / sbt
                add(b, u, rn, "stata_boot", "PASS" if 0.5 <= ratio <= 2 else "WARN", m["se_stata_bootstrap"], r["se_A"],
                    f"ratio R/Stata = {ratio:.2f} (different random draws)")
    for b, msg in man_msg.items():
        add(b, "", "", "stata_point", "ERROR", detail=msg)

    with open(res / "bootstrap_details.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(out[0]) if out else ["bid"])
        w.writeheader()
        w.writerows(out)
    by = defaultdict(list)
    for o in out:
        by[o["bid"]].append(o)
    lines = ["=" * 110, "R bootstrap tests", "=" * 110]
    for mfile in ("r_meta.txt", "stata_meta.txt"):
        p = res / mfile
        if p.exists():
            lines += ["  " + mfile + ": " + "; ".join(l for l in p.read_text().splitlines() if l.startswith("package"))]
    checks = ["point", "counts", "reproducible", "replay", "method", "active", "stata_point", "stata_se", "stata_boot"]
    lines += ["", f"{'bid':<6} {'verdict':<14} " + " ".join(f"{c[:12]:>12}" for c in checks) + "  first problem", "-" * 110]
    for b in sorted(by):
        rr = by[b]
        c = Counter(o["status"] for o in rr)
        v = "ERROR" if c["ERROR"] else "FAIL" if c["FAIL"] else "NOT_SUPPORTED" if c["NOT_SUPPORTED"] else "WARN" if c["WARN"] else "PASS"
        cells = []
        for ch in checks:
            sub = [o for o in rr if o["check"] == ch]
            if not sub:
                cells.append(f"{'-':>12}")
            else:
                nb = sum(o["status"] in ("FAIL", "ERROR") for o in sub)
                cells.append(f"{(str(nb) + ' bad') if nb else 'ok':>12}" if sub[0]["status"] != "WARN" or nb else f"{'warn':>12}")
        first = next((o for o in rr if o["status"] in ("FAIL", "ERROR")), None) or next((o for o in rr if o["status"] in ("WARN", "NOT_SUPPORTED")), None)
        desc = f"{first['check']} {first['unit']} {first['row']} {first['value_1']} vs {first['value_2']} {first['detail']}"[:110] if first else ""
        lines.append(f"{b:<6} {v:<14} " + " ".join(cells) + "  " + desc)
    nbad = sum(o["status"] in ("FAIL", "ERROR") for o in out)
    lines += ["", f"Details: {res / 'bootstrap_details.csv'}", "RESULT: " + ("ALL CHECKS PASSED" if nbad == 0 else f"{nbad} FAILED / ERROR CHECKS")]
    text = "\n".join(lines)
    print(text)
    (res / "bootstrap_report.txt").write_text(text + "\n", encoding="utf-8")
    return 1 if nbad else 0


if __name__ == "__main__":
    sys.exit(main())
