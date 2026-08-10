# CFPS — China Family Panel Studies

**Status: Complete for deposited waves** — all 6 (2010–2022), adult frame.
Built 2026-08-09 for paper 26 (political views of Dragon Children).

## What this is

Biennial family panel run by Peking University ISSS, 2010–2022, plus 2008/2009
pilots. **This is a PANEL**: `data/processed/cfps_harmonized.rds` is person-wave
long (193,695 rows across six waves) — cluster on `pid`, never treat rows as
independent. KLoSA-class caveat: cannot row-bind with the
cross-sectional attitude surveys.

## Coverage

| wave | n (16+) | source file | notes |
|---|---|---|---|
| w2010 | 33,598 | `cfps2010adult_202008.dta` | adult module |
| w2014 | 37,147 | `cfps2014adult_201906.dta` | label-verified 2026-08-09 |
| w2016 | 36,892 | `cfps2016adult_201906.dta` | full-sample `qn4001` CCP item (8.3%) |
| w2018 | 34,734 | `cfps2018person_202012.dta` | person module, 2,620 under-16 dropped |
| w2020 | 26,387 | `cfps2020person_202306.dta` | person module, 2,143 under-16 dropped |
| w2022 | 24,937 | `cfps2022person_202410.dta` | person module, 2,064 under-16 dropped; wv opinion battery subsampled (~7k) |

**193,695 person-waves, 40 columns.** From 2018 the individual questionnaire is
the unified `person` module (children from ~9); the loader filters person waves
to **age ≥ 16** to keep the adult frame consistent. Instrument continuity:
government evaluation (`qn4`/`qn1101`) spans all six waves; the trust battery,
trust disposition (`pn1001` in 2016, `qn1001` otherwise), and corruption
severity run 2014–2022; the government-experience battery runs 2010–2016 only
(2014 has an extra "witnessed" category; 2016 reverts to plain yes/no); the
meritocracy opinion battery runs 2010 (`qm70x`) and 2018–2022 (`wv10x`, same
trap coding, plus new `wv106` corruption-inevitable); subjective position runs
2010 (`qm40x`) and 2014–2022 (`qn8011`/`qn8012`/`qn12012`, `qn12016` 2018+).
Birth month exists 2010 and 2018–2022 (`qa001m`) — 2014/2016 get month via
panel `pid` linkage. CCP membership is full-sample **only in 2016** (`qn4001`;
elsewhere skip-routed or the `party` missing-means-no trap — see spec note).
Dragon cohorts in-frame: 1988ers all six waves; **2000-born enter at 2016
(n=461)**; trust-in-officials item relabels 干部 → 本地政府官员 from 2020.

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
  join year. `pn401a` is real but skip-routed (n≈1,055).
  Full-sample membership exists only in w2016 (`qn4001`); see the spec note
  for the 2018+ new-respondent-only routing.
- Also: `cfps20XXedu` code 9 = 不必读书 ("no need for schooling") is **folded
  into ladder floor 1**: all 1,943 carriers (2014) have exactly 0 education
  years, mean age ~60, 74% female, 66% rural — the never-schooled profile
  (interpretation Jeff's, verified empirically 2026-08-09).

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
(0.076–0.090 per animal). **2000-born dragons are IN the adult frame from
2016** (n=461, persisting 324/321/290 through 2022); 2012-born dragons remain
child-module through 2022 and would enter around CFPS 2028.

## No verbatim dictionary yet

Required before papers cite item wording (repo standard). Questionnaires for
2010–2018 (CHN; ENG for 2014–2018) are on disk in `data/cfps/raw/` (gitignored
per the repo *.pdf rule); 2020/2022 questionnaires are not deposited at PKU —
use the .dta variable labels + the 2018 instrument as reference for those.
Chinese-first extraction, like KIPA/KGSS.

**Row identity:** `row_uid` (bank-wide); native panel key `wave+pid` (unique, verified).
