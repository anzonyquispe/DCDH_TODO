"""
test_by_path.py  --  Python side of the by_path cross-language test

Runs every case in ../cases.csv and ../validation_cases.csv and writes
  results/python_results.csv      one row per (case, path, statistic), full precision
  results/python_validation.csv   accepted / rejected for each invalid input
  results/python_meta.txt         which did_multiplegt_dyn was used

Usage (from anywhere):
    python tests_by_path/python/test_by_path.py

Environment variables (all optional):
    DCDH_PY_SRC      folder that contains the did_multiplegt_dyn package
                     (e.g. ../py_did_multiplegt_dyn/src); default: installed package
    DCDH_ONLY_CASES  space-separated case_ids to run (default: all)
"""

from __future__ import annotations

import contextlib
import csv
import io
import math
import os
import sys
import time
import warnings
from pathlib import Path

TB_DIR = Path(__file__).resolve().parent.parent
PROJ_ROOT = TB_DIR.parent
RESULTS_DIR = TB_DIR / "results"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)

src = os.environ.get("DCDH_PY_SRC", "")
if src:
    sys.path.insert(0, str(Path(src).resolve()))

import pandas as pd  # noqa: E402
import polars as pl  # noqa: E402
import did_multiplegt_dyn as dmd  # noqa: E402
from did_multiplegt_dyn import DidMultiplegtDyn  # noqa: E402

FIELDS = ["case_id", "path", "path_order", "n_groups", "row", "estimate", "se",
          "lb_ci", "ub_ci", "n", "switchers", "source", "status", "message"]
# Python labels the average total effect differently from Stata/R.
ROW_ALIASES = {"Average_Total_Effect": "Av_tot_eff"}


def pkg_version() -> str:
    # Source checkout: read pyproject.toml next to src/
    pyproject = Path(dmd.__file__).resolve().parent.parent.parent / "pyproject.toml"
    if src and pyproject.exists():
        import re
        m = re.search(r'^version\s*=\s*"([^"]+)"', pyproject.read_text(encoding="utf-8"), re.M)
        if m:
            return m.group(1) + " (source)"
    try:
        from importlib.metadata import version
        return version("py-did-multiplegt-dyn")
    except Exception:
        return getattr(dmd, "__version__", "unknown")


def num(x) -> str:
    try:
        x = float(x)
    except (TypeError, ValueError):
        return ""
    return "" if math.isnan(x) else repr(x)


def load_data(rel_path: str) -> pl.DataFrame:
    df = pd.read_stata(PROJ_ROOT / rel_path, convert_categoricals=False)
    return pl.from_pandas(df)


def build_args(cs: dict, df: pl.DataFrame) -> dict:
    a = dict(df=df, outcome=cs["outcome"], group=cs["group"], time=cs["time"],
             treatment=cs["treatment"], effects=int(cs["effects"]),
             placebo=int(cs["placebo"]))
    a["by_path"] = "all" if cs["by_path"].lower() == "all" else int(cs["by_path"])
    if cs["controls"]:
        a["controls"] = cs["controls"].split()
    if cs["weight"]:
        a["weight"] = cs["weight"]
    if cs["cluster"]:
        a["cluster"] = cs["cluster"]
    if cs["normalized"] == "1":
        a["normalized"] = True
    if cs["switchers"]:
        a["switchers"] = cs["switchers"]
    if cs["only_never_switchers"] == "1":
        a["only_never_switchers"] = True
    return a


def fit_quietly(args: dict):
    """Fit the model, swallowing the package's prints and warnings."""
    buf = io.StringIO()
    with warnings.catch_warnings(), contextlib.redirect_stdout(buf):
        warnings.simplefilter("ignore")
        model = DidMultiplegtDyn(**args)
        result = model.fit()
    return result, buf.getvalue()


def path_label(seq) -> str:
    return ",".join("NA" if v is None else str(v) for v in seq)


def row(case_id, **kw) -> dict:
    r = {f: "" for f in FIELDS}
    r.update(case_id=case_id, source="precise", status="ok")
    r.update({k: ("" if v is None else v) for k, v in kw.items()})
    return r


def table_rows(tab, case_id, path, order, n_groups):
    if tab is None or len(tab) == 0:
        return []
    out = []
    for name, rec in tab.iterrows():
        vals = list(rec.values)
        out.append(row(case_id, path=path, path_order=order, n_groups=n_groups,
                       row=ROW_ALIASES.get(str(name).strip(), str(name).strip()),
                       estimate=num(vals[0]), se=num(vals[1]), lb_ci=num(vals[2]),
                       ub_ci=num(vals[3]), n=num(vals[4]), switchers=num(vals[5])))
    return out


