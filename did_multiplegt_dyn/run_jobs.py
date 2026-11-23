"""run_jobs.py -- run the suite with ONE JOB PER SPEC, then merge and compare.

    python run_jobs.py --stata-ado installed --r-pkg installed --py-pkg installed
    python run_jobs.py ... --stata-workers 6 --skip r,python --only "A02 D10"

* Stata : every spec is its own Stata process; --stata-workers of them run at
          the same time (the biggest specs, e.g. D10, are started first).
* R     : every spec is its own Rscript process, one after the other.
* Python: every spec is its own python process, one after the other.
* The 14 input checks (specs/validation.csv) are one extra job per language.

Each job writes to results/jobs/<lang>/<spec>/<lang>/ (log: console.log next
to it). The jobs are then merged into results/<lang>/{outputs,status,
validation}.csv, meta.txt (and logs/ for Stata) -- the layout compare.py reads --
and compare/compare.py is run. A language's meta.txt gets finished_at only when
every one of its jobs finished. As in run_tests.sh, the package versions under
test must be given; nothing is defaulted.
"""
import argparse
import csv
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

SUITE = Path(__file__).resolve().parent
BIG_FIRST = ["D10"]  # memory-heavy specs, started first so they never queue at the end


def find_stata():
    if os.environ.get("STATA_BIN"):
        return os.environ["STATA_BIN"]
    for p in sorted(Path("C:/Program Files").glob("Stata*/Stata*-64.exe"), reverse=True):
        return str(p)
    for c in ("stata-mp", "stata-se", "stata"):
        if shutil.which(c):
            return shutil.which(c)
    sys.exit("Stata not found: set STATA_BIN")


def job_cmd(lang, job_res, exe):
    if lang == "stata":
        if os.name == "nt":
            return [exe, "/e", "do", str(SUITE / "Stata" / "run_specs.do"), str(SUITE), str(job_res)]
        return [exe, "-b", "do", str(SUITE / "Stata" / "run_specs.do"), str(SUITE), str(job_res)]
    if lang == "r":
        return [exe, str(SUITE / "R" / "run_specs.R"), str(SUITE), str(job_res)]
    return [exe, str(SUITE / "Python" / "run_specs.py"), str(SUITE), str(job_res)]


