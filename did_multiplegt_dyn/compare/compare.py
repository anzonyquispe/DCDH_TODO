"""
compare.py  --  check that R and Python reproduce Stata (the reference)

Reads <results>/{stata,r,python}/{outputs,status,validation,meta}.* and the
shared files in specs/, and writes in <results>/:
    report.txt     human-readable summary (also printed)
    summary.csv    one row per (spec, language)
    details.csv    one row per individual check

What is compared, per spec and per estimation unit (a by_path path or a by()
level is its own unit), with Stata as the reference:
  units      the same paths / levels are estimated (an extra unit with
             results, or a missing one, FAILS)
  elements   every e() scalar, e() macro, e() matrix cell and global matrix
             cell Stata stores, under Stata's name:
               scalars  Effect_k, se_effect_k, N_effect_k, N_switchers_effect_k,
                        Placebo_k ..., Av_tot_effect ..., p_jointeffects,
                        p_jointplacebo, p_equality_effects, *_w, switch_dates*
               macros   cmd, effects, placebo
               matrices b, V, mat_res_XX (all 7 columns), desmat (design),
                        dfs# (date_first_switch), effect_het_* (predict_het)
             For by()/by_path() units Stata only prints some numbers; those
             are compared at Stata's displayed precision.
  golden     specs listed in specs/golden.csv are also compared with saved
             Stata results (used when the Stata under test cannot run them)
  validation each input in specs/validation.csv is accepted / rejected as in Stata

Statuses: PASS, FAIL (value differs), MISSING (Stata has it, language does
not), EXTRA (language has it, Stata does not: warning), ROUNDED (the language
returns a rounded number that agrees to its last digit: warning), NOT_SUPPORTED
(specs/not_supported.csv or an option the package lacks: not counted),
ERROR (the language crashed), STATA_NOT_SUPPORTED / STATA_ERROR (no reference).
Elements that only Stata stores by design are in specs/stata_only.csv.

Tolerance: |x - stata| <= atol + rtol*|stata| (+ half a displayed digit when
only Stata's displayed value exists); counts (N, switchers, #groups) exact.

Usage:  python compare/compare.py [<results folder>] [--rtol 1e-6] [--atol 1e-7]
Exit code 0 when nothing FAILS / is MISSING / ERRORS, 1 otherwise.
"""

from __future__ import annotations

import argparse
import csv
import fnmatch
import math
import re
import sys
from collections import Counter, OrderedDict, defaultdict
from pathlib import Path

SUITE = Path(__file__).resolve().parent.parent
LANGS = ["stata", "r", "python"]
OTHERS = ["r", "python"]
BAD = {"FAIL", "MISSING", "ERROR"}
OPTION_OUTPUTS = {  # element-name patterns produced by an option's extra output
    "design": ["desmat"],
    "predict_het": ["effect_het_*"],
    "date_first_switch": ["dfs*", "switch_dates*"],
}


# ----------------------------------------------------------------------------
def read_csv(p: Path):
    if not p.exists():
        return None
    with open(p, newline="", encoding="utf-8-sig") as fh:
        return [{k: (v or "").strip() for k, v in r.items()} for r in csv.DictReader(fh)]


def read_meta(p: Path) -> dict:
    if not p.exists():
        return {}
    out = {}
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def to_float(s):
    s = (s or "").strip()
    if s in ("", ".", "NA", "nan", "NaN", "None"):
        return None
    try:
        x = float(s)
    except ValueError:
        return None
    return None if math.isnan(x) else x


def display_tol(s: str) -> float:
    s = (s or "").strip().lower()
    if not s:
        return 0.0
    mant, _, exp = s.partition("e")
    dec = len(mant.split(".")[1]) if "." in mant else 0
    return 0.5 * 10.0 ** (-dec) * (10.0 ** int(exp) if exp else 1.0)


