"""Build SPECS.html (the list of every specification, in Stata syntax) from specs/*.csv.

    python specs/make_specs_page.py

Run it again after adding or changing a spec, and commit SPECS.html with the change.
The Stata commands shown are the ones Stata/run_specs.do runs.
"""
import csv
import html
from pathlib import Path

SUITE = Path(__file__).resolve().parent.parent

BLOCKS = {
    "A": "wagepan (union membership), <code>effects(5) placebo(2)</code> with each option of <code>tests_stata.do</code>",
    "B": "wagepan: additional outputs (<code>design</code>, <code>by</code>, <code>by_path</code>, <code>predict_het</code>, <code>date_first_switch</code>)",
    "C": "Block A's options on deryugina (absorbing binary treatment)",
    "D": "Examples from the DID textbook chapters and other datasets",
    "E": "favara_imbs: weights, <code>predict_het</code>, <code>by</code>, <code>normalized_weights</code>, missing treatments",
    "F": "<code>by_path</code>: earlier by_path tests, help-file examples and <code>by_path</code> × each option",
    "G": "<code>reset</code> and <code>avg_time_periods</code> (need a Stata ado that has them)",
}

# data preparation run before the command (Stata/run_specs.do, program _prep)
PREP = {
    "deryugina_year_controls": "foreach v in coastal land_area1970 log_pop1969 frac_young1969 frac_old1969 frac_black1969 log_wage_pc1969 emp_rate1969 {\n    gen double `v'_year = `v' * year\n}",
    "gentzkow_t11": "keep if year <= first_change | same_treat_after_first_change == 1",
    "gentzkow_ch08": "keep if year < first_change | same_treat_after_first_change == 1",
    "hollingsworth_t13": "keep if rm == 0",
    "hollingsworth_t14": "egen double fg1 = min(cond(mm == 1, year, .)), by(state)\nkeep if mm == 1",
}


# plain description of each option, used when a spec has no note
DESC = {
    "continuous": "continuous period-one treatment (polynomial of order {a})",
    "ci_level": "{a}% confidence intervals",
    "reset": "reset({a}): new subgroup after {a} unchanged periods",
    "normalized": "normalized effects",
    "normalized_weights": "weights of the normalized effects",
    "trends_lin": "group-specific linear trends",
    "same_switchers": "same switchers for all effects",
    "same_switchers_pl": "same switchers for effects and placebos",
    "only_never_switchers": "only never-switchers as controls",
    "less_conservative_se": "less conservative standard errors",
    "dont_drop_larger_lower": "keeps cells with treatment above and below baseline",
    "drop_if_d_miss_before_first_switch": "drops groups with missing treatment before the first switch",
    "avg_time_periods": "average number of periods effects accumulate",
    "more_granular_demeaning": "more granular demeaning",
    "predict_het_hc2bm": "HC2/Bell-McCaffrey SEs for predict_het",
    "controls": "controls: {a}",
    "trends_nonparam": "non-parametric trends by {a}",
    "weight": "weighted by {a}",
    "cluster": "SEs clustered by {a}",
    "by": "separately by {a}",
    "switchers": "only switchers {a}",
    "effects_equal": "test that effects are equal ({a})",
    "by_path": "separately by treatment path ({a})",
    "design": "design table ({a})",
    "predict_het": "heterogeneity regressions ({a})",
    "date_first_switch": "dates of first switch ({a})",
    "bootstrap": "bootstrap SEs ({a})",
}


def describe(opts):
    import re
    parts = []
    for name, _, arg in re.findall(r"([A-Za-z_]+)(\(((?:[^()]|\([^()]*\))*)\))?", opts):
        if name in ("effects", "placebo"):
            continue
        d = DESC.get(name, name)
        parts.append(d.format(a=arg.strip(" ,") if arg else "").replace(" ()", ""))
    return "; ".join(parts) if parts else "baseline: no other options"


def read(name):
    with open(SUITE / "specs" / name, newline="", encoding="utf-8") as fh:
        return [{k: (v or "").strip() for k, v in r.items()} for r in csv.DictReader(fh)]


def e(s):
    return html.escape(s, quote=False)


