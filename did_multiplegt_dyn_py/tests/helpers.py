"""Shared helpers for the Python test suite — mirrors tests_R/R/helpers.R."""

from __future__ import annotations
import csv
import sys
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
PROJ_ROOT   = Path(__file__).parent.parent.parent   # /workspace
DATA_DIR    = PROJ_ROOT / "_data"
RESULTS_DIR = Path(__file__).parent / "results"
RESULTS_DIR.mkdir(exist_ok=True)


# ── CSV initializers ───────────────────────────────────────────────────────────
def init_switcher_csv(path: Path) -> None:
    path.write_text("dataset,spec,reset,effect_num,N_did,N_avg,diff,pass\n")


def init_wagepan_csv(path: Path) -> None:
    path.write_text("spec,effect_num,N_std,N_avg,diff,pass\n")


# ── Row writers ────────────────────────────────────────────────────────────────
def write_swrow(
    path: Path,
    dataset: str, spec: str, reset: int, effnum: int,
    n_did: float | None, n_avg: float | None,
) -> None:
    if n_did is None or n_avg is None:
        diff = "."
        verdict = "MISS"
    else:
        diff = n_did - n_avg
        verdict = "PASS" if diff == 0 else "FAIL"

    row = (f"{dataset},{spec},{reset},{effnum},"
           f"{'.' if n_did is None else n_did},"
           f"{'.' if n_avg is None else n_avg},"
           f"{'.' if diff == '.' else diff},"
           f"{verdict}\n")
    with open(path, "a") as fh:
        fh.write(row)

    tag = (f"  {verdict}  {dataset}/{spec}  reset={reset}  eff={effnum}"
           f"  did={n_did}  avg={n_avg}")
    if verdict == "PASS":
        print(tag)
    else:
        print(tag, file=sys.stderr)


def write_diagrow(
    path: Path, dataset: str, spec: str, reset: int, msg: str
) -> None:
    row = f"{dataset},{spec},{reset},-1,.,.,.,ERROR:{msg}\n"
    with open(path, "a") as fh:
        fh.write(row)
    print(f"  ERROR  {dataset}/{spec}  reset={reset}  {msg}", file=sys.stderr)


def write_wrow(
    path: Path, spec: str, effnum: int,
    n_std: float | None, n_avg: float | None,
) -> None:
    if n_std is None or n_avg is None:
        diff = "."
        verdict = "MISS"
    else:
        diff = n_std - n_avg
        verdict = "PASS" if diff == 0 else "FAIL"

    row = (f"{spec},{effnum},"
           f"{'.' if n_std is None else n_std},"
           f"{'.' if n_avg is None else n_avg},"
           f"{'.' if diff == '.' else diff},"
           f"{verdict}\n")
    with open(path, "a") as fh:
        fh.write(row)

    tag = f"  {verdict}  {spec}  eff={effnum}  std={n_std}  avg={n_avg}"
    if verdict == "PASS":
        print(tag)
    else:
        print(tag, file=sys.stderr)


# ── Result extractors ─────────────────────────────────────────────────────────
def extract_N_switchers(result, max_k: int = 600):
    if result is None:
        return {}
    out = {}
    for k in range(1, max_k + 1):
        v = getattr(result, f"N_switchers_effect_{k}", None)
        if v is None or (isinstance(v, float) and (v != v or v == 0)):
            break
        out[k] = v
    return out


def extract_N_switch_avg(result, max_k: int = 600):
    if result is None:
        return {}
    out = {}
    for k in range(1, max_k + 1):
        v = getattr(result, f"N_switch_avg_{k}", None)
        if v is None or (isinstance(v, float) and (v != v or v == 0)):
            break
        out[k] = v
    return out
