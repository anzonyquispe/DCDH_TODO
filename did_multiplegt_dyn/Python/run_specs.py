"""
run_specs.py  --  Python side of the did_multiplegt_dyn suite

Runs every spec in ../specs/specs.csv and every input check in
../specs/validation.csv and writes, in <results>/python/:
  outputs.csv     every result element under the name Stata uses for it
  status.csv      one row per spec (and per by / by_path unit)
  validation.csv  accepted / rejected for each input check
  meta.txt        which did_multiplegt_dyn was tested

Usage (normally called by ../run_tests.sh):
    python Python/run_specs.py <suite folder> <results folder>

Environment variables:
    DCDH_PY_PKG   REQUIRED. Which did_multiplegt_dyn to test:
                    installed      the version installed in this Python
                    <folder>       a folder that contains the did_multiplegt_dyn
                                   package (e.g. .../py_did_multiplegt_dyn/src)
    DCDH_ONLY     space-separated spec ids (default: all)
    DCDH_BLOCKS   space-separated blocks (default: all)
"""

from __future__ import annotations

import contextlib
import csv
import inspect
import io
import math
import os
import re
import sys
import time
import warnings
from pathlib import Path

SUITE = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent).resolve()
RES = Path(sys.argv[2]) if len(sys.argv) > 2 else SUITE / "results"
OUT = RES / "python"
OUT.mkdir(parents=True, exist_ok=True)
DATA = SUITE / "data"

pkg = os.environ.get("DCDH_PY_PKG", "")
if not pkg:
    sys.exit("DCDH_PY_PKG is not set. Say which did_multiplegt_dyn to test (installed, or the folder that contains the package).")
if pkg != "installed":
    p = Path(pkg).resolve()
    if not (p / "did_multiplegt_dyn").is_dir():
        sys.exit(f"DCDH_PY_PKG={pkg}: no did_multiplegt_dyn package folder inside it")
    sys.path.insert(0, str(p))

import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
import polars as pl  # noqa: E402
import did_multiplegt_dyn as dmd  # noqa: E402
from did_multiplegt_dyn import DidMultiplegtDyn  # noqa: E402

PARAMS = set(inspect.signature(DidMultiplegtDyn.__init__).parameters)


def pkg_version() -> str:
    pyproject = Path(dmd.__file__).resolve().parent.parent.parent / "pyproject.toml"
    if pkg != "installed" and pyproject.exists():
        m = re.search(r'^version\s*=\s*"([^"]+)"', pyproject.read_text(encoding="utf-8"), re.M)
        if m:
            return m.group(1) + " (source)"
    try:
        from importlib.metadata import version
        return version("py-did-multiplegt-dyn")
    except Exception:
        return getattr(dmd, "__version__", "unknown")


def rd(name):
    with open(SUITE / "specs" / name, newline="", encoding="utf-8") as fh:
        return [{k: (v or "").strip() for k, v in r.items()} for r in csv.DictReader(fh)]


SPECS, OPTMAP, VAL = rd("specs.csv"), {r["stata_option"]: r for r in rd("option_map.csv")}, rd("validation.csv")
NOTSUP = [r for r in rd("not_supported.csv") if r["lang"] == "python"]

# ----------------------------------------------------------------------------
# Stata option string -> Python arguments
# ----------------------------------------------------------------------------
TOK = re.compile(r"[A-Za-z_][A-Za-z_0-9]*(\((?:[^()]|\([^()]*\))*\))?")


def parse_stata_options(s):
    out = []
    for m in TOK.finditer(s):
        t = m.group(0)
        name = t.split("(", 1)[0]
        arg = t[len(name) + 1:-1] if "(" in t else None
        out.append((name, arg))
    return out


def as_num(a):
    x = float(a)
    return int(x) if x.is_integer() else x


def convert(kind, arg):
    if kind == "int":
        return as_num(arg)
    if kind == "flag":
        return True
    if kind == "varlist":
        return arg.split()
    if kind in ("var", "string"):
        return arg.strip()
    if kind == "effects_equal":
        return True if arg.strip().lower() == "all" else arg.strip()
    if kind == "by_path":
        a = arg.strip()
        return as_num(a) if re.fullmatch(r"-?[0-9.]+", a) else a
    parts = [p.strip() for p in arg.split(",")]
    if kind == "design":
        return [float(parts[0]) if parts and parts[0] else 1, parts[1] if len(parts) > 1 else "console"]
    if kind == "predict_het":
        w = -1 if len(parts) < 2 or parts[1] == "all" else [int(v) for v in parts[1].split()]
        return [parts[0].split(), w]
    if kind == "date_first_switch":
        return [parts[0] if parts and parts[0] else "", parts[1] if len(parts) > 1 else "console"]
    if kind == "bootstrap":
        return [as_num(p) for p in parts]
    raise ValueError(f"unknown option kind {kind}")


