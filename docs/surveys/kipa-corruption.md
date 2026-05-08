# KIPA Corruption Survey (공직부패의 실태에 관한 설문조사)

**Status**: Initial (36 vars, 20 years 2004–2023, 18,000 respondents, South Korea only).

Conducted annually by 한국행정연구원 (KIPA) since 1999; KOSSDA holds 2004–2023. The 2004–2007 cumulative file is split by year internally (n=500 each); 2008–2023 are annual (n=1,000 each).

## ⚠️ SAMPLE POPULATION

This is **NOT a general-population survey**. Respondents are corporate employees (일반기업체 종사자) and self-employed workers (자영업자) who have business contact with government agencies, sampled via stratified proportional design. **Cannot be row-bound with KGSS / KAMOS / KIPA-social** — different universe. Use as a parallel specialty survey for corruption-specific analysis or to triangulate KGSS corruption perception items.

## Pipeline

```bash
Rscript src/r/data_prep_modules/kipa-corruption/2_harmonize_all.R
Rscript src/r/data_prep_modules/kipa-corruption/99_create_final_dataset.R
```

Data directory: `data/kipa-corruption/raw/unzipped/<handle>/`. Year-to-handle mapping lives in `src/r/data_prep_modules/kipa-corruption/0_load_waves.R`.

## Loading

```r
d <- readRDS("data/processed/kipa_corruption_harmonized.rds")
# Or: arrow::read_parquet("data/processed/kipa_corruption_harmonized.parquet")
```

## Variable categories

| Category | Variables | Scale |
|----------|-----------|-------|
| Corruption perception (3) | corr_prevalence_perception (money/favor-giving to officials perceived as common), corr_seriousness_perception (corruption as social problem), corr_change_vs_last_year (direction of change, ~3.5 midpoint = same) | 1–6, higher=more corruption/worse |
| Corruption experience (1) | corr_bribery_experience_1yr (personally gave money/favors to officials in past year) | 1=yes, 2=no; NOT available in 2022-2023 (question restructured) |
| Sector corruption — public/private (2) | corr_sector_public, corr_sector_private | 1–6, higher=more corrupt |
| Sector corruption — admin functions (11) | corr_func_tax, corr_func_police, corr_func_fire, corr_func_legal (⚠ scope narrows 2022+: 법조 → 검찰), corr_func_environment, corr_func_health, corr_func_food_safety, corr_func_construction, corr_func_procurement, corr_func_education, corr_func_welfare, corr_func_customs | 1–6, higher=more corrupt; 18 of 20 years (2008-2009 use q7_* structure not mapped) |
| Sector corruption — admin agencies (3) | corr_agency_central_hq, corr_agency_central_branch, corr_agency_local_frontline | 1–6, higher=more corrupt; 18 of 20 years |
| Demographics (4) | sex (1=M, 2=F), age_cat (1–5 categorical), education (categorical), income (categorical, ~1–10; boundaries vary by wave due to inflation) | varies |
| Anti-corruption policy — govt effectiveness (1) | corr_govt_policy_effectiveness | 1–6, higher=more effective; 5 years (2014-2016, 2020-2023) |
| Anti-corruption policy — punishment (3) | corr_punishment_bribe_giver (13 yrs, 2011-2023), corr_punishment_corrupt_official (10 yrs, 2014-2023), corr_punishment_relative_strength (7 yrs, 2011-2017 only — ⚠ scale restructured to 7-pt in 2018, incompatible with 2011-2017 6-pt series) | 1–6 |
| Anti-corruption policy — surveillance (7) | corr_surveil_party, corr_surveil_assembly, corr_surveil_civsoc, corr_surveil_media, corr_surveil_judiciary (⚠ 2018-2020 splits judiciary from prosecutors; we keep judiciary-only post-split), corr_surveil_internal_audit, corr_surveil_boa | 1–6, higher=functions better as corruption check; 13 years (2011-2023) |

## Verbatim dictionary

`data/kipa-corruption/questionnaire_text/kipa_corruption_verbatim_items.csv` — Complete (36 vars, 20 years, 720 rows; English 2004-2008, Korean 2009-2023; corr_punishment_relative_strength absent 2018-2023 due to scale change).

## Raw variable naming: two families across years

- **"a-family"** (`a01`, `a02`, `a03`, `a13`, …): used 2010–2021 + the 2004–2007 cumulative
- **"q-family"** (`q1`, `q2`, `q3`, `q9`, `q13`, …): used 2008, 2009, 2022, 2023

Semantic content is stable across the naming shift. In 2022–2023 the wording was slightly broadened to include 향응/편의 (entertainment/favors) alongside 금품 (money), reflecting the Kim Young-ran Act's expanded definition. The harmonization maps per-wave raw names to stable harmonized IDs.

## Substantive signal in the 4 vars

- `corr_bribery_experience_1yr` shows a dramatic drop after the Kim Young-ran Act (2016): from ~3–14% of respondents reporting having given a bribe in 2004–2015 to <1% in 2018–2020. Consistent with post-law reported behavior changes.
- `corr_prevalence_perception` declines ~3.6 (2009) → ~2.9 (2020–2023).
- `corr_change_vs_last_year` drops from above-midpoint (worse) to ~2.7 (better) after 2016.

## Errata

The English SPSS labels mistranslate 사법부 (judiciary) as "legislature". Korean-label matching is the correct path; document in any paper using these data.
