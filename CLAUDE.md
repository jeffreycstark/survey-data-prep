# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Project**: Multi-Survey Harmonization Data Pipeline

## Surveys at a glance

| Survey | Status | Coverage | Per-survey docs |
|---|---|---|---|
| Asian Barometer (ABS) | Complete | 330 vars, 6 waves, 113,945 resp; W6 = 12 countries | [docs/surveys/abs.md](docs/surveys/abs.md) |
| World Values Survey (WVS) | Complete | 62 vars, 7 waves, 446,767 resp, 108 countries | [docs/surveys/wvs.md](docs/surveys/wvs.md) |
| Latinobarómetro (LBS) | Complete | 19 vars, 24 waves 1995–2024, 489,771 resp | [docs/surveys/lbs.md](docs/surveys/lbs.md) |
| Afrobarometer | Complete | 38 vars + 3 indices, R1–R9 + partial R10, 391,815 resp; T&M extension items R5/R8/R9 | [docs/surveys/afro.md](docs/surveys/afro.md) |
| Arab Barometer | Verbatim done; harmonization in progress | W1–W8 | [docs/surveys/arab-barometer.md](docs/surveys/arab-barometer.md) |
| KAMOS | Complete | 39 vars, 2 waves (2016, 2019), 3,500 resp | [docs/surveys/kamos.md](docs/surveys/kamos.md) |
| KGSS | Complete | 187 vars, 17 years 2003–2025, 23,282 resp | [docs/surveys/kgss.md](docs/surveys/kgss.md) |
| KIPA Corruption | Complete | 36 vars, 20 years 2004–2023; **specialty sample** | [docs/surveys/kipa_corruption.md](docs/surveys/kipa_corruption.md) |
| KINU Unification | Complete | 127 vars, 13 waves 2014–2023 (biannual 2019–2021) | [docs/surveys/kinu.md](docs/surveys/kinu.md) |
| IPUS Unification | Initial | 11 vars, 18 annual waves 2007–2024, 21,617 resp | [docs/surveys/ipus.md](docs/surveys/ipus.md) |
| KLoSA (Korean Longitudinal Study of Aging) | Complete | 43 vars, 9 waves W1–W9 biennial 2006–2022, 68,352 person-wave rows, 11,146 distinct `pid`; **standalone aging panel, 45+ only** | [docs/surveys/klosa.md](docs/surveys/klosa.md) |
| Korean Unification Tri-Survey Panel (derived) | Complete | KGSS + KINU + IPUS, 46 wave-rows | [docs/surveys/korean-unification-panel.md](docs/surveys/korean-unification-panel.md) |
| CFPS (China Family Panel Studies) | Scaffold | 37 vars, 2 waves (2010, 2014) of 7, 70,745 person-waves; **family PANEL, adult module only**; 2014 SAS release has no value labels; zodiac/dragon via `src/r/lookups/zodiac.R` (paper 26) | [docs/surveys/cfps.md](docs/surveys/cfps.md) |
| Global Corruption Barometer (GCB) | Scaffold | 22 vars, 1 edition (Asia 2020), 19,416 resp, 17 countries; region-extensible | [docs/surveys/gcb.md](docs/surveys/gcb.md) |
| V-Dem v15 | Scaffold | Country-year panel, 202 countries, 1789–2024 | [docs/surveys/vdem.md](docs/surveys/vdem.md) |
| MARPOR / CMP (MPDS2025a) | Scaffold | **party × election** panel (NOT individual respondents), 5,285 manifestos, 67 countries, 822 elections, 1920–2025 | [docs/surveys/marpor.md](docs/surveys/marpor.md) |
| UNGA voting (Bailey–Strezhnev–Voeten) | Scaffold | **country × year** ideal points (11,610 rows, 198 states, 1946–2025) + **country × roll-call** votes (1,283,746 rows, 6,551 roll-calls, 1946–2022). NOT respondents. | [docs/surveys/unga-unsc.md](docs/surveys/unga-unsc.md) |
| UNSC non-permanent membership | Scaffold | **country × term** (296 terms) + country-year (590 rows), 1970–2028, P5 excluded. NOT respondents. **Second source not yet reconciled.** | [docs/surveys/unga-unsc.md](docs/surveys/unga-unsc.md) |
| OECD DAC bilateral aid (DAC2A + DAC3A) | Scaffold | **donor × recipient × year**, 944,968 rows, 1960–2024, 50 bilateral donors. NOT respondents. ⚠️ `donor_type == "aggregate"` rows are SUMS; ⚠️ the two tables use different constant-price base years (2022 / 2024) | [docs/surveys/unga-unsc.md](docs/surveys/unga-unsc.md) |

