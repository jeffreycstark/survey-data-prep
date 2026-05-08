# KAMOS (Korean Attitudes and Mobilization Opinion Survey)

**Status**: Complete (39 vars, 2 waves W1=2016, W4=2019, 3,500 respondents, South Korea only).

## Pipeline

```bash
Rscript src/r/data_prep_modules/kamos/0_load_waves.R
Rscript src/r/data_prep_modules/kamos/2_harmonize_all.R
Rscript src/r/data_prep_modules/kamos/99_create_final_dataset.R
```

Raw waves: `data/kamos/raw/wave1/` (n=2,000) and `data/kamos/raw/wave4/` (n=1,500). Waves 2 and 3 are not available.

## Loading

```r
d <- readRDS("data/processed/kamos_harmonized.rds")
# Or: arrow::read_parquet("data/processed/kamos_harmonized.parquet")
```

Country identifier: `country` = "KOR" (all rows).
Wave keys: w1=2016, w4=2019.

## Variable categories

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Trust (8) | trust_central_govt, trust_local_govt, trust_national_assembly, trust_judiciary, trust_private_enterprise, trust_media, trust_ngo, trust_religious | 0-10, higher=more trust |
| Social Trust (2) | trust_society, trust_citizens | 0-10, higher=more trust |
| Demographics (9) | gender, age, birth_year, education (1-8), income (1-11), marital_status, employment (nominal), region (1-17 nominal), subjective_class (0-10) | varies |
| Political Attitudes (6) | ideology (1=far left–5=far right), pol_satisfaction (1=satisfied–4=unsatisfied), pol_system_pref (1-5 categorical), party_id (nominal), party_id_lean (nominal), party thermometers W1 only: party_att_saenuri, party_att_minjoo, party_att_peoples, party_att_justice (0-10) | varies |
| Economy & Society (8) | econ_national, econ_family, social_mobility, social_mobility_next_gen (1-4), econ_equality (0-10), social_conflict_severity (1-4), national_pride (1-4), news_interest (1-4) | varies |
| Vote (3) | voted_presidential, voted_general, voted_local | binary (1=voted, NA=did not) |
| Weights (1) | weight | continuous; W1=wt2 (trimmed post-strat, mean≈1, range 0.72–1.81); W4=1.0 (no weight in raw data) |

## Verbatim dictionary

`data/kamos/questionnaire_text/kamos_verbatim_items.csv` — Complete (42 vars, 2 waves, 84 rows; Korean+English).

## Notes & gotchas

- ⚠️ **Trust scale is 0–10** (not 1–4 like ABS/LBS/WVS) — do not compare directly without rescaling.
- ⚠️ `party_id` and `party_id_lean` are **nominal and wave-incompatible** (Saenuri Party renamed/dissolved between waves; landscape differs).
- `pol_satisfaction` direction: 1=very satisfied, 4=very unsatisfied (higher=worse).
- `econ_national`, `econ_family` direction: 1=very good, 4=poor (higher=worse).
- No interview date variable in either wave; year assigned statically.
- Missing-value conventions: 98 and 99 treated as NA for age; other variables per-spec.
- Gender coding corrected via `recode_kamos_gender_w1()` (W1 had 1=female,2=male; standardized to 1=male,2=female).