def main():
    specs, val = read("specs.csv"), read("validation.csv")
    golden = {g["spec_id"] for g in read("golden.csv")}
    out = []
    w = out.append
    w("""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Test specifications</title>
<style>
:root{--bg:#fff;--fg:#1d1d1f;--mut:#666;--code:#f3f3f5;--line:#ddd;--acc:#0b5cad}
@media (prefers-color-scheme:dark){:root{--bg:#161618;--fg:#e8e8ea;--mut:#9a9aa0;--code:#232327;--line:#333;--acc:#6aa8ff}}
body{background:var(--bg);color:var(--fg);font:16px/1.55 system-ui,sans-serif;max-width:980px;margin:0 auto;padding:24px 16px}
h1{font-size:1.6em;margin:0 0 4px}h2{font-size:1.15em;margin:28px 0 8px;border-top:1px solid var(--line);padding-top:16px}
p.sub{color:var(--mut);margin:0 0 8px}a{color:var(--acc)}
code,pre{background:var(--code);border-radius:4px;font:13.5px/1.45 ui-monospace,Consolas,monospace}
code{padding:1px 4px}pre{margin:0;padding:6px 8px;white-space:pre-wrap;word-break:break-word}
.t{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:14.5px}
th{text-align:left;color:var(--mut);font-weight:600}th,td{border-bottom:1px solid var(--line);padding:6px;vertical-align:top}
td.id{white-space:nowrap;font-weight:600}td.what{min-width:140px}.mut{color:var(--mut);font-size:13px}
input{font:inherit;padding:6px 10px;width:100%;max-width:420px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--fg)}
</style>
</head>
<body>
<h1>Test specifications</h1>
""")
    w(f"""<p class="sub">Every specification the test suite runs: {len(specs)} estimations and {len(val)} input checks, written as the Stata commands that produce the reference results. R and Python run the same specifications (translated through <code>specs/option_map.csv</code>) and every result is compared with Stata's.
How to run them: <a href="TESTING.html">TESTING.html</a>. Known differences: <a href="DIFFERENCES.html">DIFFERENCES.html</a>.</p>
<p class="mut">Each spec starts with <code>use data/&lt;dataset&gt;.dta, clear</code> from the suite's <code>data/</code> folder; <code>graph_off</code> is added to every command. This page is generated from <code>specs/specs.csv</code> by <code>specs/make_specs_page.py</code>.</p>
<p><input id="q" type="search" placeholder="Filter: e.g. weight, by_path, D18, deryugina" aria-label="Filter specifications"></p>
""")
    w('<h2>Blocks</h2>\n<div class="t"><table>\n<tr><th>Block</th><th>What it covers</th><th>Specs</th></tr>\n')
    for b, desc in BLOCKS.items():
        n = sum(s["block"] == b for s in specs)
        w(f'<tr><td class="id"><a href="#block-{b}">{b}</a></td><td>{desc}</td><td>{n}</td></tr>\n')
    w(f'<tr><td class="id"><a href="#block-H">H</a></td><td>Input checks: options that must be accepted or rejected</td><td>{len(val)}</td></tr>\n</table></div>\n')

    for b, desc in BLOCKS.items():
        rows = [s for s in specs if s["block"] == b]
        w(f'<h2 id="block-{b}">Block {b}</h2>\n<p class="mut">{desc}</p>\n<div class="t"><table class="specs">\n'
          '<tr><th>ID</th><th>Stata commands</th><th class="what">What it tests</th></tr>\n')
        for s in rows:
            cmd = f"use data/{s['dataset']}.dta, clear\n"
            if s["prep"]:
                cmd += PREP.get(s["prep"], f"* preparation: {s['prep']}") + "\n"
            opts = (s["options"] + " graph_off").strip()
            cmd += f"did_multiplegt_dyn {s['outcome']} {s['group']} {s['time']} {s['treatment']}, {opts}"
            what = e(describe(s["options"]))
            if s["spec_id"] in golden:
                what += ' <span class="mut">(also compared with saved Stata results)</span>'
            src = f'<div class="mut">source: {e(s["source"])}</div>' if s["source"] else ""
            w(f'<tr><td class="id">{s["spec_id"]}</td><td><pre>{e(cmd)}</pre></td><td>{what}{src}</td></tr>\n')
        w("</table></div>\n")

    w('<h2 id="block-H">Block H: input checks</h2>\n<p class="mut">Each check runs the command below with one option added and records whether Stata accepts it (results are produced) or rejects it.</p>\n'
      '<pre>use data/wagepan.dta, clear\ndid_multiplegt_dyn lwage nr year union, effects(2) placebo(0) graph_off &lt;option&gt;</pre>\n'
      '<div class="t"><table class="specs" style="margin-top:8px">\n<tr><th>ID</th><th>Option</th><th>Expected in Stata</th><th class="what">Why</th></tr>\n')
    for v in val:
        w(f'<tr><td class="id">{v["vid"]}</td><td><code>{e(v["test_option"])}</code></td><td>{e(v["expected_stata"])}</td><td>{e(v["note"])}</td></tr>\n')
    w("</table></div>\n")
    w("""<script>
(function(){var q=document.getElementById('q');if(!q)return;
q.addEventListener('input',function(){var t=q.value.toLowerCase();
document.querySelectorAll('table.specs tr').forEach(function(r,i){if(!r.querySelector('td'))return;
r.style.display=!t||r.textContent.toLowerCase().indexOf(t)>-1?'':'none';});});})();
</script>
</body>
</html>
""")
    (SUITE / "SPECS.html").write_text("".join(out), encoding="utf-8")
    print(f"wrote SPECS.html: {len(specs)} specs, {len(val)} input checks")


if __name__ == "__main__":
    main()
