# KLoSA Harmonization — Design Spec

**Date:** 2026-07-17
**Survey:** KLoSA (Korean Longitudinal Study of Aging / 한국고령화연구패널)
**Downstream consumer:** Paper 9 — *"Does a pension buy a citizen?"* (target: *Journal of Asian Public Policy*)
**Status:** Design approved; pending spec review → implementation plan.

---

## 1. Purpose

Harmonize a **focused RD variable set** from KLoSA to support Paper 9, whose design is:

- **Estimator:** sharp/fuzzy RD at age 65, plus a **diff-in-disc** across the July-2014 Basic Pension reform (the design "worth doing" — it differences out everything static about turning 65 in Korea).
- **Running variable:** age; **cutoff:** 65 (Basic Pension eligibility).
- **Subsample:** bottom-70%-income (the pension means-test group); top-30% is the placebo complement.
- **Treatment:** Basic Pension eligibility/receipt; the pre/post-2014 contrast is a **dose** effect (see §6), not on/off.
- **Outcome:** civic/social participation (KLoSA social-activity module).

**This repo's boundary:** produce a clean, documented **person-wave dataset** + a **cross-wave instrument-stability audit**. All RD/DiD-RD estimation, bandwidth selection, and the 소득인정액 / bottom-70% construction live in the **paper repo**, not here.

## 2. Scope & standalone status

- KLoSA is a **standalone** survey in this repo. It is an aging/health/labor/income panel and shares almost no items with the political-attitude surveys (ABS/WVS/KGSS/…). It **cannot row-bind** with them — a KIPA-Corruption-style caveat to record in `docs/surveys/klosa.md` and CLAUDE.md.
- KLoSA is a **genuine longitudinal panel** (same individuals tracked via a stable personal ID), unlike every other survey here (repeated cross-sections). This is handled by the architecture in §4 without new engine code.

## 3. Source data & waves

- **Source:** raw English wave releases `w0N_e.sav` (main respondent file), located in `~/Downloads/KLoSA 1-9th wave (SPSS).zip`. To be copied into `data/klosa/raw/`.
  - The main `w0N_e.sav` file carries the A- (activity), E- (income/transfers), and G- (Basic Pension) modules we need. The companion `str0N_e.sav` (~20 MB) and `Lt0N_e.sav` (~4 MB, likely tracking/weights) files are **not required** for Paper 9; characterize them at load time only if weights turn out to live there (see §7).
  - `w05_new_e.sav` = wave-5 refresher-cohort file; fold into W5 at load if present.
  - EXIT interview files (W7–W9, attrited/deceased) are **out of scope** for Paper 9.
- **Waves:** harmonize **W1–W9** (biennial). Analysis window is **W2–W9**; **W1 (2006)** is retained as a **pure placebo** — it predates *any* pension, so no age-65 discontinuity should appear there. Note the treatment block (§5) is structurally absent in W1 (nothing to receive) — that is the point of the placebo.
  - Wave→year: W1=2006, W2=2008, W3=2010, W4=2012, **W5=2014** (first post-Basic-Pension wave; reform effective July 2014), W6=2016, W7=2018, W8=2020, W9=2022.
- **Gateway "Harmonized KLoSA" (HRS-standard)** file is **optional covariate enrichment**, folded in as a *second pass*. It is a free g2aging.org download behind a login + data-use agreement (user must fetch; drop at `data/klosa/raw/gateway/`). **Not on the critical path** — identification rests entirely on raw-file constructs.

## 4. Architecture

Fits the existing shared harmonization engine; **no new engine code**.

- Standard 3-file module `src/r/data_prep_modules/klosa/`:
  - `0_load_waves.R` — read `w0N_e.sav` W1–W9 → `list(w1=…, …, w9=…)`; fold in `w05_new` if present.
  - `2_harmonize_all.R` — `run_survey_harmonization("klosa", load_klosa_waves, …)`.
  - `99_create_final_dataset.R` — stack per-wave harmonized frames → long **person-wave** rows → `data/processed/klosa_harmonized.rds`.
- YAML specs in `src/config/klosa/harmonize/*.yml` (one file per concept group, §5).
- **Panel linkage** = the harmonized `pid` column riding through the stacked long output. Same `pid` across rows ⇒ pooling + clustering SEs on individual + panel robustness are all available downstream. No wide-by-person restructure (YAGNI — the RD needs person-wave rows + `pid`, not a wide panel).
- Columns carried: `pid`, `wave` (integer 1..9), `year` (2006..2022), plus harmonized concept variables. (Wave keys `w1..w9`; analysis window filters `wave >= 2`.)

## 5. Concept groups & variable anchors

Anchors verified by metadata peek on w04 (2012), w05 (2014), w09 (2022). Exact per-wave codes finalized during spec-build.

