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

| wave | n | source file | value labels | status |
|---|---|---|---|---|
| w2010 | 33,598 | `cfps2010adult_202008.dta` (Stata-CH) | ✅ | harmonized |
| w2014 | 37,147 | `cfps2014adult_201906.dta` (Stata-CH) | ✅ | harmonized, **label-verified 2026-08-09** |
| 2016 | — | `cfps2016adult_201906.dta` (Stata-CH) | ✅ | on disk, not yet wired |
| 2018 | — | `cfps2018person_202012.dta` (Stata-CH; +ENG variant) | ✅ | on disk, not yet wired |
| 2020 | — | `cfps2020person_202306.dta` (Stata-CH) | ✅ | on disk, not yet wired |
| 2022 | — | `cfps2022person_202410.dta` (Stata-CH) | ✅ | on disk, not yet wired |

The deposit has **no SPSS files** (Stata + SAS only; SAS ships without value-label
catalogs — never harmonize from the SAS variants). **No 2012 data exists in the
deposit at all** (0 files; only 2012 questionnaires) — if a paper ever needs the
2012 wave, it must be sourced separately from PKU. ⚠️ From 2018 the individual
module is renamed `person` (adult+child unified); 2022 ships password-protected
(password = the compliance sentence in its `Instructions.docx`). ⚠️ Variable
names are LOWERCASE in Stata releases, UPPERCASE in SAS releases — specs follow
Stata.

**2014 label-verification results (2026-08-09)** — three scaffold assumptions
were wrong, all fixed same day:
- `qn1001` trust disposition codes are **{1, 5}** not {1,2} — the assumed
  `[1,2]` range would have deleted all 14,628 "can't be too careful" answers.
  Now recoded 1→1, 5→0 (binary, 1=trusting).
- The 2014 government-experience battery **adds 3 = witnessed-but-not-
  experienced** (n≈2,400–3,300/item), absent in 2010. Harmonized binary =
  PERSONAL experience (3→0, documented); read raw `qn1014-1017` for 3-category.
- **`cfps_party` is NOT a CCP-membership variable** despite its variable label:
  value labels read 0=数据缺失/1=数据正常 and zero of its code-1 cases have a
  join year. `ccp_member` is null in both waves; `pn401a` is real but
  skip-routed (n≈1,055). Derive membership from `ccp_join_year` (members-only)
  or find a full-sample source in famconf/2018+ person files.
- Also: `cfps2014edu` code 9 = 不必读书 covers **1,943 real adults** —
  declared-dropped from the 1–8 ladder pending investigation.

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