def canon_unit(u: str) -> str:
    """'path=0, 1, .' -> 'path=0,1,NA'; 'level=1.0' -> 'level=1'."""
    if "=" not in u:
        return u
    kind, val = u.split("=", 1)
    parts = []
    for t in re.split(r"[,;]", val):
        t = t.strip()
        if t in (".", "", "NA", "nan", "None"):
            parts.append("NA")
            continue
        try:
            x = float(t)
            parts.append(str(int(x)) if x.is_integer() else f"{x:.10g}")
        except ValueError:
            parts.append(t)
    return f"{kind}=" + ",".join(parts)


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


AV = norm("Av_tot_eff")                  # label of the total-effect row/column of e(V)
AV_V = ("matrix", "V", AV, AV)
AV_SE = ("scalar", "se_avg_total_effect", "", "")


def element_key(r: dict):
    """Language-independent key of one stored element."""
    kind, name = r["kind"], r["name"]
    if kind in ("e_scalar",):
        return ("scalar", name, "", "")
    if kind == "e_macro":
        return ("macro", name, "", "")
    if kind in ("e_matrix", "matrix"):
        if name == "b":
            return ("matrix", "b", "", norm(r["colname"]))
        if name == "V":
            return ("matrix", "V", norm(r["rowname"]), norm(r["colname"]))
        if name == "desmat":
            return ("matrix", "desmat", r["row"], r["col"])
        return ("matrix", name, norm(r["rowname"]), r["col"])
    if kind == "display":  # Stata log, display precision
        if name == "mat_res_XX":
            return ("matrix", "mat_res_XX", norm(r["rowname"]), r["col"])
        return ("scalar", name, "", "")
    return None


def is_count(key) -> bool:
    cat, name, row, col = key
    if cat == "scalar":
        return name.startswith("N_") or name.startswith("switch_dates")
    if name == "mat_res_XX":
        return col in ("5", "6", "7")
    if name == "desmat" or name.startswith("dfs"):
        return col == "1"
    return False


def option_names(opts: str):
    return set(re.findall(r"([A-Za-z_][A-Za-z_0-9]*)(?=\(|\s|$)", opts))


# ----------------------------------------------------------------------------
def load_lang(res: Path, lang: str):
    d = res / lang
    out = read_csv(d / "outputs.csv")
    st = read_csv(d / "status.csv")
    if out is None or st is None:
        return None
    units = defaultdict(lambda: OrderedDict())   # spec -> unit -> status row
    for r in st:
        units[r["spec_id"]][canon_unit(r["unit"])] = r
    elems = defaultdict(dict)                     # (spec, unit) -> key -> (value, precision)
    enum = defaultdict(list)
    other = defaultdict(list)                     # stata-only / ignored rows, for info
    for r in out:
        u = canon_unit(r["unit"])
        if r["kind"] == "path_enum":
            enum[r["spec_id"]].append(u)
            continue
        k = element_key(r)
        if k is None:
            other[(r["spec_id"], u)].append(r)
            continue
        prev = elems[(r["spec_id"], u)].get(k)
        # full precision wins over display precision
        if prev is None or (prev[1] == "display" and r["precision"] != "display"):
            elems[(r["spec_id"], u)][k] = (r["value"], r["precision"], r["kind"])
    if lang != "stata":
        # Stata's e(V) has an Av_tot_eff row/column whose diagonal is se_avg_total_effect^2.
        # R and Python keep the total effect in a separate table (results$ATE /
        # result["did_multiplegt_dyn"]["ATE"]), not in their vcov: use its SE squared.
        for e in elems.values():
            s = e.get(AV_SE)
            if s is not None and AV_V not in e and to_float(s[0]) is not None:
                e[AV_V] = (repr(to_float(s[0]) ** 2), s[1], "e_matrix")
    return dict(units=units, elems=elems, enum=enum, other=other,
                validation={r["vid"]: r for r in (read_csv(d / "validation.csv") or [])},
                finished="finished_at" in read_meta(d / "meta.txt"),
                meta=read_meta(d / "meta.txt"))