def build_args(opts):
    a, ns, used = {}, [], []
    for name, arg in parse_stata_options(opts):
        used.append(name)
        row = OPTMAP.get(name)
        if row is None:
            ns.append(f"unknown option {name}")
            continue
        hit = [r for r in NOTSUP if r["option"] == name and r["scope"] == "spec"]
        if hit:
            ns.append(hit[0]["reason"])
            continue
        if not row["py_arg"] or row["py_arg"] not in PARAMS:
            ns.append(f"option {name} has no argument in this did_multiplegt_dyn")
            continue
        a[row["py_arg"]] = convert(row["kind"], arg)
    # Python's default is placebo=1 (Stata and R: 0): always pass it
    a.setdefault("placebo", 0)
    return a, ("; ".join(ns) or None), used


# ----------------------------------------------------------------------------
# Data preparation (same as Stata's _prep)
# ----------------------------------------------------------------------------
def load_data(ds):
    return pd.read_stata(DATA / f"{ds}.dta", convert_categoricals=False)


def prep(df, p):
    if not p:
        return df
    # Stata treats a missing value as larger than any number
    if p == "deryugina_year_controls":
        for v in ["coastal", "land_area1970", "log_pop1969", "frac_young1969", "frac_old1969",
                  "frac_black1969", "log_wage_pc1969", "emp_rate1969"]:
            df[f"{v}_year"] = df[v] * df["year"]
        return df
    if p in ("gentzkow_t11", "gentzkow_ch08"):
        fc = df["first_change"]
        cmp = df["year"] <= fc if p == "gentzkow_t11" else df["year"] < fc
        keep = (df["year"].notna() & (fc.isna() | cmp)) | (df["same_treat_after_first_change"] == 1)
        return df[keep].copy()
    if p == "hollingsworth_t13":
        return df[df["rm"] == 0].copy()
    if p == "hollingsworth_t14":
        fg = df["year"].where(df["mm"] == 1).groupby(df["state"]).transform("min")
        df["fg1"] = fg
        return df[df["mm"] == 1].copy()
    raise ValueError(f"unknown prep {p}")


# ----------------------------------------------------------------------------
# Result extraction under Stata's names
# ----------------------------------------------------------------------------
ROWS, STATUS = [], []
MAT_COLS = ["Estimate", "SE", "LB CI", "UB CI", "N", "Switchers"]


def num(x) -> str:
    try:
        x = float(x)
    except (TypeError, ValueError):
        return ""
    return "" if math.isnan(x) else repr(x)


def emit(spec, unit, kind, name, value, row="", col="", rowname="", colname=""):
    ROWS.append(dict(spec_id=spec, unit=unit, kind=kind, name=name, row=str(row), col=str(col),
                     rowname=str(rowname), colname=str(colname), value=value, precision="full"))


def emit_table(spec, unit, tab, kind, names):
    if tab is None or len(tab) == 0:
        return
    for rn, rec in tab.iterrows():
        vals = list(rec.values) + [None] * 8
        est, se, n, sw, nw, sww = vals[0], vals[1], vals[4], vals[5], vals[6], vals[7]
        if kind == "ate":
            rn, k = "Av_tot_eff", 0
            pre = [("Av_tot_effect", est), ("se_avg_total_effect", se), ("N_avg_total_effect", n),
                   ("N_switchers_effect_average", sw), ("N_avg_total_effect_w", nw),
                   ("N_switchers_effect_average_w", sww)]
            ttt = 0
        else:
            rn = str(rn).strip()
            k = int(re.sub(r"^\D+_", "", rn))
            w = "effect" if kind == "effect" else "placebo"
            lab = "Effect" if kind == "effect" else "Placebo"
            pre = [(f"{lab}_{k}", est), (f"se_{w}_{k}", se), (f"N_{w}_{k}", n),
                   (f"N_switchers_{w}_{k}", sw), (f"N_{w}_{k}_w", nw), (f"N_switchers_{w}_{k}_w", sww)]
            ttt = k if kind == "effect" else -k
        names.append(rn)
        for nm, v in pre:
            emit(spec, unit, "e_scalar", nm, num(v))
        for j in range(6):
            emit(spec, unit, "matrix", "mat_res_XX", num(vals[j]), col=j + 1, rowname=rn, colname=MAT_COLS[j])
        emit(spec, unit, "matrix", "mat_res_XX", num(ttt), col=7, rowname=rn, colname="time_to_treat")