⚠️ KIPA Corruption is **NOT a general-population survey** — corporate employees + self-employed with gov-business contact. Cannot row-bind with KGSS/KAMOS/KIPA-social.

⚠️ **MARPOR, V-Dem, UNGA and UNSC are not surveys.** Their units of observation are party × election, country × year, country × roll-call and country × term — there are no respondents, no questionnaire and no waves. They therefore have **no verbatim question dictionary** and **no YAML harmonize spec**, and neither absence is a gap. Do not row-bind them with the respondent-level surveys above.

⚠️ **The two UNGA files come from different versions of one Dataverse deposit** (ideal points v38.0, votes v33.0), so their coverage ends in different years — 2025 and 2022. That is version skew, not a property of the data.

---

## QA & confidence

The harmonization is guarded by a layered audit system (`src/r/audit/`). Before trusting a "clean" run — or defending the data in a paper — read [docs/QA.md](docs/QA.md): the **confidence guide** that verifies (by fault injection) what each QA layer provably catches and, critically, what it does **not**. Key caveat baked in there: the post-harmonize direction gate is **report-only by default**, and ABS currently carries a known 18-error label-reconciliation backlog that a normal run passes silently (set `HARMONIZE_AUDIT_GATE=block` to enforce).

---

## Project Purpose

This repo houses reusable survey data harmonization infrastructure:
- YAML-driven variable specifications (separate spec sets per survey)
- Automated scale detection, reversal detection, and recoding
- Multi-wave data loading, harmonization, and validation
- Codebook search and analysis tools

Each survey has its own data directory, YAML specs, and pipeline cycle. It is **not** a paper repo. Papers that consume the harmonized data live in separate repositories.

For the directory tree, see [docs/STRUCTURE.md](docs/STRUCTURE.md).

---

## Data Processing Pipeline

```
Raw Survey Data (data/{survey}/raw/)
           ↓
    Load & Parse (src/r/survey/load_data.R)
           ↓
  Search Variables (extract_matches in src/r/utils/search.R)
           ↓
  Generate YAML (src/r/codebook/codebook_workflow.R)
           ↓
  User Reviews YAML (src/config/{survey}/harmonize/*.yml)
           ↓
  Harmonize Data (src/r/harmonize/harmonize.R)        ← shared engine
           ↓
  Validate Results (src/r/harmonize/validate_spec.R)  ← shared engine
           ↓
Harmonized Output (data/processed/)
           ↓
Generate Reports (src/r/harmonize/report_harmonization.R)
           ↓
Build Verbatim Dictionary (see below)
```

### Verbatim Question Dictionary (mandatory for every survey)

Every harmonized survey **must** have a verbatim question dictionary CSV that maps harmonized variable names to the literal questionnaire text. This is the single source of truth for Appendix A in all papers.

**Standard format** (follows `data/abs/questionnaire_text/abs_verbatim_items.csv`):

| Column | Content |
|--------|---------|
| `wave` | Wave/year identifier (w1, y2013, etc.) |
| `question_id` | Raw variable name in source data (q43, q5_3, etc.) |
| `harmonized_name` | Standardized variable name in harmonized dataset |
| `section` | Questionnaire section heading |
| `stem_text` | Battery stem question (for sub-items) |
| `item_text` | Verbatim question text as read to respondent |
| `response_scale` | Response options with numeric codes |
| `notes` | "Not included in this wave" for gaps, translation issues, known errata |

**Rules:**
- One row per harmonized_name × wave/year (include rows where variable is absent)
- Source verbatim text from official questionnaire documents (PDF, HWP, DOC), **not** SPSS variable labels
- For battery questions, split into `stem_text` (parent) and `item_text` (sub-item)
- Store original questionnaire files in `data/{survey}/questionnaires/originals/`
- Store extracted text in `data/{survey}/questionnaires/`
- Dictionary CSV goes in `data/{survey}/questionnaire_text/{survey}_verbatim_items.csv`
- Document known errata in `notes` (e.g., KIPA English SPSS mislabels 사법부/judiciary as "legislature")

Per-survey dictionary status lives in each survey's docs page.