| Group (YAML file) | Anchor vars | Notes |
|---|---|---|
| `identifiers.yml` | `pid`, household id, `wave`, `year`, weights | confirm exact `pid`/weight names at load (§7) |
| `demographics.yml` | sex, birth year, `A002_age`, education, marital status, region (시도), urban/rural, household size, home ownership | RD covariates / balance |
| `age_running.yml` (may live in demographics) | `A002_age` (= survey year − birth year), birth year | **⚠️ integer-year age only** (no birth month located) → coarse forcing variable; a real RD limitation to flag in the audit |
| `pension_basic.yml` (treatment) | **receipt `G111`(W2–W4) → `E111`(W5–W9)**; **amount `G112` → `E113`**; self/couple `G113`; application `G110`; months `E112` | see §6 — the module relocation is finding #1 |
| `pension_other.yml` (confounds) | National Pension receipt `E033` / amount `E035`; other public transfers (basic livelihood security, veterans) | net out the age-60/65 NP confound; keep NP distinct from Basic Pension |
| `participation.yml` (outcome) | membership `A033m01–06` (religious / social club / leisure-culture-sports / alumni-hometown-family council / volunteer / **political-party-NGO-interest**), none `A033m08`; frequency `A035_01–07` | derive `participation_any`, `participation_count`, `participation_civic` (the political/NGO/interest item), `participation_volunteer`, `participation_religious`, per-type membership + frequency |
| `income_assets.yml` (means test) | household total income + components (E-module), financial assets, real-estate assets | exposes the ingredients; the 소득인정액 approximation + bottom-70% cut is **paper-side** |
| `health.yml` | self-rated health, ADL/IADL limitations | controls; Gateway enrichment can supplement in pass 2 |
| `work.yml` | employment / retirement status | controls |

## 6. Two design decisions that serve the paper's honesty

1. **Treatment module relocation (finding #1).** Basic Pension receipt/amount moves from the **G-block** (W2–W4, "Basic Old-Age Pension") to the **E-block income module** (W5–W9, "Basic Pension (Ex Basic Old-Age Pension)"), while the legacy `G11x` block **persists post-2014 still labeled "Old-Age."** A naive constant-name pull would corrupt the treatment at the 2014 boundary. Spec maps receipt `G111→E111`, amount `G112→E113`, with a wave-by-wave assertion that legacy `G111` is dead post-2014 and `E111` absent pre-2014.
2. **Dose, not on/off.** Pre-2014 is not untreated — the 기초노령연금 (2008) paid a smaller benefit to a similar population. Harmonizing **amount** (not just receipt) lets the paper characterize the pre/post dose *empirically* rather than assert it. Estimand = dose effect; still identified, smaller/more honest claim.
3. **National Pension kept separate** so the contributory, age-linked (retirement age 60→65) NP is not conflated with the means-tested Basic Pension at the 65 cutoff.

## 7. Verify at implementation time (load-time checks)

- Exact `pid` variable name and stability across W1–W9; household ID.
- **Weight location** — main `w0N` file vs. `Lt0N` tracking file; harmonize cross-sectional + longitudinal weights.
- Participation battery (`A033`/`A035`) present in **W1** (should be; confirm) and its value-scale stability across all waves.
- Birth-month availability anywhere (would improve RD granularity); confirm none before declaring integer-year limitation.
- Region variable coding (시도) and any cross-wave code drift (a known trap in this repo for other surveys).
- Confirm legacy `G111` is empty/dead in W5–W9 and `E111` absent in W2–W4.

## 8. Deliverables

1. `src/r/data_prep_modules/klosa/{0_load_waves,2_harmonize_all,99_create_final_dataset}.R`
2. `src/config/klosa/harmonize/*.yml` (concept groups per §5)
3. `data/klosa/raw/` populated from the Downloads zip; `data/processed/klosa_harmonized.rds`
4. **Verbatim question dictionary** `data/klosa/questionnaire_text/klosa_verbatim_items.csv` (mandatory repo standard) — one row per harmonized_name × wave.
5. **Instrument-stability audit** (the headline deliverable): per-item stem-text + response-scale comparison across W1–W9 for the participation battery and the treatment item, written into the dictionary `notes` and summarized — states plainly where the instrument moved (the G→E relocation) and whether the participation battery is asked identically across the 2014 split.
6. `docs/surveys/klosa.md` (per-survey doc) + CLAUDE.md survey-table row + standalone/scale caveats.
7. Run through the repo's post-harmonize QA (validate spec, freshness manifest, label-reconciliation audit).

## 9. Out of scope (YAGNI)

- Full KLoSA harmonization (hundreds of vars across all modules) — only the RD set above.
- EXIT interview files; `str0N`/`Lt0N` beyond weights.
- Wide-by-person panel restructure; cross-survey pooling with political surveys.
- The RD estimation, bandwidth, 소득인정액 construction, bottom-70% cut — all paper-side.

## 10. Risks

- **Age granularity** (integer years) may be coarse for a tight RD bandwidth — flagged, paper-side mitigation.
- **Treatment relocation** must be nailed exactly or the DiD-RD is corrupted at the boundary — mitigated by §6.1 assertions.
- **Means-test approximation** from KLoSA income/assets ≠ official 소득인정액 — exposed as ingredients; paper owns the construction and its caveats.
- **Gateway two-source provenance** if enrichment is used — tracked, kept off critical path.
