"""
selftest.py  --  check that compare.py itself works

Takes an existing results/stata folder and builds a scratch results folder where
  r      = an exact copy of Stata's outputs        -> every check must PASS
  python = Stata's outputs with three planted errors:
             * one estimate changed by 1%          -> must be FAIL
             * one element deleted                 -> must be MISSING
             * one extra by_path unit with results -> must be a FAIL in "units"
Then runs compare.py on it and verifies exactly those outcomes.

Usage:  python compare/selftest.py [<results folder with a stata/ subfolder>]
Exit code 0 when compare.py behaves as expected.
"""

from __future__ import annotations

import csv
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SUITE = Path(__file__).resolve().parent.parent
src = Path(sys.argv[1]) if len(sys.argv) > 1 else SUITE / "results"
if not (src / "stata" / "outputs.csv").exists():
    sys.exit(f"no {src / 'stata' / 'outputs.csv'}: run Stata first")


def read(p):
    with open(p, newline="", encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def write(p, rows, fields):
    with open(p, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


tmp = Path(tempfile.mkdtemp(prefix="dcdh_selftest_"))
try:
    shutil.copytree(src / "stata", tmp / "stata", ignore=shutil.ignore_patterns("logs"))
    out = read(src / "stata" / "outputs.csv")
    status = read(src / "stata" / "status.csv")
    fields = list(out[0].keys())
    vf = src / "stata" / "validation.csv"
    vrows = read(vf) if vf.exists() else [{"vid": "", "outcome": "", "message": ""}]
    for lang in ("r", "python"):
        (tmp / lang).mkdir()
        (tmp / lang / "meta.txt").write_text(f"language={lang}\npackage_version=selftest copy of Stata\n")
        write(tmp / lang / "validation.csv", vrows, list(vrows[0].keys()))
        write(tmp / lang / "status.csv", status, list(status[0].keys()))
    write(tmp / "r" / "outputs.csv", out, fields)

    # planted errors for "python"
    bad = [dict(r) for r in out]
    ok_specs = {s["spec_id"] for s in status if s["status"] == "ok" and s["unit"] == ""}
    i_change = next(i for i, r in enumerate(bad) if r["spec_id"] in ok_specs and r["kind"] == "e_scalar"
                    and r["name"] == "Effect_1" and r["value"])
    bad[i_change]["value"] = repr(float(bad[i_change]["value"]) * 1.01)
    changed = (bad[i_change]["spec_id"], "Effect_1")
    i_drop = next(i for i, r in enumerate(bad) if r["spec_id"] in ok_specs and r["kind"] == "e_scalar"
                  and r["name"] == "se_effect_1" and r["spec_id"] != changed[0])
    dropped = (bad[i_drop]["spec_id"], "se_effect_1")
    del bad[i_drop]
    bp = next((r for r in bad if r["unit"].startswith("path=")), None)
    extra = None
    if bp:
        extra = (bp["spec_id"], "path=9,9,9")
        bad.append(dict(bp, unit="path=9,9,9", kind="e_scalar", name="Effect_1", value="0.5", precision="full"))
    write(tmp / "python" / "outputs.csv", bad, fields)

    rc = subprocess.run([sys.executable, str(SUITE / "compare" / "compare.py"), str(tmp)],
                        capture_output=True, text=True).returncode
    det = read(tmp / "details.csv")
    probs = []
    r_bad = [d for d in det if d["lang"] == "r" and d["status"] in ("FAIL", "MISSING", "ERROR")
             and d["check"] != "validation"]
    if r_bad:
        probs.append(f"exact copy of Stata produced {len(r_bad)} problems, e.g. {r_bad[0]}")
    py = [d for d in det if d["lang"] == "python" and d["status"] in ("FAIL", "MISSING", "ERROR")
          and d["check"] != "validation"]
    hit_change = any(d["spec_id"] == changed[0] and d["element"] == "Effect_1" and d["status"] == "FAIL" for d in py)
    hit_drop = any(d["spec_id"] == dropped[0] and d["element"] == "se_effect_1" and d["status"] == "MISSING" for d in py)
    hit_extra = extra is None or any(d["spec_id"] == extra[0] and d["unit"] == extra[1] and d["check"] == "units"
                                     and d["status"] == "FAIL" for d in py)
    expected = 2 + (extra is not None)
    if not hit_change:
        probs.append(f"changed value {changed} not reported as FAIL")
    if not hit_drop:
        probs.append(f"deleted element {dropped} not reported as MISSING")
    if not hit_extra:
        probs.append(f"extra unit {extra} not reported")
    if len(py) != expected:
        probs.append(f"expected exactly {expected} python problems, got {len(py)}: {[(d['spec_id'], d['element'], d['status']) for d in py][:8]}")
    if rc != 1:
        probs.append(f"compare.py exit code {rc}, expected 1")
    if probs:
        print("SELFTEST FAILED")
        for p in probs:
            print("  -", p)
        sys.exit(1)
    print(f"SELFTEST PASSED: identical copy passes ({sum(d['lang'] == 'r' and d['status'] == 'PASS' for d in det)} checks); "
          f"planted errors caught: changed {changed}, deleted {dropped}, extra unit {extra}")
finally:
    shutil.rmtree(tmp, ignore_errors=True)
