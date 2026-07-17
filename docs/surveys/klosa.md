# Korean Longitudinal Study of Aging (KLoSA / 고령화연구패널조사)

**Status**: Complete (43 harmonized vars, 9 waves W1–W9, biennial 2006/2008/2010/2012/2014/2016/2018/2020/2022, 68,352 person-wave rows, 11,146 distinct `pid`, South Korea only).

Conducted by the Korea Employment Information Service (한국고용정보원) since 2006 on a panel of Koreans aged 45+. Built for **Paper 9** ("Does a pension buy a citizen?"), a sharp/fuzzy regression-discontinuity + diff-in-disc design around age 65 on Basic Pension eligibility, outcome = civic/social participation.

## ⚠️ STANDALONE PANEL — cannot row-bind with the political surveys

KLoSA is an aging/health/labor/income **panel** — the same individuals are re-interviewed every wave and linked via `pid` — not a repeated cross-section like ABS/WVS/KGSS. It carries essentially no political-attitude items. This is a KIPA-Corruption-style caveat: **do not row-bind `klosa_harmonized.rds` with any other survey's harmonized file** — different universe (45+ only), different design (panel vs. cross-section), different substantive domain (aging/pension/health, not political attitudes).

`data/processed/klosa_harmonized.rds` is **LONG, person-wave keyed**: the same `pid` recurs across up to 9 rows. Any regression must **cluster standard errors on `pid`** (or use a panel/RD estimator that accounts for repeated observations of the same respondent).

## Pipeline

```bash
Rscript src/r/data_prep_modules/klosa/0_load_waves.R
Rscript src/r/data_prep_modules/klosa/2_harmonize_all.R
Rscript src/r/data_prep_modules/klosa/99_create_final_dataset.R

# Independent QA (not part of the harmonize pipeline, but part of the deliverable set):
Rscript src/r/data_prep_modules/klosa/audit_instrument_stability.R
Rscript src/r/data_prep_modules/klosa/build_verbatim_scaffold.R
```

Source: `data/klosa/raw/w0{1..9}_e.sav` (English-labelled SPSS releases, one file per wave).

## Loading

```r
d <- readRDS("data/processed/klosa_harmonized.rds")
# Or: arrow::read_parquet("data/processed/klosa_harmonized.parquet")
```

Country identifier: `country` = "KOR" (all rows). Wave column: `wave` (integer 1–9); `year` = calendar year via `w1=2006, w2=2008, …, w9=2022`.

## Variable categories

| Category | Variables | Scale |
|----------|-----------|-------|
| Identifiers (6) | pid (panel linkage key, stable across waves), hhid (⚠ lowercase `hhid` W1–W8, UPPERCASE `HHID` W9 — do not confuse with W9's separate `HHID22`), weight (cross-sectional weight `wgt_c`; ⚠ the Horizontal/Vertical weighting label on `wgt_c` vs `wgt_p` appears to swap at W8–W9 relative to W1–W7 — low stakes, but don't trust the label semantics without the official user guide), iw_year, iw_month, iw_day (day-precision interview date, all 9 waves; ⚠ W6's `iw_month`/`iw_day` are stored as zero-padded CHARACTER, routed through `no_verify` so the QC range check compares numbers not strings) | varies |
| Demographics (10) | sex (1=M, 2=F; raw 1/5 recoded), birth_year, birth_month (100% populated all 9 waves), age (running variable for the RD; integer years, `interview_year − birth_year`, no birthday adjustment — ⚠ 3 waves W6/W7/W9 carry a cosmetic SPSS *label*-text bug with wrong wave/year references, but the *stored* age values are verified correct in 100% of spot-checked rows), education (native KLoSA 4-level ladder: 1=Elementary or below…4=College+ — **not** cross-survey `education_5cat`, out of scope here), marital_status, region (Si-do numeric code, non-contiguous), urban_rural (1=Metropolitan…3=Town), hh_size, home_owner (binary, raw 5-cat rental-type collapsed) | varies |
| Basic Pension — TREATMENT (5) | basic_pension_receipt / basic_pension_amount / basic_pension_couple = **G-block, the named default** (G111/G112/G113, W2–W9, stable variable number + coding straight through the 2014 reform); basic_pension_receipt_eblock / basic_pension_amount_eblock = **E-block alternate** (E111/E113, W5–W9 only) | receipt/couple binary 0/1; amount continuous, 10,000 KRW |
| National Pension — confound (2) | natl_pension_receipt (age-linked contributory pension, binary; keep distinct from Basic Pension), natl_pension_amount | binary; continuous, 10,000 KRW |
| Participation — OUTCOME, membership (7) | part_religious, part_social_club, part_leisure, part_alumni, part_volunteer, part_civic (**the "buy a citizen" headline DV** — political parties/NGOs/interest groups), part_none | 0=No, 1=Yes |
| Participation — OUTCOME, frequency (6) | partfreq_religious, partfreq_social_club, partfreq_leisure, partfreq_alumni, partfreq_volunteer, partfreq_civic | 1–10 **DECLINING**-frequency ordinal: 1=almost every day (most frequent) … 10=almost never engaged (least frequent) — reverse (e.g. `11 - x`) before treating higher values as "more frequent" |
| Health (3) | srh (self-rated health, 1=best…5=worst), adl_count (0–8, derived from 8-item raw battery), iadl_count (0–9, derived from 9-item raw battery) | ordinal / count, higher=worse |
| Work (1) | work_status (currently working, binary) | 0/1 |
| Income/Assets — means-test ingredients (3) | hh_income_total, assets_total (absent W1), assets_realestate | continuous, 10,000 KRW |

**Derived (built in `99_create_final_dataset.R`, not part of the 43 harmonized-spec vars)**: `participation_count` (0–6, sum of the 6 substantive membership items, excludes `part_none`), `participation_any` (binary).

## Treatment: Basic Pension (both blocks; G-block is the named default)

The 2014 reform renamed the Basic Old-Age Pension (기초노령연금) to the Basic Pension (기초연금). Two independent questionnaire modules record it:

- **G-block (G111/G112/G113)** — `basic_pension_receipt` / `_amount` / `_couple` — present and STABLE at an unchanged variable number and coding from W2 straight through W9. This is the paper's default treatment source; it crosses the 2014 reform completely intact (the questionnaire never updated the item's own "Basic Old-Age Pension" stem text, but the underlying 1=currently receiving/3=will receive/5=not entitled coding is byte-for-byte identical W2–W9).
- **E-block (E111/E113)** — `basic_pension_receipt_eblock` / `_amount_eblock` — a W5–W9 alternate/cross-check living in the income module.

