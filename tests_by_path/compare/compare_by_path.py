"""
compare_by_path.py  --  check that Stata, R and Python agree on by_path

Reads the files written by the three language scripts:
    results/{stata,r,python}_results.csv
    results/{stata,r,python}_validation.csv
    results/{stata,r,python}_meta.txt
and checks, for every case in cases.csv, with Stata as the reference:

  run        every language ran the case without error
  paths      the same set of treatment paths is estimated
  order      paths come out in the same order (WARN only)
  n_groups   same number of groups per path (Stata vs Python; R does not export it)
  rows       the same statistics exist for each path (Effect_k, Av_tot_eff,
             Placebo_k, joint-test p-values)
  values     estimate, SE, CI bounds, N and switchers agree
  stata_int  Stata's displayed by_path(#) output agrees with its full-precision
             by_path(k) runs (sanity check of the harness itself)
  validation each invalid input is accepted/rejected the same way as in Stata

Tolerance for floating-point values:  |x - stata| <= atol + rtol * |stata|
(defaults atol = 1e-7, rtol = 1e-6, i.e. ~7 significant digits). Stata stores
intermediate variables as float, so bit-for-bit equality is not attainable.
When only Stata's displayed value is available, half a unit of its last
displayed digit is added to the tolerance. N and switchers must match exactly.

Usage:
    python tests_by_path/compare/compare_by_path.py [--rtol 1e-6] [--atol 1e-7]
Exit code 0 when there is no FAIL, 1 otherwise.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
import sys
from collections import OrderedDict, defaultdict
from pathlib import Path

TB_DIR = Path(__file__).resolve().parent.parent
RESULTS_DIR = TB_DIR / "results"
LANGS = ["stata", "r", "python"]
OTHERS = ["r", "python"]
FLOAT_FIELDS = ["estimate", "se", "lb_ci", "ub_ci"]
COUNT_FIELDS = ["n", "switchers"]
P_ROWS = {"p_joint_effects", "p_joint_placebos"}


# ----------------------------------------------------------------------------
# Parsing helpers
# ----------------------------------------------------------------------------
def canon_value(tok: str) -> str:
    tok = tok.strip()
    if tok in ("", ".", "NA", "nan", "NaN", "None"):
        return "NA"
    try:
        x = float(tok)
    except ValueError:
        return tok
    if math.isnan(x):
        return "NA"
    return str(int(x)) if x.is_integer() else f"{x:.10g}"


def canon_path(label: str) -> str:
    """'1, 0, 0' / '1,0,0' / '1.0,0.0,0.0' -> '1,0,0'."""
    return ",".join(canon_value(t) for t in re.split(r"[,;|]", label or ""))


def to_float(s: str):
    s = (s or "").strip()
    if s in ("", ".", "NA", "nan", "NaN"):
        return None
    try:
        x = float(s)
    except ValueError:
        return None
    return None if math.isnan(x) else x


def display_tol(s: str) -> float:
    """Half a unit of the last digit shown in a Stata-displayed number."""
    s = (s or "").strip().lower()
    if not s:
        return 0.0
    mant, _, exp = s.partition("e")
    dec = len(mant.split(".")[1]) if "." in mant else 0
    scale = 10.0 ** int(exp) if exp else 1.0
    return 0.5 * 10.0 ** (-dec) * scale


def read_csv(path: Path):
    with open(path, newline="", encoding="utf-8-sig") as fh:
        return [{k: (v or "").strip() for k, v in r.items()} for r in csv.DictReader(fh)]


def read_meta(lang: str) -> dict:
    p = RESULTS_DIR / f"{lang}_meta.txt"
    if not p.exists():
        return {}
    out = {}
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def build(rows, source=None):
    """case -> {'status','message','paths': OrderedDict(label -> info)}"""
    data = {}
    for r in rows:
        if source and r.get("source") != source:
            continue
        c = data.setdefault(r["case_id"], {"status": "ok", "message": "", "paths": OrderedDict()})
        if r["status"] == "case_error":
            c["status"], c["message"] = "case_error", r["message"]
            continue
        label = canon_path(r["path"])
        p = c["paths"].setdefault(label, {"order": r["path_order"], "n_groups": r["n_groups"],
                                          "status": "ok", "message": "", "rows": {}})
        if r["status"] == "path_error":
            p["status"], p["message"] = "path_error", r["message"]
            continue
        if r["row"]:
            p["rows"][r["row"]] = r
    return data


# ----------------------------------------------------------------------------
# Comparison
# ----------------------------------------------------------------------------
class Report:
    def __init__(self):
        self.checks = []

    def add(self, case, check, status, lang="", path="", row="", field="",
            ref="", other="", diff="", detail=""):
        self.checks.append(dict(case=case, check=check, status=status, lang=lang, path=path,
                                row=row, field=field, stata=ref, other=other, diff=diff,
                                detail=detail))


def compare_values(rep, case, lang, label, rowname, ref_row, ref_is_display, oth_row,
                   rtol, atol, maxdiff):
    fields = ["estimate"] if rowname in P_ROWS else FLOAT_FIELDS + COUNT_FIELDS
    for f in fields:
        a_s, b_s = ref_row.get(f, ""), oth_row.get(f, "")
        a, b = to_float(a_s), to_float(b_s)
        if a is None and b is None:
            continue
        if a is None:
            rep.add(case, "values", "WARN", lang, label, rowname, f, a_s, b_s,
                    detail="value reported by this language but missing in Stata")
            continue
        if b is None:
            rep.add(case, "values", "FAIL", lang, label, rowname, f, a_s, b_s,
                    detail="value missing in this language")
            continue
        diff = abs(a - b)
        if f in COUNT_FIELDS:
            ok = round(a) == round(b)
        else:
            tol = atol + rtol * abs(a) + (display_tol(a_s) if ref_is_display else 0.0)
            ok = diff <= tol
            rel = diff / max(abs(a), 1e-12)
            key = (case, lang)
            maxdiff[key] = max(maxdiff.get(key, (0.0, 0.0)), (rel, diff))
        if not ok:
            rep.add(case, "values", "FAIL", lang, label, rowname, f, a_s, b_s, f"{diff:.3g}",
                    "display-precision reference" if ref_is_display else "")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rtol", type=float, default=1e-6)
    ap.add_argument("--atol", type=float, default=1e-7)
    args = ap.parse_args()

    cases = read_csv(TB_DIR / "cases.csv")
    vcases = read_csv(TB_DIR / "validation_cases.csv")
    rep = Report()
    maxdiff = {}

    loaded, missing_langs = {}, []
    for lang in LANGS:
        f = RESULTS_DIR / f"{lang}_results.csv"
        if f.exists():
            loaded[lang] = read_csv(f)
        else:
            missing_langs.append(lang)

    if "stata" not in loaded:
        print("ERROR: results/stata_results.csv not found - Stata is the reference, run it first.")
        return 1

    stata_disp = build(loaded["stata"], "display")
    stata_prec = build(loaded["stata"], "precise")
    stata_enum = build(loaded["stata"], "enum")
    other = {lang: build(loaded[lang]) for lang in OTHERS if lang in loaded}
    # (case, path, row, field) -> {lang: value string}, used to tell whether
    # R and Python agree with each other when they disagree with Stata
    all_vals = defaultdict(dict)
    for lang, d in other.items():
        for cid, c in d.items():
            for label, pinfo in c["paths"].items():
                for rn, r in pinfo["rows"].items():
                    for f in FLOAT_FIELDS + COUNT_FIELDS:
                        all_vals[(cid, label, rn, f)][lang] = r.get(f, "")

    for cs in cases:
        cid = cs["case_id"]
        sd = stata_disp.get(cid)
        if sd is None:
            rep.add(cid, "run", "FAIL", "stata", detail="case not run by Stata")
            continue
        if sd["status"] != "ok":
            rep.add(cid, "run", "FAIL", "stata", detail=sd["message"])
            continue
        sp = stata_prec.get(cid, {"paths": {}})

        # Stata internal consistency: displayed by_path(#) vs precise by_path(k)
        for label, pinfo in sp["paths"].items():
            dinfo = sd["paths"].get(label)
            if pinfo["status"] != "ok":
                if dinfo is not None:
                    rep.add(cid, "stata_int", "FAIL", "stata", label,
                            detail="by_path(#) printed this path but the by_path(k) run did not")
                continue
            if dinfo is None:
                rep.add(cid, "stata_int", "FAIL", "stata", label,
                        detail="path from by_path(k) run not in the by_path(#) output")
                continue
            for rn, prow in pinfo["rows"].items():
                drow = dinfo["rows"].get(rn)
                if drow is None:
                    rep.add(cid, "stata_int", "FAIL", "stata", label, rn, detail="row missing in display")
                    continue
                for f in (["estimate"] if rn in P_ROWS else FLOAT_FIELDS + COUNT_FIELDS):
                    a, b = to_float(drow.get(f)), to_float(prow.get(f))
                    if a is None and b is None:
                        continue
                    if a is None or b is None or abs(a - b) > display_tol(drow.get(f)) + 1e-12:
                        rep.add(cid, "stata_int", "FAIL", "stata", label, rn, f,
                                drow.get(f, ""), prow.get(f, ""))

        # Reference = Stata display paths, with precise rows where available
        ref_paths = OrderedDict()
        for label, dinfo in sd["paths"].items():
            pinfo = sp["paths"].get(label)
            use_precise = pinfo is not None and pinfo["status"] == "ok" and pinfo["rows"]
            ref_paths[label] = dict(dinfo, rows=(pinfo["rows"] if use_precise else dinfo["rows"]),
                                    display=not use_precise)
        rep.add(cid, "run", "PASS", "stata", detail=f"{len(ref_paths)} paths")

        for lang in OTHERS:
            if lang not in other:
                rep.add(cid, "run", "FAIL", lang, detail=f"results/{lang}_results.csv not found")
                continue
            od = other[lang].get(cid)
            if od is None:
                rep.add(cid, "run", "FAIL", lang, detail="case not run")
                continue
            if od["status"] != "ok":
                rep.add(cid, "run", "FAIL", lang, detail=od["message"])
                continue
            rep.add(cid, "run", "PASS", lang, detail=f"{len(od['paths'])} paths")

            s_set, o_set = list(ref_paths), list(od["paths"])
            skipped = [p for p in stata_enum.get(cid, {"paths": {}})["paths"] if p not in ref_paths]
            miss = [p for p in s_set if p not in od["paths"]]
            extra, extra_skipped = [], []
            for p in o_set:
                if p in ref_paths:
                    continue
                op = od["paths"][p]
                has_results = op["status"] == "ok" and bool(op["rows"])
                if p in skipped:
                    # Stata enumerated the path but printed nothing: fine if this
                    # language also produced nothing for it
                    if has_results:
                        extra_skipped.append(p)
                else:
                    extra.append(p)
            if miss or extra or extra_skipped:
                bits = []
                if miss:
                    bits.append(f"missing: {miss}")
                if extra:
                    bits.append(f"extra (Stata does not enumerate): {extra}")
                if extra_skipped:
                    bits.append(f"results for paths Stata skips: {extra_skipped}")
                rep.add(cid, "paths", "FAIL", lang, detail=" | ".join(bits))
            else:
                rep.add(cid, "paths", "PASS", lang, detail=f"{len(s_set)} paths")
            common = [p for p in s_set if p in od["paths"]]
            if [p for p in o_set if p in ref_paths] != common:
                rep.add(cid, "order", "WARN", lang,
                        detail=f"stata: {s_set} | {lang}: {o_set}")

            for label in common:
                rp, op = ref_paths[label], od["paths"][label]
                if op["status"] != "ok":
                    rep.add(cid, "run", "FAIL", lang, label, detail=f"path error: {op['message']}")
                    continue
                if lang == "python" and rp["n_groups"] and op["n_groups"]:
                    if to_float(rp["n_groups"]) != to_float(op["n_groups"]):
                        rep.add(cid, "n_groups", "FAIL", lang, label, ref=rp["n_groups"],
                                other=op["n_groups"])
                for rn in rp["rows"]:
                    if rn not in op["rows"]:
                        rep.add(cid, "rows", "FAIL", lang, label, rn,
                                detail="statistic reported by Stata but missing here")
                for rn in op["rows"]:
                    if rn not in rp["rows"]:
                        status = "WARN" if rn in P_ROWS else "FAIL"
                        rep.add(cid, "rows", status, lang, label, rn,
                                detail="statistic not reported by Stata")
                for rn, srow in rp["rows"].items():
                    if rn in op["rows"]:
                        compare_values(rep, cid, lang, label, rn, srow, rp["display"],
                                       op["rows"][rn], args.rtol, args.atol, maxdiff)

    # Annotate value failures where R and Python agree with each other
    for c in rep.checks:
        if c["check"] != "values" or c["status"] != "FAIL":
            continue
        v = all_vals.get((c["case"], c["path"], c["row"], c["field"]), {})
        a, b = to_float(v.get("r")), to_float(v.get("python"))
        if a is not None and b is not None and \
                abs(a - b) <= args.atol + args.rtol * max(abs(a), abs(b)):
            c["detail"] = (c["detail"] + "; " if c["detail"] else "") + "R and Python agree, only Stata differs"

    # ---- validation ---------------------------------------------------------
    vres = {}
    for lang in LANGS:
        f = RESULTS_DIR / f"{lang}_validation.csv"
        vres[lang] = {r["vcase_id"]: r for r in read_csv(f)} if f.exists() else {}
    for v in vcases:
        vid = v["vcase_id"]
        s = vres["stata"].get(vid, {}).get("outcome", "")
        if not s:
            rep.add(vid, "validation", "FAIL", "stata", detail="not run")
            continue
        if s != v["expected"]:
            rep.add(vid, "validation", "FAIL", "stata", ref=v["expected"], other=s,
                    detail=f"by_path={v['by_path']!r}: Stata differs from the documented behaviour")
        for lang in OTHERS:
            o = vres[lang].get(vid, {}).get("outcome", "")
            status = "PASS" if o == s else "FAIL"
            rep.add(vid, "validation", status, lang, ref=s, other=o or "not run",
                    detail=f"by_path={v['by_path']!r} ({v['by_path_type']}) with_by={v['with_by']} "
                           f"{vres[lang].get(vid, {}).get('message', '')}".strip())

    # ---- write + print ------------------------------------------------------
    out_csv = RESULTS_DIR / "comparison_details.csv"
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rep.checks[0].keys()))
        w.writeheader()
        w.writerows(rep.checks)

    lines = []
    p = lines.append
    p("=" * 100)
    p("by_path cross-language comparison (reference: Stata)")
    p("=" * 100)
    for lang in LANGS:
        m = read_meta(lang)
        p(f"  {lang:<7} {m.get('package_version', '?'):<22} {m.get('package_file', 'NOT RUN')}")
    p(f"  tolerance: |x - stata| <= {args.atol:g} + {args.rtol:g}*|stata|; N and switchers exact")
    if missing_langs:
        p(f"  MISSING RESULTS: {', '.join(missing_langs)}")
    p("")
    p(f"{'case':<30} {'lang':<7} {'verdict':<7} {'fail':>5} {'warn':>5}  {'max rel diff':>12}  first problem")
    p("-" * 100)
    by_case = defaultdict(list)
    for c in rep.checks:
        by_case[(c["case"], c["lang"])].append(c)
    order = [cs["case_id"] for cs in cases] + [v["vcase_id"] for v in vcases]
    total_fail = 0
    for cid in order:
        for lang in LANGS:
            chk = by_case.get((cid, lang))
            if not chk:
                continue
            nf = sum(c["status"] == "FAIL" for c in chk)
            nw = sum(c["status"] == "WARN" for c in chk)
            if lang == "stata" and nf == 0 and nw == 0:
                continue
            total_fail += nf
            verdict = "FAIL" if nf else ("WARN" if nw else "PASS")
            md = maxdiff.get((cid, lang))
            mds = f"{md[0]:.2e}" if md else ""
            first = next((c for c in chk if c["status"] == "FAIL"), None) or \
                next((c for c in chk if c["status"] == "WARN"), None)
            desc = ""
            if first:
                bits = [first["check"], first["path"] and f"({first['path']})", first["row"],
                        first["field"], first["stata"] and f"stata={first['stata']}",
                        first["other"] and f"{lang}={first['other']}", first["detail"]]
                desc = " ".join(b for b in bits if b)[:150]
            p(f"{cid:<30} {lang:<7} {verdict:<7} {nf:>5} {nw:>5}  {mds:>12}  {desc}")
    p("-" * 100)

    # failure kinds, aggregated
    kinds = defaultdict(lambda: [0, set()])
    for c in rep.checks:
        if c["status"] == "FAIL":
            k = (c["lang"], c["check"], c["row"].split("_")[0] if c["row"] else "", c["field"],
                 c["detail"][:60] if c["check"] in ("run", "rows", "validation", "paths")
                 else ("R and Python agree" if "agree" in c["detail"] else ""))
            kinds[k][0] += 1
            kinds[k][1].add(c["case"])
    if kinds:
        p("")
        p("FAILURES grouped by kind (lang | check | row | field | detail -> count, cases)")
        for (lang, chk, rowk, field, det), (n, cs) in sorted(kinds.items(), key=lambda x: -x[1][0]):
            p(f"  {lang:<7} {chk:<10} {rowk:<16} {field:<10} {det:<60} -> {n:>4}  {', '.join(sorted(cs))[:120]}")
    p("")
    p(f"Details: {out_csv}")
    p("RESULT: " + ("ALL CHECKS PASSED" if total_fail == 0 else f"{total_fail} FAILED CHECKS"))
    text = "\n".join(lines)
    print(text)
    (RESULTS_DIR / "comparison_summary.txt").write_text(text + "\n", encoding="utf-8")
    return 0 if total_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