**Appendix A workflow:** Papers in paper-bank consume these dictionaries via the `appendix-variable-builder` skill (`scripts/appendix-variable-builder/`). The skill is an R generator (`build_appendix.R`) that joins the per-survey verbatim CSV with the harmonization YAMLs and emits paper-13-style markdown — per-wave question-ID grids, verbatim item text, response scales, harmonization notes, and shared-stem battery auto-detection. This repo owns the ground truth; paper repos only format and present. See `scripts/appendix-variable-builder/SKILL.md` for usage.

### Running pipelines

Each survey's run commands live in its docs page (e.g., [docs/surveys/kgss.md](docs/surveys/kgss.md)). The general pattern is:

```bash
Rscript src/r/data_prep_modules/{survey}/0_load_waves.R       # if applicable
Rscript src/r/data_prep_modules/{survey}/2_harmonize_all.R
Rscript src/r/data_prep_modules/{survey}/99_create_final_dataset.R
```

ABS lives at `src/r/data_prep_modules/` (no subdir). V-Dem only has step 99 (scaffold).

---

## YAML Workflow

### Generate YAML for a New Concept
```r
source("src/r/codebook/codebook_workflow.R")
results <- extract_matches("search term", w1, w2, w3, w4, w5, w6)
yaml_str <- generate_codebook_yaml(results, concept = "concept_name")
cat(yaml_str)
writeLines(yaml_str, "src/config/abs/harmonize/concept_name.yml")  # or wvs/, etc.
```

### Batch Process Multiple Concepts
```r
source("src/r/codebook/codebook_workflow.R")
results_list <- list(
  economy = extract_matches("economic condition", w1, w2, w3, w4, w5, w6),
  politics = extract_matches("trust government", w1, w2, w3, w4, w5, w6)
)
batch_generate_yaml(results_list, output_dir = "src/config/abs/harmonize/")
```

For deeper codebook tooling docs, see `src/r/codebook/` (README, QUICK_REFERENCE, SKILL_SEARCH_AND_ANALYZE).

---

## Cross-survey scale gotchas

The single most error-prone area. Read before merging or comparing across surveys.

- **Trust scales differ across surveys**:
  - ABS / WVS / LBS / Afro institutional trust: **1–4**, higher=more trust.
  - KAMOS trust: **0–10**, higher=more trust.
  - KINU `trust_*`: **0–10**, higher=more trust. ⚠️ This line previously listed KINU among the 1–4 surveys — it is not, and never was. Every `trust_*` column in `kinu_harmonized.rds` (`trust_general`, `trust_president`, `trust_administration`, `trust_courts`, `trust_assembly`, `trust_parties`, `trust_media`) is a 0–10 identity map of the raw `at07**` items, as `national_attitudes.yml` states. Pooling KINU trust with ABS/Afro trust on a 1–4 assumption silently produces nonsense. Also: **w2014 carries only `trust_general`** — the six institutional trust items are unmapped for that wave.
  - KGSS `conf_*`: **1–3**, higher=more confidence.
  - Do not combine without rescaling.
- **Korean unification direction**:
  - IPUS `uni_necessity` and KINU `uni_necessity`: higher=more pro-unification ✓
  - KGSS `pol_unification`: higher=LESS pro-unification (OPPOSITE; reverse before comparing).
  - The pre-built `korean_unification_panel.rds` already aligns directions.
