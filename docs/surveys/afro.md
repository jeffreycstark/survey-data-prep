# Afrobarometer (Afro)

**Status**: Complete through R9 + partial R10 (391,815 respondents; R10 = 40,000 across 29 country files stacked by the loader; no merged R10 .sav yet). 2026-07-03: +15 harmonized items and 3 derived indices for the Tambe & Monyake (2023) turnout/clientelism extension (see "T&M extension variables" below) — 70 columns total in the harmonized output.

## Pipeline

```bash
Rscript src/r/data_prep_modules/afro/0_load_waves.R
Rscript src/r/data_prep_modules/afro/2_harmonize_all.R
Rscript src/r/data_prep_modules/afro/99_create_final_dataset.R
```

Raw rounds: `data/afro/raw/round1/ ... round10/` (SPSS `.sav`). Each round directory also contains the round's codebook PDF.

## Loading

```r
d <- readRDS("data/processed/afro_harmonized.rds")
# Or: arrow::read_parquet("data/processed/afro_harmonized.parquet")
```

Country identifier: `country` (3-letter ISO alpha codes, derived from value labels per round).
Round mapping: w1=R1(1999), w2=R2(2002), w3=R3(2005), w4=R4(2008), w5=R5(2012), w6=R6(2015), w7=R7(2017), w8=R8(2019), w9=R9(2022). 42 countries across all rounds (12 in R1, expanding to 39 in R9).

## Variable categories

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Trust (8 of 9) | trust_president (9 rounds), trust_parliament (8, no R1), trust_elections (9), trust_police (9), trust_armed_forces (8, no R4), trust_courts (9), trust_churches (4, R6-R9 only), trust_political_parties (8, no R1) | 1-4, higher=more trust |
| Institutional Trust (NA) | trust_government | NA (no equivalent in Afro) |
| Social Trust (NA) | trust_generalized_binary | NA (no equivalent) |
| Democratic Attitudes (3) | dem_support_preferable (9 rounds, 1-3), dem_satisfaction (8, no R1), dem_how_democratic_qual (8, no R1) | varies |
| Democratic Attitudes (NA) | dem_how_democratic_10pt, dem_best_system | NA (no equivalent) |
| Democratic Support (NA) | dem_nondem_ok, dem_military_support, dem_solves_problems, pol_say_what_think | NA (scale mismatch) |
| Demographics (3) | int_month, int_year, int_date | R9 only |
| Weights (1) | weight | continuous, mean ~1; raw: withinwt (R1-R7), withinwt_hh (R8-R9) |

## T&M extension variables (added 2026-07-03)

For the Tambe & Monyake (2023) replication/extension (paper-bank Block 1).
Specs: `political_participation.yml`, `lived_poverty.yml`, and the
`corr_perc_*` battery in `corruption.yml`. Q-codes verified against the
R5/R6/R8/R9 merged .sav value labels.

| Variable | Rounds | Notes |
|----------|--------|-------|
| turnout | R5, R8, R9 | binary; voted=1, substantive non-vote=0; **not-registered / too-young / can't-remember → NA** (judgment call logged in the spec) |
| vote_buying | **R3, R5, R8** | binary 0=never/1=ever offered. ⚠️ **NOT fielded in R6/R7/R9**. R3 (q57f) added 2026-07-05 for paper 22 (Zeng 2019). For the T&M turnout design the usable window is still **R8 only** |
| corr_perc_president/_mp/_officials/_councilors/_police/_judges | R5, R8, R9 | 0–3 each; R5 judges = Q60G (Q60F = tax officials, excluded per T&M) |
| corruption_perc (derived) | R5, R8, R9 | additive 0–18 index of the six items, complete cases (built in step 99) |
| lpi_food/_water/_medicine/_fuel/_income | R5, R8, R9 | 0–4 each |
| lived_poverty (derived) | R5, R8, R9 | respondent mean of 5 LPI items, complete cases |
| poverty_ctry (derived) | R5, R8, R9 | unweighted country × round mean of lived_poverty |
| polint | **R5, R6 only** | 0–3; unavailable R7–R9 → drop from the R8 extension control set |
| region_admin1 | R5, R8, R9 | raw REGION passthrough; country-specific codes, join on (country, region_admin1) |