class Report:
    def __init__(self):
        self.rows = []

    def add(self, spec, lang, check, status, unit="", element="", stata="", other="", diff="", detail=""):
        self.rows.append(dict(spec_id=spec, lang=lang, check=check, status=status, unit=unit,
                              element=element, stata=stata, other=other, diff=diff, detail=detail))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("results", nargs="?", default=str(SUITE / "results"))
    ap.add_argument("--rtol", type=float, default=1e-6)
    ap.add_argument("--atol", type=float, default=1e-7)
    a = ap.parse_args()
    res = Path(a.results)

    specs = read_csv(SUITE / "specs" / "specs.csv")
    vcases = read_csv(SUITE / "specs" / "validation.csv")
    notsup = read_csv(SUITE / "specs" / "not_supported.csv")
    stata_only = read_csv(SUITE / "specs" / "stata_only.csv")
    golden = {g["spec_id"]: g for g in read_csv(SUITE / "specs" / "golden.csv") or []}

    L = {lang: load_lang(res, lang) for lang in LANGS}
    if L["stata"] is None:
        print("ERROR: no Stata results (results/stata/outputs.csv). Stata is the reference: run it first.")
        return 1
    S = L["stata"]
    rep = Report()
    maxdiff = defaultdict(float)

    def stata_only_match(kind, name):
        return any(so["kind"] == kind and fnmatch.fnmatch(name, so["name"]) for so in stata_only)

    def flagged_output(lang, opts, ename):
        for ns in notsup:
            if ns["lang"] == lang and ns["scope"] == "output" and ns["option"] in opts:
                if any(fnmatch.fnmatch(ename, pat) for pat in OPTION_OUTPUTS.get(ns["option"], [])):
                    return ns["reason"]
        return None

    ran_specs = [s for s in specs if s["spec_id"] in S["units"]]
    for s in ran_specs:
        sid = s["spec_id"]
        opts = option_names(s["options"])
        s_units = S["units"][sid]
        main = s_units.get("") or next(iter(s_units.values()))
        stata_state = main["status"]
        if stata_state != "ok":
            label = "STATA_NOT_SUPPORTED" if stata_state == "not_supported" else "STATA_ERROR"
            for lang in OTHERS:
                if L[lang] is None:
                    continue
                lu = L[lang]["units"].get(sid)
                ran = "not run" if lu is None else ", ".join(sorted({r["status"] for r in lu.values()}))
                rep.add(sid, lang, "reference", label, detail=f"Stata: {main['message']} | {lang}: {ran}")
            continue

        # Stata units that carry results (display or precise elements)
        ref_units = [u for u in OrderedDict.fromkeys([k[1] for k in S["elems"] if k[0] == sid])]
        is_multi = any(u.startswith(("path=", "level=")) for u in ref_units)
        if is_multi:
            ref_units = [u for u in ref_units if u.startswith(("path=", "level="))]

        for lang in OTHERS:
            O = L[lang]
            if O is None:
                rep.add(sid, lang, "run", "ERROR", detail=f"results/{lang} not found")
                continue
            lu = O["units"].get(sid)
            if lu is None:
                rep.add(sid, lang, "run", "ERROR", detail="spec not run")
                continue
            lmain = lu.get("") or next(iter(lu.values()))
            if lmain["status"] == "not_supported":
                rep.add(sid, lang, "run", "NOT_SUPPORTED", detail=lmain["message"])
                continue
            if lmain["status"] == "error" and "" in lu:
                rep.add(sid, lang, "run", "ERROR", detail=lmain["message"])
                continue
            rep.add(sid, lang, "run", "PASS")

            o_units = [u for u in OrderedDict.fromkeys([k[1] for k in O["elems"] if k[0] == sid])]
            if is_multi:
                o_units = [u for u in o_units if u.startswith(("path=", "level="))]
                miss = [u for u in ref_units if u not in o_units]
                extra = [u for u in o_units if u not in ref_units]
                for u in miss:
                    st = lu.get(u, {})
                    rep.add(sid, lang, "units", "MISSING", u,
                            detail=f"Stata estimates this {u.split('=')[0]}; {lang}: {st.get('status', 'absent')} {st.get('message', '')}".strip())
                for u in extra:
                    enum = u in S["enum"].get(sid, [])
                    rep.add(sid, lang, "units", "FAIL", u,
                            detail="results for a path Stata enumerates but does not estimate" if enum
                            else "results for a path/level Stata does not have")
                if not miss and not extra:
                    rep.add(sid, lang, "units", "PASS", detail=f"{len(ref_units)} units")
                errs = [(u, r) for u, r in lu.items() if r["status"] == "error" and u in ref_units]
                for u, r in errs:
                    rep.add(sid, lang, "run", "ERROR", u, detail=r["message"])

            units = ref_units if is_multi else [""]
            for u in units:
                if is_multi and u not in o_units:
                    continue
                se, oe = S["elems"].get((sid, u), {}), O["elems"].get((sid, u), {})
                used_w = set()   # language *_w scalars matched to Stata's N_* under weight()
                for key, (sv, sprec, skind) in se.items():
                    cat, name, row, col = key
                    # With weight(), Stata's e(N_*) scalars hold the WEIGHTED count (ado: total of the
                    # weighted cell counts); its table (mat_res_XX) shows the unweighted one. R and
                    # Python call the weighted count N_*_w and keep the unweighted one as N_*.
                    weighted = ("weight" in opts and cat == "scalar" and name.startswith("N_")
                                and not name.endswith("_w") and ("scalar", name + "_w", "", "") in oe)
                    if weighted:
                        used_w.add(("scalar", name + "_w", "", ""))
                    ename = name if not row and not col else f"{name}[{row},{col}]".replace("[,", "[").replace(",]", "]")
                    if stata_only_match(skind, name):
                        continue
                    if name == "V" and AV in (row, col) and row != col:
                        continue  # Stata fills these with 0; they are not estimated covariances
                    fr = flagged_output(lang, opts, name)
                    if fr:
                        rep.add(sid, lang, "element", "NOT_SUPPORTED", u, ename, sv, oe.get(key, ("",))[0], detail=fr)
                        continue
                    if key not in oe and not weighted:
                        if to_float(sv) is None and cat != "macro":
                            continue  # Stata stores a missing value; nothing to compare
                        rep.add(sid, lang, "element", "MISSING", u, ename, sv, "",
                                detail="Stata stores it, this language does not return it")
                        continue
                    ov = oe[("scalar", name + "_w", "", "")][0] if weighted else oe[key][0]
                    if weighted:
                        ename = f"{name} (vs {lang} {name}_w)"
                    if cat == "macro":
                        ok = norm(sv) == norm(ov)
                        rep.add(sid, lang, "element", "PASS" if ok else "FAIL", u, ename, sv, ov)
                        continue
                    x, y = to_float(sv), to_float(ov)
                    if x is None and y is None:
                        continue
                    if x is None or y is None:
                        rep.add(sid, lang, "element", "FAIL", u, ename, sv, ov,
                                detail="missing value in " + ("Stata" if x is None else lang))
                        continue
                    diff = abs(x - y)
                    if is_count(key) and not weighted:   # weighted counts are not whole numbers
                        ok = round(x) == round(y)
                    else:
                        tol = a.atol + a.rtol * abs(x) + (display_tol(sv) if sprec == "display" else 0.0)
                        ok = diff <= tol
                        maxdiff[(sid, lang)] = max(maxdiff[(sid, lang)], diff / max(abs(x), 1e-12))
                    st = "PASS" if ok else "FAIL"
                    # the language returns a rounded number (e.g. a share as "31.47"):
                    # equal within half a unit of its last digit -> ROUNDED (warning)
                    if not ok and any(abs(round(x, d) - y) <= 1e-9 * max(1.0, abs(y)) for d in range(5)):
                        st = "ROUNDED"
                    rep.add(sid, lang, "element", st, u, ename, sv, ov, f"{diff:.3g}",
                            "display-precision reference" if sprec == "display" and not ok else
                            ("this language returns a rounded value" if st == "ROUNDED" else ""))
                for key, (ov, _, okind) in oe.items():
                    if key in se or key in used_w:
                        continue
                    if any(k2[1] == key[1] for k2 in se) or key[0] == "scalar":
                        # an element Stata does not store (e.g. *_w without weights)
                        if to_float(ov) is None and key[0] != "macro":
                            continue
                        cat, name, row, col = key
                        ename = name if not row and not col else f"{name}[{row},{col}]"
                        rep.add(sid, lang, "element", "EXTRA", u, ename, "", ov,
                                detail="returned by this language, not stored by Stata")

    # ---- golden files (saved Stata results) ---------------------------------
    for sid, g in golden.items():
        p = SUITE / "data" / g["file"]
        if not p.exists():
            continue
        try:
            import pandas as pd
            gd = pd.read_stata(p)
        except Exception as e:  # noqa: BLE001
            rep.add(sid, "stata", "golden", "ERROR", detail=f"cannot read {g['file']}: {e}")
            continue
        for lang in LANGS:
            if L[lang] is None:
                continue
            el = L[lang]["elems"].get((sid, ""), {})
            if not el:
                continue
            # rows of mat_res_XX by time_to_treat
            by_t = defaultdict(dict)
            for (cat, name, row, col), (v, _, _) in el.items():
                if name == "mat_res_XX":
                    by_t[row][col] = v
            t2row = {to_float(c.get("7")): c for c in by_t.values() if to_float(c.get("7")) is not None}
            nbad = nchk = 0
            for _, gr in gd.iterrows():
                t = float(gr["time_to_treat"])
                if t == 0:
                    continue
                c = t2row.get(t)
                if c is None:
                    rep.add(sid, lang, "golden", "MISSING", element=f"time_to_treat={t:g}", detail=g["file"])
                    nbad += 1
                    continue
                for j, gcol in enumerate(["point_estimate", "se_point_estimate", "lb_CI_95", "up_CI_95", "N", "N_switchers"], 1):
                    x, y = float(gr[gcol]), to_float(c.get(str(j)))
                    if y is None:
                        continue
                    nchk += 1
                    ok = round(x) == round(y) if j >= 5 else abs(x - y) <= a.atol + a.rtol * abs(x)
                    if not ok:
                        nbad += 1
                        rep.add(sid, lang, "golden", "FAIL", element=f"t={t:g} {gcol}", stata=repr(x), other=c.get(str(j)),
                                diff=f"{abs(x - y):.3g}", detail=f"vs saved {g['file']}")
            if nchk and not nbad:
                rep.add(sid, lang, "golden", "PASS", detail=f"{nchk} values vs saved {g['file']}")

    # ---- validation ---------------------------------------------------------
    for v in vcases:
        vid = v["vid"]
        s = S["validation"].get(vid, {}).get("outcome", "")
        if not s:
            rep.add(vid, "stata", "validation", "ERROR", detail="not run")
            continue
        if s not in ("not_supported",) and s != v["expected_stata"]:
            rep.add(vid, "stata", "validation", "WARN", stata=v["expected_stata"], other=s,
                    detail=f"{v['test_option']}: Stata differs from the documented behaviour")
        for lang in OTHERS:
            if L[lang] is None:
                continue
            o = L[lang]["validation"].get(vid, {})
            oo = o.get("outcome", "")
            if s == "not_supported":
                st = "STATA_NOT_SUPPORTED"
            elif oo == "not_supported":
                st = "NOT_SUPPORTED"
            elif not oo:
                st = "ERROR"
            else:
                st = "PASS" if oo == s else "FAIL"
            rep.add(vid, lang, "validation", st, stata=s, other=oo or "not run",
                    detail=f"{v['test_option']} ({v['value_type']}) {o.get('message', '')}".strip())

    # ---- annotate value failures where R and Python agree --------------------
    vals = defaultdict(dict)
    for r in rep.rows:
        if r["check"] == "element":
            vals[(r["spec_id"], r["unit"], r["element"])][r["lang"]] = r["other"]
    for r in rep.rows:
        if r["check"] == "element" and r["status"] == "FAIL":
            v = vals[(r["spec_id"], r["unit"], r["element"])]
            x, y = to_float(v.get("r")), to_float(v.get("python"))
            if x is not None and y is not None and abs(x - y) <= a.atol + a.rtol * max(abs(x), abs(y)):
                r["detail"] = (r["detail"] + "; " if r["detail"] else "") + "R and Python agree, only Stata differs"

    write_outputs(res, rep, specs, vcases, L, maxdiff, a)
    return 1 if any(r["status"] in BAD for r in rep.rows) else 0