def run_job(lang, job, exe, env_base, jobs_root, timeout):
    """job = spec id, or '_validation' for the input checks."""
    job_res = jobs_root / lang / job
    if job_res.exists():
        shutil.rmtree(job_res)
    job_res.mkdir(parents=True)
    env = dict(env_base)
    if job == "_validation":
        env["DCDH_ONLY"] = "__no_spec__"
        env["DCDH_SKIP_VALIDATION"] = "0"
    else:
        env["DCDH_ONLY"] = job
        env["DCDH_SKIP_VALIDATION"] = "1"
    env.pop("DCDH_BLOCKS", None)
    t0 = time.time()
    with open(job_res / "console.log", "w", encoding="utf-8", errors="replace") as fh:
        try:
            # cwd = the job folder: Stata /e writes run_specs.log into the cwd
            rc = subprocess.run(job_cmd(lang, job_res, exe), cwd=job_res, env=env,
                                stdout=fh, stderr=subprocess.STDOUT, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            rc = "timeout"
    meta = job_res / lang / "meta.txt"
    finished = meta.exists() and "finished_at=" in meta.read_text(encoding="utf-8", errors="replace")
    return job, finished, rc, time.time() - t0


def merge(lang, jobs, jobs_root, res, started):
    out = res / lang
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    all_ok = True
    for name in ("outputs.csv", "status.csv"):
        header_done = False
        with open(out / name, "w", encoding="utf-8", newline="") as fo:
            for j in jobs:
                f = jobs_root / lang / j / lang / name
                if not f.exists():
                    continue
                lines = f.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
                if not lines:
                    continue
                if not header_done:
                    fo.write(lines[0] if lines[0].endswith("\n") else lines[0] + "\n")
                    header_done = True
                for ln in lines[1:]:
                    fo.write(ln if ln.endswith("\n") else ln + "\n")
    v = jobs_root / lang / "_validation" / lang / "validation.csv"
    if v.exists():
        shutil.copy(v, out / "validation.csv")
    if lang == "stata":
        (out / "logs").mkdir()
        for j in jobs:
            for lg in (jobs_root / lang / j / lang / "logs").glob("*.log"):
                shutil.copy(lg, out / "logs" / lg.name)
    meta_lines = []
    for j in jobs:
        m = jobs_root / lang / j / lang / "meta.txt"
        if m.exists() and not meta_lines:
            meta_lines = [ln for ln in m.read_text(encoding="utf-8", errors="replace").splitlines()
                          if not ln.startswith(("started_at=", "finished_at="))]
        if not (m.exists() and "finished_at=" in m.read_text(encoding="utf-8", errors="replace")):
            all_ok = False
    meta_lines.append(f"started_at={started}")
    meta_lines.append("run_mode=one job per spec (run_jobs.py)")
    if all_ok:
        meta_lines.append(f"finished_at={time.strftime('%Y-%m-%d %H:%M:%S')}")
    (out / "meta.txt").write_text("\n".join(meta_lines) + "\n", encoding="utf-8")
    return all_ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stata-ado", default=os.environ.get("DCDH_STATA_ADO", ""))
    ap.add_argument("--r-pkg", default=os.environ.get("DCDH_R_PKG", ""))
    ap.add_argument("--py-pkg", default=os.environ.get("DCDH_PY_PKG", ""))
    ap.add_argument("--stata-workers", type=int, default=6)
    ap.add_argument("--only", default="")
    ap.add_argument("--skip", default="", help="comma list of stata,r,python,compare")
    ap.add_argument("--results", default=str(SUITE / "results"))
    ap.add_argument("--timeout", type=float, default=4 * 3600, help="seconds per job")
    ap.add_argument("--merge-only", action="store_true",
                    help="do not run jobs: merge the existing results/jobs/<lang>/ folders (then compare)")
    a = ap.parse_args()
    skip = set(filter(None, a.skip.split(",")))
    langs = [l for l in ("stata", "r", "python") if l not in skip]
    need = {"stata": a.stata_ado, "r": a.r_pkg, "python": a.py_pkg}
    # Jobs run inside their own folders, so a relative package path (e.g.
    # new_versions/R_2.5.0) must be made absolute here, against the folder
    # the command was started from.
    def absolute(p):
        return p if p in ("", "installed") else str(Path(p).expanduser().resolve())
    a.stata_ado, a.r_pkg, a.py_pkg = absolute(a.stata_ado), absolute(a.r_pkg), absolute(a.py_pkg)
    need = {"stata": a.stata_ado, "r": a.r_pkg, "python": a.py_pkg}
    for l in langs:
        if not need[l] and not a.merge_only:
            sys.exit(f"ERROR: say which {l} package to test (--stata-ado / --r-pkg / --py-pkg); nothing is assumed.")

    with open(SUITE / "specs" / "specs.csv", newline="", encoding="utf-8") as fh:
        specs = [r["spec_id"].strip() for r in csv.DictReader(fh)]
    if a.only:
        specs = [s for s in specs if s in a.only.split()]
    jobs = sorted(specs, key=lambda s: (s not in BIG_FIRST, specs.index(s))) + ["_validation"]

    res = Path(a.results).resolve()
    jobs_root = res / "jobs"
    env = dict(os.environ, DCDH_STATA_ADO=a.stata_ado, DCDH_R_PKG=a.r_pkg, DCDH_PY_PKG=a.py_pkg,
               MSYS_NO_PATHCONV="1")
    exes = {"stata": find_stata() if "stata" in langs else "",
            "r": os.environ.get("RSCRIPT", "Rscript"),
            "python": os.environ.get("PYTHON", sys.executable)}

    status = 0
    for lang in langs:
        started = time.strftime("%Y-%m-%d %H:%M:%S")
        if a.merge_only:
            ok = merge(lang, jobs, jobs_root, res, started)
            print(f"  {lang}: merged into {res / lang}" + ("" if ok else " (some jobs did not finish)"))
            status = status or (0 if ok else 1)
            continue
        workers = a.stata_workers if lang == "stata" else 1
        print(f"\n===== {lang}: {len(jobs)} jobs, {workers} at a time ({exes[lang]}) =====", flush=True)
        t0 = time.time()
        bad = []
        with ThreadPoolExecutor(max_workers=workers) as ex:
            futs = [ex.submit(run_job, lang, j, exes[lang], env, jobs_root, a.timeout) for j in jobs]
            for n, f in enumerate(as_completed(futs), 1):
                j, ok, rc, secs = f.result()
                if not ok:
                    bad.append(j)
                print(f"  [{lang} {n:3d}/{len(jobs)}] {j:12s} {'finished' if ok else 'DID NOT FINISH rc=' + str(rc)}"
                      f"  {secs:7.1f}s", flush=True)
        all_ok = merge(lang, jobs, jobs_root, res, started)
        print(f"  {lang}: {time.time() - t0:.0f}s total; merged into {res / lang}"
              + ("" if all_ok else f"; NOT FINISHED: {' '.join(bad)}"), flush=True)
        if not all_ok:
            status = 1

    if "compare" not in skip:
        print("", flush=True)
        rc = subprocess.run([sys.executable, str(SUITE / "compare" / "compare.py"), str(res)]).returncode
        status = status or rc
    return status


if __name__ == "__main__":
    sys.exit(main())
