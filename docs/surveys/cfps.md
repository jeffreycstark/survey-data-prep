# CFPS — China Family Panel Studies

**Status: Scaffold** (adult module, 2 of 7 waves). Built 2026-08-09 for paper 26
(political views of Dragon Children).

## What this is

Biennial family panel run by Peking University ISSS, 2010–2022, plus 2008/2009
pilots. **This is a PANEL**: `data/processed/cfps_harmonized.rds` is person-wave
long (70,745 rows, 66,565 distinct `pid` across w2010+w2014) — cluster on `pid`,
never treat rows as independent. KLoSA-class caveat: cannot row-bind with the
cross-sectional attitude surveys.

## Coverage

| wave | n | source file | value labels |
|---|---|---|---|
| w2010 | 33,598 | `cfps2010adult_202008.dta` (Stata, Chinese) | ✅ full |
| w2014 | 37,147 | `cfps2014adult_201906.sas7bdat` (SAS, Chinese) | ❌ **none** |

⚠️ **The deposit has NO SPSS files — Stata + SAS only** — and the SAS files ship
without `.sas7bcat` catalogs, so **every 2014 value-coding is assumed from the
CFPS codebook convention**, flagged "assumed"/"verify" in the YAML. The 2014
Stata variant (which has labels) was skipped by the Dataverse 100MB bundle cap,
along with all of 2016/2018/2020/2022 — `data/cfps/raw/MANIFEST.TXT` lists all
59 skipped files. Re-download those to extend.

Pipeline: `src/r/data_prep_modules/cfps/{0_load_waves,2_harmonize_all,99_create_final_dataset}.R`;
specs in `src/config/cfps/harmonize/{demographics,politics}.yml` (37 variables).
2008/2009 pilots and the child/family/community modules are deliberately not loaded.

## Coding gotchas (raw-verified on 2010)

- **All CFPS missing codes are NEGATIVE** (−10 cannot-judge, −9 missing, −8 n/a,
  −7 unmatchable, −2 refused, −1 don't-know) — the `treat_as_na` convention can
  never collide with a positive scale.
- **"No" is code 5, not 0, on the qn20x government-experience battery** (2010:
  n=21,633 at 5, zero at the labelled 0), and `79` = "experience type n/a"
  (n=7,302) is a declared drop. The `govt_*` recodes handle both.
- **The qm70x opinion battery is out of order**: 1=strongly disagree, 2=disagree,
  3=agree, 4=strongly agree, with neutral at **5** and an in-range **6=don't
  know** (n≈5,500). Recoded to ordered 1–5 with neutral centered; 6 declared.
- `govt_eval_county` raw runs 1=great achievements → 5=worse than before;
  **reversed** so higher = better evaluation.

## Dragon Children (paper 26)

Zodiac assignment is a **paper-time lookup** (`src/r/lookups/zodiac.R`,
`add_zodiac()`), not baked into the RDS: zodiac years begin at Chinese New Year,
and public CFPS gives birth year+month only, so Jan/Feb births cannot be
resolved to an animal (flagged `zodiac_boundary`; `dragon_boundary_wide` marks
every could-be-dragon). Run robustness excluding/reassigning boundary births.

Adult-module dragon cohorts (w2010): **1976 (n=549), 1988 (n=484)**, plus 1964
(828) and 1952 (706) for placebo/age comparisons. Zodiac shares are flat
(0.076–0.090 per animal). ⚠️ **2000/2012-born dragons are child-module
respondents** — no political items; out of scope until later waves age them in
(2000-born enter the adult file at CFPS 2016).

## What w2014 adds

Trust battery (0–10: officials/cadres, parents, neighbors, Americans, strangers,
doctors), perceived government corruption severity (0–10), CCP membership flag.
2010-only: the meritocracy/fairness opinion battery and subjective position
items. The government-evaluation and government-experience items exist in BOTH
waves — the panel's only repeated political measures so far.

## No verbatim dictionary yet

Required before papers cite item wording (repo standard). Source: the 2010
questionnaire PDF is in `data/cfps/raw/`; 2012/2014+ questionnaires are in the
skipped-files list. Chinese-first extraction, like KIPA/KGSS.
