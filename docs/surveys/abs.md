# Asian Barometer Survey (ABS)

**Status**: Complete (330 vars, 6 waves, 113,945 respondents). W6 covers 12 countries — Japan, Singapore, Malaysia added 2026-05.

## Pipeline

```bash
Rscript src/r/data_prep_modules/0_load_waves.R
Rscript src/r/data_prep_modules/2_harmonize_all.R
Rscript src/r/data_prep_modules/99_create_final_dataset.R
```

ABS uses **validated specs**: production specs are in `src/config/abs/harmonize_validated/` (28 files), not `src/config/abs/harmonize/`.

## Loading

```r
d <- readRDS("data/processed/abs_harmonized.rds")
# Or: arrow::read_parquet("data/processed/abs_harmonized.parquet")
```

Per-wave files: `outputs/master_w{1..6}.rds`.

## Key Variable Categories

| Category | Examples |
|----------|----------|
| Demographics | country, age, gender, urban_rural, education_level |
| Political Action | action_demonstration, action_petition (1-5, higher=more active) |
| Trust | trust_president, trust_parliament, trust_police (1-4, higher=more trust) |
| Democracy | dem_sat_national, dem_best_form, dem_always_preferable |
| Economy | econ_national_now, econ_family_now (1-5, higher=better) |
| Social Media | sm_use_facebook, sm_use_twitter (1=Yes, 2=No, W6 only) |
| Weights | weight (mean ~1, W3-W6), weight_cross (W3-W4 only) — continuous |

## Country Codes

1=Japan, 2=Hong Kong, 3=Korea, 4=China, 5=Mongolia, 6=Philippines, 7=Taiwan, 8=Thailand, 9=Indonesia, 10=Singapore, 11=Vietnam, 12=Cambodia, 13=Malaysia, 14=Myanmar, 15=Australia, 18=India.

## Verbatim dictionary

`data/abs/questionnaire_text/abs_verbatim_items.csv` — Complete.

## Scale-direction notes

- `democracy_satisfaction`: W2 raw 1=Not at all → 4=Very; W3–W6 raw 1=Very → 4=Not at all (REVERSED in harmonization to standard direction)
- `dem_best_form`: raw 1=Strongly agree → 4=Strongly disagree; REVERSED so 4=pro-democracy
- `dem_vs_equality`: raw "both equally" at position 5; REMAPPED to center (3)
- `dem_always_preferable`: W2 response order differs; remapped to W3 standard