def emit_unit(spec, unit, res) -> bool:
    d = res.get("did_multiplegt_dyn") if isinstance(res, dict) else None
    if not isinstance(d, dict) or d.get("Effects") is None:
        return False
    eff, pl_, ate = [], [], []
    emit_table(spec, unit, d.get("Effects"), "effect", eff)
    emit_table(spec, unit, d.get("ATE"), "ate", ate)
    emit_table(spec, unit, d.get("Placebos"), "placebo", pl_)
    for p in ("p_jointeffects", "p_jointplacebo", "p_equality_effects"):
        if d.get(p) is not None:
            emit(spec, unit, "e_scalar", p, num(d[p]))
    emit(spec, unit, "e_macro", "cmd", "did_multiplegt_dyn")
    if eff:
        emit(spec, unit, "e_macro", "effects", " ".join(eff))
    if pl_:
        emit(spec, unit, "e_macro", "placebo", " ".join(pl_))
    coef = res.get("coef") or {}
    # e(b) is not compared (see specs/stata_only.csv)
    V = coef.get("vcov")
    if V is not None:
        V = pd.DataFrame(V)
        for i, rn in enumerate(V.index):
            for j, cn in enumerate(V.columns):
                emit(spec, unit, "e_matrix", "V", num(V.iloc[i, j]), row=i + 1, col=j + 1,
                     rowname=str(rn).strip(), colname=str(cn).strip())
    # predict_het(): e(effect_het_#_XX) / e(effect_het_pl_#_XX) in Stata;
    # Python: res["did_multiplegt_dyn"]["predict_het"] (same columns as R)
    ph = d.get("predict_het")
    if isinstance(ph, pd.DataFrame) and len(ph):
        for _, r in ph.iterrows():
            e = int(r["effect"])
            nm = f"effect_het_pl_{-e}_XX" if e < 0 else f"effect_het_{e}_XX"
            vals = [r.get("Estimate"), r.get("SE"), r.get("t"), r.get("LB"), r.get("UB"), r.get("N")]
            for j, v in enumerate(vals):
                emit(spec, unit, "e_matrix", nm, num(v), col=j + 1, rowname=str(r["covariate"]))
    # avg_time_periods: e(avg_cumul), e(N_switch_avg_#) in Stata -- same names in Python
    if d.get("avg_cumul") is not None:
        emit(spec, unit, "e_scalar", "avg_cumul", num(d["avg_cumul"]))
    for k in sorted((k for k in d if re.fullmatch(r"N_switch_avg_\d+", k)), key=lambda s: int(s.rsplit("_", 1)[1])):
        emit(spec, unit, "e_scalar", k, num(d[k]))
    des = res.get("design")
    if isinstance(des, pd.DataFrame):
        for i, rn in enumerate(des.index):
            for j, cn in enumerate(des.columns):
                emit(spec, unit, "matrix", "desmat", num(des.iloc[i, j]), row=i + 1, col=j + 1,
                     rowname=str(rn), colname=str(cn))
    return True


def status(spec, unit, st, secs="", msg=""):
    STATUS.append(dict(spec_id=spec, unit=unit, status=st, rc="", seconds=str(secs),
                       message=str(msg).replace("\n", " ")[:400]))


def fit(df_pd, s, args):
    buf = io.StringIO()
    with warnings.catch_warnings(), contextlib.redirect_stdout(buf):
        warnings.simplefilter("ignore")
        model = DidMultiplegtDyn(df=pl.from_pandas(df_pd), outcome=s["outcome"], group=s["group"],
                                 time=s["time"], treatment=s["treatment"], **args)
        out = model.fit()
    return out.result if hasattr(out, "result") else out


def path_label(seq) -> str:
    return ",".join("NA" if (v is None or (isinstance(v, float) and math.isnan(v))) else
                    (str(int(v)) if float(v).is_integer() else repr(float(v))) for v in seq)


OUT_FIELDS = ["spec_id", "unit", "kind", "name", "row", "col", "rowname", "colname", "value", "precision"]
ST_FIELDS = ["spec_id", "unit", "status", "rc", "seconds", "message"]


def flush(first=False):
    """Append this spec's rows so that a crash later keeps what was done."""
    for name, fields, rows in (("outputs.csv", OUT_FIELDS, ROWS), ("status.csv", ST_FIELDS, STATUS)):
        with open(OUT / name, "w" if first else "a", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=fields)
            if first:
                w.writeheader()
            w.writerows(rows)
        rows.clear()