Row-level RECEIPT agreement between the two blocks is high throughout (~92–99% where both exist).

**Three caveats, all load-bearing for the paper:**

1. **Screener/denominator trap** (KIPA-bribery-style, cf. `src/r/lookups/kipa_bribery_series.R`): G111 is asked of applicants only, so its `NA` is a SKIP (didn't apply), not a refusal. `mean(basic_pension_receipt, na.rm = TRUE)` is therefore **conditional on application** (~92%), **not** a population rate. For a population-level reading, treat skip → 0 (a paper-side choice, not baked into harmonization).
2. **G/E amount divergence near the reform boundary**: the two AMOUNT measures for the SAME benefit diverge ~2× right where the diff-in-disc identifies the effect — G112 (entitlement/schedule level) runs ~20 (10,000-won units) in W5–W6 while E113 (amount actually received) runs ~9–10, converging by W7–W9 (ratio 2.22× at W5, 2.00× at W6, 1.05× at W7, 1.00× at W8–W9). Most likely explanation: the 2014–15 National-Pension-linkage deduction reduced actual payouts below the statutory maximum for higher-National-Pension-benefit recipients in the reform's first two waves, and G112 (schedule-level) doesn't reflect that deduction the way E113 (received) does. **Do not treat G112 and E113 as interchangeable dose measures in W5–W6**; if the identification strategy uses amount (not just receipt) right at the 2014 boundary, prefer E113 for that window or report both and flag the gap.
3. **E-block variable-number repurposing pre-2014**: E113 is not simply absent before 2014 — it EXISTS in W1–W4 as a completely unrelated item ("total amount of Other welfare Benefit," a binary check-flag), only becoming the Basic Pension amount field from W5 on. The harmonization spec (`pension_basic.yml`) correctly restricts the E-block source to W5–W9 and never touches the pre-2014 column — this is confirmed correct by the instrument-stability audit, not an oversight — but it is a hazard for any *future* script that assumes "same variable number = same construct" for the E-block.

`won_to_10k_won()` fixes a genuine unit bug in G112: its SPSS label claims "unit: 10,000 won" but the raw stored values are the literal KRW amount (observed range ~20,000–500,000), confirmed against known 2014 policy amounts (200,000/320,000 individual/couple).

## Outcome: civic/social participation

Membership battery (`part_religious/social_club/leisure/alumni/volunteer/civic` + `part_none`) and paired frequency battery (`partfreq_*`), plus derived `participation_count` (0–6) / `participation_any`. `part_civic` (political parties/NGOs/interest groups) is the headline "buy a citizen" DV.

**Instrument STABLE across the 2014 reform.** W1 uses a different variable-number family (`A017m01-08` / `A019_01-07`) than W2–W9 (`A033m01-08` / `A035_01-07`) for the identical construct and identical coding — a pure questionnaire RENUMBER at the W1→W2 revision, not an instrument change. W1 is usable as the battery's placebo wave without any scale-comparability caveat, and nothing in the outcome battery moves across the W4→W5 reform boundary. Three items (`part_leisure`, `part_civic`, and their frequency pairs) carry cosmetic stem-wording drift at W6 (e.g. `part_civic` "the NGOs, the interest groups" → "NGO, interest groups") that does not change the verdict, since construct and response scale are unchanged.

## Running variable

`age` (integer years, `interview_year − birth_year`) is the base RD forcing variable, but a **finer running variable is available**: `birth_year` + `birth_month` + interview date (`iw_year`/`iw_month`/`iw_day`) together support an age-in-months or days-to-cutoff running variable — this relaxes the integer-year-only limitation an earlier design note assumed. (⚠️ W6's `iw_month`/`iw_day` are zero-padded character in the raw `.sav`; the harmonize spec routes W6 through `no_verify` so range checks compare numbers, not strings.)

## Controls

- **Health**: `srh` (self-rated, 1=best…5=worst). ⚠️ Response wording gains an "Excellent" top category at W3 (2010), pushing "Very good" down to position 2 — a genuine reference-point shift for W1–W2 respondents, but it does not interact with the 2014 treatment discontinuity since both W4 (pre-reform) and W5–W9 (post-reform) share the identical 5-point "Excellent…Poor" scale. `adl_count` (0–8) and `iadl_count` (0–9), both derived from stable component batteries.
- **Work**: `work_status` (currently working, binary).
- **Means-test ingredients** (for the bottom-70% 소득인정액 approximation, paper-side): `hh_income_total`, `assets_total` (absent W1), `assets_realestate` — all 10,000-KRW units, verified against plausible Korean household income/wealth magnitudes.

## QA

`run_validation(survey = "klosa")`: **ok=366 / warn=9 (benign) / err=0**.

Cross-wave instrument-stability audit at `outputs/klosa/instrument_stability_audit.md` (generated by `audit_instrument_stability.R`, metadata pulled directly from each wave's raw `.sav`, independent of `variable_map.csv` or the harmonize YAMLs). Top-line verdicts:

- **Outcome (participation battery)** — NO contamination. All membership + frequency items STABLE or RENUMBERED (W1 only); nothing moves across the 2014 boundary.
- **Treatment (Basic Pension)** — NO contamination on the G-block default; a real but bounded amount-measurement caveat (see above) plus the E-block variable-repurposing hazard.
- **Control (`srh`)** — CHANGED at W3 (2010), not at the 2014 reform boundary; internally comparable across the diff-in-disc window itself (W4 vs. W5–W9).

⚠️ **KNOWN FOLLOW-UP GAP**: the post-harmonize label-reconciliation gate (Check A, `run_post_harmonize_gate("klosa")` in `99_create_final_dataset.R`) runs report-only against KLoSA but currently **SKIPS** its findings because KLoSA has no `.SURVEY_LABEL_LOADER` entry registered in the Phase-4 auditor infrastructure. Wiring one up is a natural follow-up, not implemented as part of this harmonization. Similarly, `src/r/audit/06_check_freshness.R` (Layer 6d) does not yet list `klosa` in `.FRESHNESS_SURVEYS` — freshness checks for this survey are not yet automated.

## Verbatim dictionary

`data/klosa/questionnaire_text/klosa_verbatim_items.csv` — **scaffold** (387 rows, 43 harmonized vars × 9 waves; built by `build_verbatim_scaffold.R`).

⚠️ **Dependency pending**: we do not have the official KLoSA questionnaire booklets (PDF/HWP) on disk. Per the repo's verbatim-dictionary convention (CLAUDE.md), `item_text` should ultimately come from the official questionnaire, not from SPSS variable labels. Until those booklets are sourced, `item_text` is populated from each wave's raw SPSS variable **label** and `response_scale` from the SPSS **value-label** set (both pulled directly from the `.sav` metadata, the same method used by `audit_instrument_stability.R`) — every substantive row is flagged `notes = "... item_text from SPSS label; verbatim backfill from official questionnaire pending."`. This SPSS-label version is sufficient for the instrument-stability verdict but is **not** yet Appendix-A-ready in the sense the other surveys' dictionaries are.

**Possible future Jeff download**: the Korea Employment Information Service (한국고용정보원) publishes the KLoSA questionnaire booklets per wave (Korean; English translations exist for some waves) alongside the microdata on the KLoSA data portal. Sourcing these and re-running the backfill (replacing the SPSS-label `item_text`/`response_scale` with verbatim questionnaire text) is the natural follow-up once the PDFs are in hand — store originals under `data/klosa/questionnaires/originals/` per the repo convention.