Known QC notes: `corr_perc_mp`/`corr_perc_councilors` show 4–10% coverage
loss in R8/R9 — that is the item's real "Don't know/Haven't heard" rate
masked to NA per convention, not a harmonization defect.

## Paper 22 extension variables (added 2026-07-05)

For the clientelism × competitiveness paper (paper-bank paper 22), replicating
Zeng (2019). Specs: `government_performance.yml`, `clientelism_patronage.yml`,
`ethnic_relations.yml`, `vote_intention.yml` (plus `vote_buying` R3 in
`political_participation.yml`). Q-codes + scales verified against the R3/R5/R6/R8
merged .sav value labels and round codebooks 2026-07-05. Paper-specific derived
variables (club-goods PCA, ruling-party crosswalk, binary "vote ruling party",
tenure, competitiveness, V-Dem/WDI merges, co-ethnicity) are built in paper-bank,
**not** here.

| Variable | Rounds | Notes |
|----------|--------|-------|
| perf_health/_education/_water/_roads/_electricity | R5, R6, R8 | govt "handling" items, 1=very badly … 4=very well; Zeng "club goods" (paper-bank builds the PCA factor-1) |
| perf_food | **R5, R6 only** | same scale; ⚠️ R8 dropped the "enough to eat" item → R8 club-goods index = 5 items |
| govt_employee | R6, R8 | binary 1=government employer, 0=self/private/NGO; 7=Not applicable → NA (defined within the employed frame). Zeng patronage. ⚠️ R5 has no employer item |
| occupation | R5, R6, R8 | nominal passthrough (country/round-specific codes). ⚠️ R5 Q96_ARB fielded in a country subset (~6k valid) |
| ethnic_unfair | R3, R5, R6, R8 | 0=never … 3=always ethnic group treated unfairly by government; Zeng control |
| ethnic_group | R3, R5, R6, R8 | nominal passthrough; co-ethnicity input. Join labels via afro_value_labels.csv |
| vote_intent_party | R3, R5, R6, R8 | **paper 22 PRIMARY DV source**; country-specific party codes retained, NO binary collapse. "Would not vote/other" kept as substantive |
| party_close_which | R3, R5, R6, R8 | nominal companion (party R feels close to); labels via afro_value_labels.csv |

⚠️ **Nominal codes need the label lookup.** For `vote_intent_party`,
`party_close_which`, `ethnic_group`, and `occupation`, the harmonize engine keeps
numeric codes only. `data/processed/afro_value_labels.csv` (6,739 rows; columns
`variable, wave, country, code, label`, rebuilt from the raw .sav in step 99) is
the crosswalk — join on **(variable, wave, country, code)**. Codes are NOT
comparable across rounds: e.g. Botswana code 141 = BCP in R3 but BDP in R5.

Missing-code note: these four nominal vars use **per-variable** conventions that
strip only true DK/Refused/Not-asked/Missing and PRESERVE substantive codes
(e.g. ethnic code 7 = Afrikaner/Coloured, occupation code 7 = Miner/Artisan) —
codes the standard ordinal `treat_as_na` set would have deleted.

## Verbatim dictionary

`data/afro/questionnaire_text/afro_verbatim_items.csv` — Complete (73 vars, 9 rounds, 657 rows; text from R9 codebook + T&M extension items 2026-07-03 + paper 22 additions 2026-07-05).

## Notes & gotchas

- Missing-value conventions: codes -1, 8, 9, 98, 99, 998, 999 treated as NA.
- **Trust scale handling**: R1 raw 1-4 → `recode_afro_r1_trust`; R2-R9 raw 0-3 → `recode_0_3_to_1_4` (+1 shift).
- **dem_support_preferable coding differs**: R1 → `recode_afro_dem_pref_r1`; R2-R8 → `recode_afro_dem_pref_r2_r8`; R9 → identity.
- R1 dem_satisfaction excluded (5-point scale, incompatible with R2-R9 4-point).
- Country codes change meaning every round — use value labels, not numeric codes.
- Custom recode functions in `src/r/utils/recoding.R`: `recode_afro_r1_trust`, `recode_afro_dem_sat`, `recode_afro_dem_pref_r1`, `recode_afro_dem_pref_r2_r8`.