def verdict(rows):
    c = Counter(r["status"] for r in rows)
    for st in ("STATA_ERROR", "STATA_NOT_SUPPORTED", "ERROR"):
        if c.get(st):
            return st, c
    if c.get("FAIL") or c.get("MISSING"):
        return "FAIL", c
    if c.get("NOT_SUPPORTED") and not c.get("PASS"):
        return "NOT_SUPPORTED", c
    if c.get("NOT_SUPPORTED"):
        return "PASS*", c
    return ("WARN" if c.get("EXTRA") or c.get("WARN") or c.get("ROUNDED") else "PASS"), c


def write_outputs(res, rep, specs, vcases, L, maxdiff, a):
    rows = rep.rows
    with open(res / "details.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) if rows else ["spec_id"])
        w.writeheader()
        w.writerows(rows)
    by = defaultdict(list)
    for r in rows:
        by[(r["spec_id"], r["lang"])].append(r)
    spec_by_id = {s["spec_id"]: s for s in specs}
    order = [s["spec_id"] for s in specs] + [v["vid"] for v in vcases]
    summary = []
    for sid in order:
        for lang in LANGS:
            rr = by.get((sid, lang))
            if not rr:
                continue
            v, c = verdict(rr)
            first = next((r for r in rr if r["status"] in BAD | {"STATA_ERROR", "STATA_NOT_SUPPORTED"}), None) or \
                next((r for r in rr if r["status"] in ("NOT_SUPPORTED", "WARN")), None)
            desc = ""
            if first:
                bits = [first["check"], first["unit"] and f"({first['unit']})", first["element"],
                        first["stata"] and f"stata={first['stata']}", first["other"] and f"{lang}={first['other']}",
                        first["detail"]]
                desc = " ".join(b for b in bits if b)[:160]
            summary.append(dict(spec_id=sid, block=spec_by_id.get(sid, {}).get("block", "H"), lang=lang, verdict=v,
                                n_pass=c.get("PASS", 0), n_fail=c.get("FAIL", 0), n_missing=c.get("MISSING", 0),
                                n_extra=c.get("EXTRA", 0), n_not_supported=c.get("NOT_SUPPORTED", 0),
                                max_rel_diff=f"{maxdiff[(sid, lang)]:.2e}" if (sid, lang) in maxdiff else "",
                                first_problem=desc))
    with open(res / "summary.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(summary[0].keys()) if summary else ["spec_id"])
        w.writeheader()
        w.writerows(summary)

    out = []
    p = out.append
    p("=" * 118)
    p("did_multiplegt_dyn cross-language test suite -- reference: Stata")
    p("=" * 118)
    for lang in LANGS:
        m = (L[lang] or {}).get("meta", {})
        p(f"  {lang:<7} {m.get('package_version', 'NOT RUN'):<24} {m.get('package_source', '')}")
    p(f"  tolerance: |x - stata| <= {a.atol:g} + {a.rtol:g}*|stata|; counts exact")
    p("")
    # per-block totals
    tot = defaultdict(Counter)
    for s in summary:
        tot[(s["block"], s["lang"])][s["verdict"]] += 1
    p("Verdicts per block (specs):")
    p(f"  {'block':<6} {'lang':<7} " + "  ".join(f"{k:>19}" for k in
      ["PASS", "PASS*", "FAIL", "ERROR", "NOT_SUPPORTED", "STATA_NOT_SUPPORTED", "STATA_ERROR"]))
    for (b, lang) in sorted(tot):
        if lang == "stata":
            continue
        c = tot[(b, lang)]
        p(f"  {b:<6} {lang:<7} " + "  ".join(f"{c.get(k, 0):>19}" for k in
          ["PASS", "PASS*", "FAIL", "ERROR", "NOT_SUPPORTED", "STATA_NOT_SUPPORTED", "STATA_ERROR"]))
    p("  PASS* = everything compared passed; some option output is NOT_SUPPORTED in this language")
    p("")
    p(f"{'spec':<6} {'lang':<7} {'verdict':<20} {'pass':>5} {'fail':>5} {'miss':>5} {'extra':>5}  {'max rel':>9}  first problem")
    p("-" * 118)
    for s in summary:
        if s["lang"] == "stata" and s["verdict"] in ("PASS", "WARN"):
            continue
        p(f"{s['spec_id']:<6} {s['lang']:<7} {s['verdict']:<20} {s['n_pass']:>5} {s['n_fail']:>5} {s['n_missing']:>5} "
          f"{s['n_extra']:>5}  {s['max_rel_diff']:>9}  {s['first_problem']}")
    p("-" * 118)
    kinds = defaultdict(lambda: [0, set()])
    for r in rows:
        if r["status"] in BAD:
            el = re.sub(r"_\d+", "_k", r["element"].split("[")[0]) if r["element"] else ""
            det = r["detail"][:70] if r["check"] in ("run", "units", "validation") else \
                ("R and Python agree" if "agree" in r["detail"] else "")
            k = (r["lang"], r["status"], r["check"], el, det)
            kinds[k][0] += 1
            kinds[k][1].add(r["spec_id"])
    if kinds:
        p("")
        p("PROBLEMS grouped (lang | status | check | element | detail -> count : specs)")
        for (lang, st, chk, el, det), (n, cs) in sorted(kinds.items(), key=lambda x: -x[1][0]):
            p(f"  {lang:<7} {st:<8} {chk:<10} {el:<28} {det:<70} -> {n:>5} : {', '.join(sorted(cs))[:150]}")
    ns = [r for r in rows if r["status"] in ("NOT_SUPPORTED", "STATA_NOT_SUPPORTED")]
    if ns:
        p("")
        p("NOT SUPPORTED (not counted as failures)")
        agg = defaultdict(set)
        for r in ns:
            agg[(r["lang"], r["status"], r["detail"][:110])].add(r["spec_id"])
        for (lang, st, det), cs in sorted(agg.items()):
            p(f"  {lang:<7} {st:<20} {det:<110} : {', '.join(sorted(cs))[:150]}")
    nbad = sum(r["status"] in BAD for r in rows)
    p("")
    p(f"Details: {res / 'details.csv'}   Summary: {res / 'summary.csv'}")
    p("RESULT: " + ("ALL CHECKS PASSED" if nbad == 0 else f"{nbad} FAILED / MISSING / ERROR CHECKS"))
    text = "\n".join(out)
    print(text)
    (res / "report.txt").write_text(text + "\n", encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