def run_specs():
    flush(first=True)
    only = os.environ.get("DCDH_ONLY", "").split()
    blocks = os.environ.get("DCDH_BLOCKS", "").split()
    for s in SPECS:
        sid = s["spec_id"]
        if (only and sid not in only) or (blocks and s["block"] not in blocks):
            continue
        flush()
        print(f"\n=== {sid}: {s['options']}", flush=True)
        args, ns, used = build_args(s["options"])
        if ns:
            status(sid, "", "not_supported", msg=ns)
            continue
        try:
            df = prep(load_data(s["dataset"]), s["prep"])
        except Exception as e:  # noqa: BLE001
            status(sid, "", "error", msg=f"prep: {e}")
            continue
        t0 = time.time()
        try:
            res = fit(df, s, args)
        except Exception as e:  # noqa: BLE001
            msg = f"{type(e).__name__}: {e}"
            # crashes in an option whose output is flagged as not supported
            flagged = [r for r in NOTSUP if r["option"] in used and r["scope"] == "output"]
            st = "not_supported" if flagged else "error"
            if flagged:
                msg = f"{flagged[0]['reason']} -- crashed: {msg}"
            print("  ", st.upper(), msg)
            status(sid, "", st, round(time.time() - t0, 3), msg)
            continue
        secs = round(time.time() - t0, 3)
        d = res.get("did_multiplegt_dyn", {}) if isinstance(res, dict) else {}
        if "by_path" in used and d.get("all_path_results") is not None:
            for item in d["all_path_results"]:
                unit = "path=" + path_label(item.get("treatment_sequence", []))
                if item.get("error"):
                    status(sid, unit, "error", secs, item["error"])
                    continue
                ok = emit_unit(sid, unit, item.get("result") or {})
                status(sid, unit, "ok" if ok else "no_results", secs)
        elif "by" in used and d.get("all_by_results") is not None:
            for item in d["all_by_results"]:
                v = item.get("by_value")
                lab = str(int(v)) if isinstance(v, (int, float)) and float(v).is_integer() else str(v)
                unit = "level=" + lab
                ok = emit_unit(sid, unit, item.get("result") or {})
                status(sid, unit, "ok" if ok else "no_results", secs)
        else:
            ok = emit_unit(sid, "", res)
            status(sid, "", "ok" if ok else "no_results", secs)
        print(f"  done in {secs:.1f}s", flush=True)

    flush()


def run_validation():
    wagepan = load_data("wagepan")
    base = dict(outcome="lwage", group="nr", time="year", treatment="union")
    out = []
    for v in VAL:
        args, ns, _ = build_args(v["test_option"])
        if ns:
            out.append(dict(vid=v["vid"], outcome="not_supported", message=ns))
            continue
        if v["value_type"] == "str" and "by_path" in args:
            args["by_path"] = re.search(r"by_path\(([^)]*)\)", v["test_option"]).group(1)
        args.update(effects=2, placebo=0)
        try:
            res = fit(wagepan, base, args)
            d = res.get("did_multiplegt_dyn", {})
            paths = d.get("all_path_results")
            ok = any(not p.get("error") for p in paths) if paths is not None else d.get("Effects") is not None
            outcome, msg = ("accepted" if ok else "rejected"), ""
        except Exception as e:  # noqa: BLE001
            outcome, msg = "rejected", f"{type(e).__name__}: {e}".replace("\n", " ")[:200]
        print(f"VALIDATION {v['vid']} {v['test_option']} -> {outcome}")
        out.append(dict(vid=v["vid"], outcome=outcome, message=msg))
    with open(OUT / "validation.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["vid", "outcome", "message"])
        w.writeheader()
        w.writerows(out)


def main():
    meta = ["language=python", f"language_version={sys.version.split()[0]}",
            f"package_source={Path(dmd.__file__).resolve().parent}", f"package_version={pkg_version()}",
            f"polars_version={pl.__version__}", f"pandas_version={pd.__version__}",
            f"started_at={time.strftime('%Y-%m-%d %H:%M:%S')}"]
    (OUT / "meta.txt").write_text("\n".join(meta) + "\n", encoding="utf-8")
    print(f"Testing did_multiplegt_dyn {pkg_version()} from {Path(dmd.__file__).resolve().parent}")
    run_specs()
    if os.environ.get("DCDH_SKIP_VALIDATION") != "1":
        run_validation()
    with open(OUT / "meta.txt", "a", encoding="utf-8") as fh:
        fh.write(f"finished_at={time.strftime('%Y-%m-%d %H:%M:%S')}\n")
    print(f"\nPython specs finished. Results in {OUT}")


if __name__ == "__main__":
    main()