def run_cases() -> None:
    with open(TB_DIR / "cases.csv", newline="", encoding="utf-8") as fh:
        cases = [{k: (v or "").strip() for k, v in r.items()} for r in csv.DictReader(fh)]
    only = os.environ.get("DCDH_ONLY_CASES", "").split()
    if only:
        cases = [c for c in cases if c["case_id"] in only]

    rows = []
    for cs in cases:
        cid = cs["case_id"]
        print(f"\n=== CASE {cid} (by_path = {cs['by_path']}) ===", flush=True)
        df = load_data(cs["dataset"])
        t0 = time.time()
        try:
            result, _ = fit_quietly(build_args(cs, df))
            paths = result.result["did_multiplegt_dyn"].get("all_path_results") or []
        except Exception as e:  # noqa: BLE001
            msg = f"{type(e).__name__}: {e}".replace("\n", " ")
            print("  ERROR:", msg)
            rows.append(row(cid, status="case_error", message=msg[:300]))
            continue

        for item in paths:
            label = path_label(item.get("treatment_sequence", []))
            order = item.get("path_id", "")
            ng = item.get("n_groups", "")
            if item.get("error"):
                rows.append(row(cid, path=label, path_order=order, n_groups=ng,
                                status="path_error", message=str(item["error"])[:300]))
                continue
            dyn = item["result"]["did_multiplegt_dyn"]
            for key in ("Effects", "ATE", "Placebos"):
                rows += table_rows(dyn.get(key), cid, label, order, ng)
            for key, name in (("p_jointeffects", "p_joint_effects"),
                              ("p_jointplacebo", "p_joint_placebos")):
                if dyn.get(key) is not None:
                    rows.append(row(cid, path=label, path_order=order, n_groups=ng,
                                    row=name, estimate=num(dyn[key])))
        print(f"  {len(paths)} paths in {time.time() - t0:.1f}s", flush=True)

    with open(RESULTS_DIR / "python_results.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)


def run_validation() -> None:
    with open(TB_DIR / "validation_cases.csv", newline="", encoding="utf-8") as fh:
        vcases = [{k: (v or "").strip() for k, v in r.items()} for r in csv.DictReader(fh)]
    wagepan = load_data("_data/wagepan.dta")
    out = []
    for v in vcases:
        raw = v["by_path"]
        if v["by_path_type"] == "num":
            bp = float(raw)
            bp = int(bp) if bp.is_integer() else bp
        else:
            bp = raw
        args = dict(df=wagepan, outcome="lwage", group="nr", time="year",
                    treatment="union", effects=2, placebo=0, by_path=bp)
        if v["with_by"] == "1":
            args["by"] = "black"
        try:
            result, _ = fit_quietly(args)
            paths = result.result["did_multiplegt_dyn"].get("all_path_results") or []
            ok = any(not p.get("error") for p in paths)
            outcome, msg = ("accepted" if ok else "rejected"), ""
        except Exception as e:  # noqa: BLE001
            outcome, msg = "rejected", f"{type(e).__name__}: {e}".replace("\n", " ")[:200]
        print(f"VALIDATION {v['vcase_id']} by_path={bp!r} -> {outcome}")
        out.append({"vcase_id": v["vcase_id"], "outcome": outcome, "message": msg})

    with open(RESULTS_DIR / "python_validation.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["vcase_id", "outcome", "message"])
        w.writeheader()
        w.writerows(out)


def main() -> None:
    meta = [
        "language=python",
        f"python_version={sys.version.split()[0]}",
        f"package_file={Path(dmd.__file__).resolve().parent}",
        f"package_version={pkg_version()}",
        f"polars_version={pl.__version__}",
        f"pandas_version={pd.__version__}",
        f"run_at={time.strftime('%Y-%m-%d %H:%M:%S')}",
    ]
    (RESULTS_DIR / "python_meta.txt").write_text("\n".join(meta) + "\n", encoding="utf-8")
    print(f"Testing did_multiplegt_dyn from {Path(dmd.__file__).resolve().parent}")
    run_cases()
    run_validation()
    print(f"\nPython by_path tests finished. Results in {RESULTS_DIR}")


if __name__ == "__main__":
    main()