- **`subjective_class_6pt` direction is OPPOSITE between KGSS and KINU**.
- **Education: use `education_5cat`, never `education_level_01`, to compare surveys.** Each survey stores education on its own native ladder (ABS 1–10, Afro 0–3 condensed + 0–9 detailed, LBS 1–7, KGSS 0–8, WVS 1–6). `education_level_01` is a min-max rescale of *that survey's own* ladder, so its step size differs (ABS 1/9, Afro 1/3, WVS 1/5) and 0.5 means different things in different files — it is a within-survey covariate only. The cross-survey columns are `education_5cat` (1=No formal, 2=Primary, 3=Secondary, 4=Post-secondary/some university, 5=University degree or post-graduate) and `education_5cat_01 = (education_5cat − 1)/4`. Both are produced from the single mapping in `src/r/utils/education.R`; a secondary-educated respondent is 0.5 in every survey. Two traps that bit us: **KGSS `education` code 8 = "other"**, not a level above PhD, so `normalize_01(education)` ranks it top — always go through `edu5_from_kgss()`, which sends 8 to NA. And **Afrobarometer codes 8/9 on the 0–9 ladder are substantive** ("University completed", "Post-graduate"), *not* the Refused/Don't-know they mean on Afro's 0–3 items; the shared `treat_as_na` convention deleted 16,172 of them until 2026-07-09 (fixed: `education_ladder_missing`). ⚠️ WVS `education_level` widened from 3 to 6 levels on 2026-07-09 — anything built against the old 3-level column must be re-run.
- **KIPA judiciary mislabel**: English SPSS labels mistranslate 사법부 (judiciary) as "legislature". Korean-label matching is correct.
- **KIPA bribery denominator changes at 2016**: `corr_bribery_experience_1yr` is routed behind a prior official-contact screener from 2016 onward. Roughly half of each annual sample is skipped (비해당, raw `-1`), and the harmonized file collapses that to `NA`, where it is indistinguishable from a refusal. The naive `mean(x == 1, na.rm = TRUE)` therefore switches, mid-series, from a population rate to a rate **conditional on official contact** — about 2× higher — and manufactures a spurious uptick at the 2015→2016 boundary (1.90% → 3.46% conditional, vs 1.90% → 1.60% unconditional). Use `kipa_bribery_series()` (`src/r/lookups/kipa_bribery_series.R`), which returns both denominators; `uncond_pct` is the one comparable to a full-population measure such as ABS witnessed corruption. Gating is present in **all** of 2016–2021 — routed-out per n=1,000: 2016=538, 2017=499, 2018=497, 2019=537, 2020=575, 2021=487 — even though only 2016/2019/2020 are gated in the printed codebooks. `qc.gated_waves` lists all six.
- **ABS `region` numeric codes are NOT stable across waves** (Thailand verified; check before trusting any country). W4 `region` and W5 `Region` use **803=Central, 804=Northeast**; the W6 Thailand file `REGION` **swaps them: 803=Northeast, 804=Central**. W6's value *labels* are correct — the swap only bites code that pools the **raw numeric** code across waves. Always `as_factor()` **per file** before `bind_rows()`. W6's mapping is confirmed by sample allocation (Isan is the largest cell, n=415) and by `IR2c` (403/415 of code-803 interviews were conducted by Esan-language interviewers). Also: **W1–W3 have no region variable at all** for Thailand — only `level3` (urban/rural) — so ABS regional analysis is structurally W4–W6-only. Diagnostic: `results/paper05_thailand_deep_south.R`.
- **ABS W5 trust levels are on a pole-merged scale — use the `*_w5_6pt` companions for W5.** W5 fielded the 13 institutional-trust items, 4 social-trust items and `econ_family_income_fair` on 6-point scales, collapsed 6→4 by merging both poles (raw 1,2→4; 5,6→1), so W5 top/bottom bins hold two native categories vs one in every other wave and W5 top-box shares/means are inflated ~2.4–4.6×. Since 2026-08-08 each item has a native W5-only companion `<id>_w5_6pt` (1–6, higher = more trust / fairer) — use it for any W5 level; use the 4-pt columns only for W4↔W6 comparisons that bypass W5. W4→W5/W5→W6 change scores on the 4-pt columns are artefactual. See docs/surveys/abs.md "W5 trust seam".
- **ABS system-support battery direction**: the four agree/disagree items — `system_capable`, `system_prefer`, `system_proud`, `system_deserves_support` — all share raw coding **1=Strongly agree → 4=Strongly disagree** and are **reversed** in harmonization (`safe_reverse_4pt`) so higher = more system support. `system_needs_change` is a *different* item (raw 1=works fine → 4=should be replaced), **not** reversed → higher = more desire for change. ⚠️ Historical bug: `system_deserves_support` was harmonized **without** reversal until 2026-06-20 (fixed `safe_4pt_none` → `safe_reverse_4pt`). Any paper `analysis_data.rds` built before that date carries this one item backwards (opposite its three battery-mates); re-run against the corrected `abs_harmonized.rds`. Some papers applied a manual `5 - system_deserves_support` to compensate for the bug — those will **double-reverse** (become wrong) when re-run against fixed data, so remove the manual reversal there.
- **WVS `freedom_vs_equality` W2 vs W7 code order — fixed 2026-07-31, re-run anything older.** The two waves do not share a code order: W7 (`Q149`) is binary 1=Freedom/2=Equality, but W2 (`V247`) is three-category with the middle option **second** — 1=Freedom, 2=**Neither**, 3=**Equality**. Until 2026-07-31 both waves used `method: identity` with `valid_range: [1,2]`, so W2 deleted all 8,787 "Equality" responses and relabelled the 2,029 "Neither" responses as "Equality". W2 contained no equality responses at all, and W2↔W7 comparisons pitted W7's equality camp against W2's neither camp. Now an explicit per-wave recode (1→1, 2→NA, 3→2); W2 Equality reads 8,787. Details in `JEFF_MUST_INVESTIGATE.md`.
- **Every processed survey RDS carries `row_uid` — the bank-wide stable row key.** Format `<survey>.<wave>.<position>` (character, e.g. `abs.w5.001234`), minted once in `stack_harmonized_wide()` and hard-asserted (present/non-NA/unique) by every 99-script before saving. Stable across rebuilds while that wave's raw file and loader are unchanged (run manifests hash raw inputs, so renumbering events are freshness-detectable); a changed wave renumbers only itself. **Native IDs (`idnumber`, `pid`, `respid`, `respno`, `numentre`, `s007`, `native_id`) are data columns for raw-traceability and merges — never sole join keys.** Declared key scopes + verified anomalies: `src/config/_audit/key_declarations.yml` and `key_uniqueness_exemptions.yml`, enforced by `check_key_uniqueness.R`.
- **ABS `idnumber` is NOT a respondent key — never join, merge or dedupe on it.** It is a per-country, per-wave sequential counter that restarts every wave, so the same value denotes different people in different waves (`idnumber = 1` occurs in 7 countries in W1, 11 in W2, and so on). ABS is a **repeated cross-section, not a panel** — there is no respondent to follow across waves, and any join on `idnumber` silently fabricates links between unrelated people. Worse, **not even `country + wave + idnumber` is unique**: 113,945 rows collapse to 113,643 distinct triples. The 302 extra rows are **357 rows with a NA `idnumber`** (spread over 55 country×wave cells) plus **2 genuine duplicates in Hong Kong W5** (`704273201`, `704273901`). Excluding the NAs, 113,588 rows give 113,586 distinct triples. **There is no unique row identifier in `abs_harmonized.rds` — row position is the only one.** If you need a stable key, mint one at load (`dplyr::row_number()`), and never carry `idnumber` into a `left_join`. (Verified 2026-08-09.)
- **ABS `int_year` is complete for W1 and W4–W6 only.** W2 is 74.6% (Korea, Philippines, Thailand, Singapore have no interview date **at all** — the whole `ir9_*` block is empty) and W3 is 94.8% (Singapore missing). Since `birth_year = int_year - age` is the only route to a cohort variable, **any generational analysis silently returns all-NA for those cells** rather than erroring. W1 was fixed 2026-08-09 by repointing from `ir007_3` to `yrsurvey` (recovering Korea 1,500 and Mongolia 1,144); W2 is not fixable from the data and awaits ABS fieldwork documentation — see `data/lookups/abs_fieldwork_years.csv`. Do **not** assume a single year per wave: the nine W2 countries with dates spread across 2004–2008, and China alone splits 531 cases in 2007 against 4,508 in 2008. Related: **ABS W1 and W2 ship no survey weights** (`weight`/`weight_cross` are W3+ only), so W1/W2 analysis is unweighted by necessity.
- **KLoSA is a standalone aging PANEL — cannot row-bind with the political surveys.** It samples Koreans 45+, tracks the same individuals wave to wave (`pid`), and carries essentially no political-attitude items — a KIPA-Corruption-style caveat (different universe, different design). `data/processed/klosa_harmonized.rds` is **LONG, person-wave keyed** (up to 9 rows per `pid`, 68,352 rows / 11,146 distinct `pid`) — cluster standard errors on `pid`, don't treat rows as independent.
- **KLoSA Basic Pension treatment is harmonized in BOTH blocks; G-block is the named default.** `basic_pension_receipt`/`_amount`/`_couple` (G111/G112/G113, W2–W9) are stable across the 2014 Basic-Old-Age-Pension→Basic-Pension reform and are the default; `basic_pension_receipt_eblock`/`_amount_eblock` (E111/E113, W5–W9) are a robustness alternate. Three traps: (a) G111 is **screener-gated** — its `NA` means "didn't apply," not "refused," so `mean(x, na.rm=TRUE)` is conditional-on-application (~92%), not a population rate (KIPA-bribery-style denominator trap — treat NA→0 for a population reading); (b) the two AMOUNT measures **diverge ~2× in W5–W6** (G112 schedule-level ≈20 vs E113 received ≈9–10, 10k-won units) before converging by W7–W9 — do not treat them as interchangeable right at the reform boundary the RD identifies on; (c) the E-block **variable number E113 is repurposed pre-2014** (W1–W4 = an unrelated "Other welfare Benefit" flag), correctly nulled in harmonization. See [docs/surveys/klosa.md](docs/surveys/klosa.md).
- **KLoSA trust/participation scales are their own convention, not comparable to the ABS/WVS/KGSS trust families above.** The participation frequency items (`partfreq_*`) are a **1–10 DECLINING-frequency ordinal** (1=almost every day, 10=almost never engaged) — the opposite of an intuitive increasing-frequency scale; reverse (`11 - x`) before treating higher as "more frequent." `srh` (self-rated health) is 1=best…5=worst, its own scale family entirely.
- **KLoSA has a fine RD running variable available, not just integer-year age.** Beyond `age` (integer years), `birth_year` + `birth_month` + interview date (`iw_year`/`iw_month`/`iw_day`) are all populated across W1–W9 and support an age-in-months or days-to-cutoff running variable for the pension-eligibility RD.

