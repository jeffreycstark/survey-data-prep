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
| Security Voting — paper 29 (3) | pres_approval (0/1), crime_victim (0/1), crime_fear (1-4, higher=more insecure) | 2015-2024 |
| Demographics (+1) | female (0/1) | 2015-2024 (extendable) |
| Weights (1) | weight | continuous, mean ~1; raw: WT (all waves) |

### Paper 29 "security voting" items (added 2026-07-07)

For paper-bank paper 29 (Veiga, Ribeiro & Borba 2022 — crime victimization / subjective
insecurity → presidential approval, with an incumbent-ideology moderator). Spec:
`src/config/lbs/harmonize/security_voting.yml` (+ `female` in `demographics.yml`). Q-codes
pinned per year against raw English `.sav` value labels 2026-07-07 (LBS renames variables
almost every year).

| Column | Recode | Per-year source |
|--------|--------|-----------------|
| `pres_approval` (DV) | 1=Approve→1, 2=Disapprove→0 | 2015 P48STGBS, 2016 P16STGBS, 2017 P17STGBSC, 2018 P20STGBSC, 2020 P17STGBS, 2023/2024 P15STGBS |
| `crime_victim` (IV) | {1,2,3}→1, 4→0 | 2015 P60ST, 2016 P37ST, **2017 P65ST.A+.B**, **2018 P69ST.1+.2** (split → any-victimization via `combine_lbs_victim_any`), 2020 P64ST, 2023 P58ST, **2024 P50ST.A (1=Yes/2=No)** |
| `crime_fear` (IV) | `safe_reverse_4pt` (higher=more insecure) | 2015 P57ST, 2016 P39ST, 2017 P66ST, 2018 P70ST, 2020 P65ST, 2023 P59ST, 2024 P51ST |
| `female` (control) | (sex==2)→1 | 2015 S12, 2016-2024 SEXO |

**Usable window = 2015, 2016, 2017, 2018, 2020, 2023, 2024** — all seven target years carry
approval + victimization + fear. `pres_approval` wording drifts across years
("government led by the President" vs. "the way the president is leading the country") but is the
same construct. `incumbent_ideology` (the extension moderator) is hand-coded in paper-bank, not here.

## Verbatim dictionary

`data/lbs/questionnaire_text/lbs_verbatim_items.csv` — Complete (34 vars, 24 waves, 816 rows;
+4 paper-29 items 2026-07-07).

## Notes & gotchas

- Missing-value conventions: codes -5 through -1 treated as NA.
- Variable names are HIGHLY UNSTABLE across waves (different prefixes every year). Variable mapping CSVs: `outputs/prospecting/lbs_variable_mapping*.csv`.
- 1995/1996 use `pais` instead of `IDENPA` for country codes.
- 2024 has Spanish labels only (no English translation available).
- Trust variables need `safe_reverse_4pt` (raw 1=A lot → 4=No trust).
- See `src/config/lbs/harmonize/LBS_VARIABLE_REVIEW.md` for WVS→LBS mappability assessment.
