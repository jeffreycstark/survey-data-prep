# Latinobarómetro (LBS)

**Status**: Complete (19 vars, 24 waves 1995–2024, 489,771 respondents, 19 Latin American countries).

## Pipeline

```bash
Rscript src/r/data_prep_modules/lbs/0_load_waves.R
Rscript src/r/data_prep_modules/lbs/2_harmonize_all.R
Rscript src/r/data_prep_modules/lbs/99_create_final_dataset.R
```

Raw waves live in `data/lbs/raw/{1995..2024}/` (24 year-named dirs, SPSS `.sav`).

## Loading

```r
d <- readRDS("data/processed/lbs_harmonized.rds")
# Or: arrow::read_parquet("data/processed/lbs_harmonized.parquet")
```

Country identifier: `country` (3-letter ISO alpha codes, e.g. "ARG", "BRA", "MEX").

Wave keys (year-based): y1995, y1996, y1997, y1998, y2000, y2001, y2002, y2003, y2004, y2005, y2006, y2007, y2008, y2009, y2010, y2011, y2013, y2015, y2016, y2017, y2018, y2020, y2023, y2024.

## Variable categories

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Trust (9) | trust_churches, trust_armed_forces, trust_police, trust_courts, trust_government (19 waves), trust_political_parties, trust_parliament, trust_elections (10 waves), trust_president (13 waves) | 1-4, higher=more trust |
| Social Trust (1) | trust_generalized_binary | 1-2 |
| Democratic Attitudes (4) | dem_always_preferable (1-3), dem_satisfaction (1-4), dem_best_system (18 waves, 1-4), dem_how_democratic_10pt (13 waves, 1-10) | varies |
| Democratic Support (4) | dem_nondem_ok, dem_military_support, dem_solves_problems, pol_say_what_think | sparse (2-3 waves each) |
| Weights (1) | weight | continuous, mean ~1; raw: WT (all waves) |

## Verbatim dictionary

`data/lbs/questionnaire_text/lbs_verbatim_items.csv` — Complete (30 vars, 24 waves, 720 rows).

## Notes & gotchas

- Missing-value conventions: codes -5 through -1 treated as NA.
- Variable names are HIGHLY UNSTABLE across waves (different prefixes every year). Variable mapping CSVs: `outputs/prospecting/lbs_variable_mapping*.csv`.
- 1995/1996 use `pais` instead of `IDENPA` for country codes.
- 2024 has Spanish labels only (no English translation available).
- Trust variables need `safe_reverse_4pt` (raw 1=A lot → 4=No trust).
- See `src/config/lbs/harmonize/LBS_VARIABLE_REVIEW.md` for WVS→LBS mappability assessment.
