# Afrobarometer (Afro)

**Status**: Complete through R9 (23 vars, 9 rounds R1–R9, 1999–2022, 351,815 respondents, 42 African countries). R10 in progress — pilot codebook (South Africa) on disk; merged .sav not yet released. Loader has a `w10` placeholder that auto-loads when the merged file lands at `data/afro/raw/round10/merged_r10_data.sav`.

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

## Verbatim dictionary

`data/afro/questionnaire_text/afro_verbatim_items.csv` — Complete (46 vars, 9 rounds, 414 rows; text from R9 codebook).

## Notes & gotchas

- Missing-value conventions: codes -1, 8, 9, 98, 99, 998, 999 treated as NA.
- **Trust scale handling**: R1 raw 1-4 → `recode_afro_r1_trust`; R2-R9 raw 0-3 → `recode_0_3_to_1_4` (+1 shift).
- **dem_support_preferable coding differs**: R1 → `recode_afro_dem_pref_r1`; R2-R8 → `recode_afro_dem_pref_r2_r8`; R9 → identity.
- R1 dem_satisfaction excluded (5-point scale, incompatible with R2-R9 4-point).
- Country codes change meaning every round — use value labels, not numeric codes.
- Custom recode functions in `src/r/utils/recoding.R`: `recode_afro_r1_trust`, `recode_afro_dem_sat`, `recode_afro_dem_pref_r1`, `recode_afro_dem_pref_r2_r8`.