---

## Paper-time lookups (`src/r/lookups/`)

Some context is deliberately not baked into harmonized RDS files — coalition labels are contested, crosswalks are partial, and downstream papers may want to choose-at-load rather than disagree-and-override. These lookups live in `src/r/lookups/` and are joined on demand.

- **Cross-wave party lineage** — `join_party_crosswalk()` adds `party_lineage` and `coalition` columns from `data/processed/party_id_crosswalk.csv` (Korea / Taiwan / Thailand × W2-W6). Other (country × wave) combos get NA + a one-time warning. Country-code map at `data/lookups/abs_country_codes.csv`. See `src/r/lookups/README.md` for usage.
- **KIPA bribery denominator** — `kipa_bribery_series()` returns `corr_bribery_experience_1yr` per year under both denominators (`uncond_pct` = full sample, use this; `cond_pct` = answerers only). Necessary because the item is gated behind an official-contact screener from 2016 on; see the gotcha above.

---

## Key Functions

| Function | Purpose | File |
|----------|---------|------|
| `extract_matches()` | Search variable names/labels across waves | src/r/utils/search.R |
| `generate_codebook_yaml()` | Search results → YAML spec | src/r/codebook/codebook_workflow.R |
| `detect_scale_type()` | Identify 5pt/4pt/6pt scales | src/r/codebook/codebook_analysis.R |
| `detect_reversals()` | Find waves with flipped semantics | src/r/codebook/codebook_analysis.R |
| `harmonize_all()` | Apply YAML spec to harmonize data | src/r/harmonize/harmonize.R |
| `validate_harmonize_spec()` | Validate YAML specs | src/r/harmonize/validate_spec.R |
| `report_harmonization()` | Generate QC reports | src/r/harmonize/report_harmonization.R |

---

## Slope Prospector

Trend-anomaly detection tool over harmonized country-wave means. Produces 10 outputs (outlier slopes, structural breaks, divergent pairs, acceleration, concept-group coherence, country clusters, narrative-pattern matches, heatmaps, dashboards). See [docs/SLOPE_PROSPECTOR.md](docs/SLOPE_PROSPECTOR.md). **Findings are puzzles, not conclusions.**

---

## Environment Setup

**R** (primary language): Managed via `renv`. Restore with `Rscript -e "renv::restore()"`. Key packages: tidyverse, haven (SPSS I/O), here, arrow (parquet I/O).

**Python** (minimal use): Managed via `uv`. Setup: `uv sync && source .venv/bin/activate`. Lint: `ruff check src/python/`.

No R MCP is currently configured. R code is executed via `Rscript` in Bash.

## Architecture Notes

**Adding a new survey**: Each survey follows the same 3-file pipeline pattern in `src/r/data_prep_modules/{survey}/`: `0_load_waves.R` → `2_harmonize_all.R` → `99_create_final_dataset.R`. YAML specs go in `src/config/{survey}/harmonize/`. The harmonization engine (`src/r/harmonize/harmonize.R`) is shared across all surveys.

**Shared recoding functions** live in `src/r/utils/recoding.R`: `safe_reverse_3pt/4pt/5pt/6pt()`, `safe_3pt/4pt/5pt/6pt_none()`, plus ~90 wave- and survey-specific helpers (`recode_w*_*`, `collapse_*`). These are referenced by name in YAML spec `fn:` fields and reach each survey via `src/r/utils/_load_functions.R`, sourced from each `2_harmonize_all.R`.

**Spec layout is uniform**: every survey's production specs live in `src/config/{survey}/harmonize/` (ABS: 28 files). ABS used to be the exception, reading a curated `harmonize_validated/`; the two were merged 2026-08-07. Draft specs that must not be loaded live in `src/config/{survey}/_drafts/`.
