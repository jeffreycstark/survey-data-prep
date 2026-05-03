# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Project**: Multi-Survey Harmonization Data Pipeline
**Surveys**: Asian Barometer Survey (ABS, Waves 1-6) + World Values Survey (WVS, Waves 1-7) + Latinobarómetro (LBS, 24 waves: 1995-2024) + Afrobarometer (Afro, Rounds 1-9) + Arab Barometer (AB, Waves 1-8) + KAMOS (Waves 1, 4) + Korea General Social Survey (KGSS, 17 years: 2003-2025) + KIPA Corruption Survey (20 years: 2004-2023) + V-Dem v15 (scaffold)
**Status**: ABS complete (330 vars, 6 waves, 113,945 respondents; W6 covers 12 countries — Japan, Singapore, Malaysia added 2026-05); WVS complete (62 vars, 7 waves, 446,767 respondents, 108 countries); LBS complete (19 vars, 24 waves, 489,771 respondents); Afro complete (23 vars, 9 rounds, 351,815 respondents); KAMOS complete (39 vars, 2 waves, 3,500 respondents); KGSS complete (158 vars, 17 years 2003–2025, 23,282 respondents); KIPA Corruption (36 vars, 20 years 2004–2023, 18,000 respondents; NOT general-population — sample = corporate employees + self-employed with gov-business contact); V-Dem scaffolded (country-year panel, 202 countries, 1789–2024). Arab Barometer verbatim dictionary complete; full harmonization in progress.

---

## Project Purpose

This repo houses reusable survey data harmonization infrastructure:
- YAML-driven variable specifications (separate spec sets per survey)
- Automated scale detection, reversal detection, and recoding
- Multi-wave data loading, harmonization, and validation
- Codebook search and analysis tools

Each survey (ABS, WVS, etc.) has its own data directory, YAML specs, and pipeline cycle.

It is **not** a paper repo. Papers that consume the harmonized data live in separate repositories.

---

## Project Structure

```
src/
├── r/
│   ├── codebook/               # Codebook YAML generation tools
│   │   ├── codebook_analysis.R
│   │   ├── codebook_workflow.R
│   │   ├── test_codebook.R
│   │   └── *.md                # Documentation
│   │
│   ├── harmonize/              # Harmonization engine (shared)
│   │   ├── harmonize.R
│   │   ├── validate_spec.R
│   │   └── report_harmonization.R
│   │
│   ├── survey/                 # Survey utilities
│   │   ├── codebook_tools.R
│   │   ├── harmonize_vars.R
│   │   └── load_data.R
│   │
│   ├── utils/                  # General utilities
│   │   ├── search.R            # extract_matches()
│   │   ├── recoding.R
│   │   └── validation.R
│   │
│   ├── data_prep_modules/      # Pipeline orchestration scripts
│   │   ├── 0_load_waves.R          # ABS wave loader
│   │   ├── 1_harmonize_funs.R      # Shared recoding helpers
│   │   ├── 2_harmonize_all.R       # ABS harmonization (shared functions)
│   │   ├── 99_create_final_dataset.R
│   │   └── {wvs,lbs,afro,arab-barometer,kamos,kgss,kipa-corruption,vdem}/
│   │       # Per-survey subdirs: 0_load_waves.R + 2_harmonize_all.R + 99_create_final_dataset.R
│   │
│   └── models/                 # Statistical models
│
├── config/
│   ├── abs/                    # Production ABS specs are in harmonize_validated/, not harmonize/
│   │   ├── harmonize/          # legacy / scratch
│   │   └── harmonize_validated/
│   └── {wvs,lbs,afro,arab-barometer,kamos,kgss,kipa,kipa-corruption}/harmonize/
│
├── python/                     # Python utilities
│   ├── ingest/
│   ├── export/
│   └── validation/
│
└── scripts/                    # Pipeline orchestration

data/
├── abs/                        # Asian Barometer Survey
│   └── raw/
│       ├── wave1/ ... wave6/   # ABS waves (SPSS .sav)
│       └── README.md
├── wvs/                        # World Values Survey
│   └── raw/
│       ├── wave1/ ... wave7/   # WVS waves (W1-W5: SPSS .sav, W6-W7: parquet)
├── lbs/                        # Latinobarómetro
│   └── raw/
│       ├── 1995/ ... 2024/     # LBS waves (SPSS .sav; 24 year-named dirs)
├── afro/                       # Afrobarometer
│   └── raw/
│       └── round1/ ... round8/, wave9/   # Afrobarometer R1-R9 (SPSS .sav)
├── kamos/                      # Korean Attitudes and Mobilization Opinion Survey
│   └── raw/
│       ├── wave1/              # KAMOS W1 2016 (SPSS .sav, n=2000)
│       └── wave4/              # KAMOS W4 2019 (SPSS .sav, n=1500)
├── kgss/                       # Korea General Social Survey
│   └── raw/
│       └── kor_data_CUM0074.sav  # Cumulative file (n=23,282, 3,491 cols, 2003-2025)
├── v-dem/                      # Varieties of Democracy
│   └── raw/
│       └── v15/                # V-Dem v15 (RDS, 27,913 rows × 4,607 cols)
├── external/                   # External datasets (V-Dem, COVID, etc.)
├── interim/                    # Intermediate processing
└── processed/                  # Final harmonized datasets

outputs/
├── figures/
├── tables/
├── master_w*.rds               # ABS per-wave harmonized data
├── {wvs,lbs,afro,kamos,kgss,kipa-corruption,arab-barometer}/master_*.rds
└── harmonization_validation_*  # Validation reports

# Final combined per-survey datasets live in data/processed/{survey}_harmonized.rds
```

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

**Current status:**

| Survey | Dictionary | Status |
|--------|-----------|--------|
| ABS | `data/abs/questionnaire_text/abs_verbatim_items.csv` | Complete |
| KIPA Corruption | `data/kipa-corruption/questionnaire_text/kipa_corruption_verbatim_items.csv` | Complete (36 vars, 20 years, 720 rows; English 2004-2008, Korean 2009-2023; corr_punishment_relative_strength absent 2018-2023 due to scale change) |
| KIPA/KSIS Social | `data/processed/kipa_question_dictionary.csv` | Complete (needs migration to standard format) |
| WVS | `data/wvs/questionnaire_text/wvs_verbatim_items.csv` | Complete (79 vars, 7 waves, 553 rows) |
| LBS | `data/lbs/questionnaire_text/lbs_verbatim_items.csv` | Complete (30 vars, 24 waves, 720 rows) |
| Afrobarometer | `data/afro/questionnaire_text/afro_verbatim_items.csv` | Complete (46 vars, 9 rounds, 414 rows; text from R9 codebook) |
| KAMOS | `data/kamos/questionnaire_text/kamos_verbatim_items.csv` | Complete (42 vars, 2 waves, 84 rows; Korean+English) |
| Arab Barometer | `data/arab-barometer/questionnaire_text/arab_barometer_verbatim_items.csv` | Complete (44 vars, 6 waves, 264 rows; W1 PDF + SPSS labels) |
| KGSS | `data/kgss/questionnaire_text/kgss_verbatim_items.csv` | Complete (68 vars, 1,108 rows; covers 17 years/2003–2025; includes social_conflict (4), srhealth (1), family_gender (6) added 2026-04) |

**Appendix A workflow:** Papers in paper-bank consume these dictionaries via the `appendix-variable-builder` skill (`scripts/appendix-variable-builder-SKILL.md`). The skill filters to variables used in a given paper and generates formatted Appendix A prose. This repo owns the ground truth; paper repos only format and present.

### Running the Pipelines

**ABS** (6 waves, SPSS → RDS → harmonize):
```bash
Rscript src/r/data_prep_modules/0_load_waves.R
Rscript src/r/data_prep_modules/2_harmonize_all.R
Rscript src/r/data_prep_modules/99_create_final_dataset.R
```

**WVS** (7 waves, W1-W5 SPSS + W6-W7 parquet → harmonize):
```bash
Rscript src/r/data_prep_modules/wvs/2_harmonize_all.R
Rscript src/r/data_prep_modules/wvs/99_create_final_dataset.R
```

**LBS** (24 waves 1995–2024, SPSS → harmonize):
```bash
Rscript src/r/data_prep_modules/lbs/0_load_waves.R
Rscript src/r/data_prep_modules/lbs/2_harmonize_all.R
Rscript src/r/data_prep_modules/lbs/99_create_final_dataset.R
```

**Afrobarometer** (9 rounds R1–R9, SPSS → harmonize):
```bash
Rscript src/r/data_prep_modules/afro/0_load_waves.R
Rscript src/r/data_prep_modules/afro/2_harmonize_all.R
Rscript src/r/data_prep_modules/afro/99_create_final_dataset.R
```

**KAMOS** (2 waves, SPSS → harmonize):
```bash
Rscript src/r/data_prep_modules/kamos/0_load_waves.R
Rscript src/r/data_prep_modules/kamos/2_harmonize_all.R
Rscript src/r/data_prep_modules/kamos/99_create_final_dataset.R
```

**KGSS** (17 years 2003–2025, single cumulative SPSS → split by year → harmonize):
```bash
Rscript src/r/data_prep_modules/kgss/0_load_waves.R
Rscript src/r/data_prep_modules/kgss/2_harmonize_all.R
Rscript src/r/data_prep_modules/kgss/99_create_final_dataset.R
```

**KIPA Corruption** (20 years 2004–2023, annual SPSS per year + one cumulative split by year):
```bash
Rscript src/r/data_prep_modules/kipa-corruption/2_harmonize_all.R
Rscript src/r/data_prep_modules/kipa-corruption/99_create_final_dataset.R
```

**V-Dem** (country-year panel, scaffold):
```bash
Rscript src/r/data_prep_modules/vdem/99_create_final_dataset.R
```

---

## YAML Workflow

### Generate YAML for a New Concept
```r
source("src/r/codebook/codebook_workflow.R")
results <- extract_matches("search term", w1, w2, w3, w4, w5, w6)
yaml_str <- generate_codebook_yaml(results, concept = "concept_name")
cat(yaml_str)
writeLines(yaml_str, "src/config/abs/harmonize/concept_name.yml")  # or wvs/
```

### Batch Process Multiple Concepts
```r
source("src/r/codebook/codebook_workflow.R")
results_list <- list(
  economy = extract_matches("economic condition", w1, w2, w3, w4, w5, w6),
  politics = extract_matches("trust government", w1, w2, w3, w4, w5, w6)
)
batch_generate_yaml(results_list, output_dir = "src/config/abs/harmonize/")  # or wvs/
```

---

## Harmonized Dataset Reference

### Loading the Data
```r
d <- readRDS("data/processed/abs_harmonized.rds")
# Or: arrow::read_parquet("data/processed/abs_harmonized.parquet")
```

### Key Variable Categories
| Category | Examples |
|----------|----------|
| Demographics | country, age, gender, urban_rural, education_level |
| Political Action | action_demonstration, action_petition (1-5, higher=more active) |
| Trust | trust_president, trust_parliament, trust_police (1-4, higher=more trust) |
| Democracy | dem_sat_national, dem_best_form, dem_always_preferable |
| Economy | econ_national_now, econ_family_now (1-5, higher=better) |
| Social Media | sm_use_facebook, sm_use_twitter (1=Yes, 2=No, W6 only) |
| Weights | weight (mean ~1, W3-W6), weight_cross (W3-W4 only) | continuous |

### Country Codes
1=Japan, 2=Hong Kong, 3=Korea, 4=China, 5=Mongolia, 6=Philippines, 7=Taiwan, 8=Thailand, 9=Indonesia, 10=Singapore, 11=Vietnam, 12=Cambodia, 13=Malaysia, 14=Myanmar, 15=Australia, 18=India

### WVS Harmonized Dataset

```r
d <- readRDS("data/processed/wvs_harmonized.rds")
# Or: arrow::read_parquet("data/processed/wvs_harmonized.parquet")
```

**446,767 respondents, 108 countries, 62 harmonized variables across waves 1-7.**

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Trust (19) | trust_churches, trust_armed_forces, trust_press, trust_television, trust_labor_unions, trust_police, trust_courts, trust_government, trust_political_parties, trust_parliament, trust_civil_service, trust_universities, trust_elections (W7), trust_major_companies, trust_banks, trust_environmental_orgs, trust_womens_orgs, trust_charitable_orgs, trust_united_nations | 1-4, higher=more trust; W1-W7 (most items) |
| Social Trust (7) | trust_generalized_binary (1-2, W1-W7), trust_family, trust_neighborhood, trust_people_personally, trust_first_time, trust_another_religion, trust_another_nationality (W5-W7) | 1-4, higher=more trust |
| Democratic Attitudes (3) | dem_importance_democracy (W5-W7), dem_how_democratic (W5-W7), dem_satisfaction_political_system (W7) | 1-10, higher=more |
| Democratic Support (5) | dem_strong_leader (W3-W7), dem_experts_rule (W3-W7), dem_army_rule (W3-W7), dem_democratic_system (W3-W7), dem_religious_law (W7) | 1-4, higher=more support for that system |
| Life Satisfaction (2) | happiness (W1-W7), life_satisfaction (W1-W7) | 1-4 / 1-10, higher=better |
| Political Engagement (2) | pol_interest (W1-W7), pol_discuss_friends (W1-W4, W7) | 1-4 / 1-3, higher=more |
| Political Action (5) | action_petition (W1-W7), action_boycotts (W1-W7), action_demonstrations (W1-W7), action_strikes (W1-W4, W6), action_other_protest (W5-W6) | 1-3, higher=more active |
| Media Consumption (9) | info_newspaper, info_magazines (W6), info_television, info_radio, info_mobile_phone, info_email, info_internet, info_social_media (W7), info_talk_friends | 1-5, higher=more frequent; W6-W7 only (W1-W5 incompatible scales) |
| National Identity (1) | national_pride (W1-W7) | 1-4, higher=more proud |
| Demographics (7) | sex (W1-W7), age (W1-W7), education_level (W2-W7, 1-3 harmonized), income_scale (W1-W7, 1-10), social_class (W2-W7), marital_status (W1-W7), employment_status (W1-W7) | varies |
| Derived (1) | education_level_01 (0-1 rescaled from education_level) | 0-1 continuous |
| Weights (1) | weight | continuous, mean ~1; wave-specific raw sources |

Country identifier: `country` (3-letter ISO alpha codes, e.g. "USA", "CHN", "DEU")

### LBS Harmonized Dataset

```r
d <- readRDS("data/processed/lbs_harmonized.rds")
# Or: arrow::read_parquet("data/processed/lbs_harmonized.parquet")
```

**489,771 respondents, 19 Latin American countries, 19 harmonized variables across 24 waves (1995-2024).**

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Trust (9) | trust_churches, trust_armed_forces, trust_police, trust_courts, trust_government (19 waves), trust_political_parties, trust_parliament, trust_elections (10 waves), trust_president (13 waves) | 1-4, higher=more trust |
| Social Trust (1) | trust_generalized_binary | 1-2 |
| Democratic Attitudes (4) | dem_always_preferable (1-3), dem_satisfaction (1-4), dem_best_system (18 waves, 1-4), dem_how_democratic_10pt (13 waves, 1-10) | varies |
| Democratic Support (4) | dem_nondem_ok, dem_military_support, dem_solves_problems, pol_say_what_think | sparse (2-3 waves each) |
| Weights (1) | weight | continuous, mean ~1; raw: WT (all waves) |

Country identifier: `country` (3-letter ISO alpha codes, e.g. "ARG", "BRA", "MEX")
LBS waves use year-based keys: y1995, y1996, y1997, y1998, y2000, y2001, y2002, y2003, y2004, y2005, y2006, y2007, y2008, y2009, y2010, y2011, y2013, y2015, y2016, y2017, y2018, y2020, y2023, y2024

LBS missing value conventions: codes -5 through -1 treated as NA.
See `src/config/lbs/harmonize/LBS_VARIABLE_REVIEW.md` for WVS→LBS variable mappability assessment.

### Afrobarometer Harmonized Dataset

```r
d <- readRDS("data/processed/afro_harmonized.rds")
# Or: arrow::read_parquet("data/processed/afro_harmonized.parquet")
```

**351,815 respondents, 42 African countries, 23 harmonized variables across 9 rounds (R1-R9, 1999-2022).**

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

Country identifier: `country` (3-letter ISO alpha codes, derived from value labels per round)
Afro rounds: w1=R1(1999), w2=R2(2002), w3=R3(2005), w4=R4(2008), w5=R5(2012), w6=R6(2015), w7=R7(2017), w8=R8(2019), w9=R9(2022)
42 countries across all rounds (12 in R1, expanding to 39 in R9)

Afro missing value conventions: codes -1, 8, 9, 98, 99, 998, 999 treated as NA.
Trust scale handling: R1 raw 1-4 → `recode_afro_r1_trust`; R2-R9 raw 0-3 → `recode_0_3_to_1_4` (+1 shift).
dem_support_preferable coding differs: R1 → `recode_afro_dem_pref_r1`; R2-R8 → `recode_afro_dem_pref_r2_r8`; R9 → identity.

### KAMOS Harmonized Dataset

```r
d <- readRDS("data/processed/kamos_harmonized.rds")
# Or: arrow::read_parquet("data/processed/kamos_harmonized.parquet")
```

**3,500 respondents, South Korea only (KOR), 39 harmonized variables across 2 waves (W1=2016, W4=2019).**

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Trust (8) | trust_central_govt, trust_local_govt, trust_national_assembly, trust_judiciary, trust_private_enterprise, trust_media, trust_ngo, trust_religious | 0-10, higher=more trust |
| Social Trust (2) | trust_society, trust_citizens | 0-10, higher=more trust |
| Demographics (9) | gender, age, birth_year, education (1-8), income (1-11), marital_status, employment (nominal), region (1-17 nominal), subjective_class (0-10) | varies |
| Political Attitudes (6) | ideology (1=far left–5=far right), pol_satisfaction (1=satisfied–4=unsatisfied), pol_system_pref (1-5 categorical), party_id (nominal), party_id_lean (nominal), party thermometers W1 only: party_att_saenuri, party_att_minjoo, party_att_peoples, party_att_justice (0-10) | varies |
| Economy & Society (8) | econ_national, econ_family, social_mobility, social_mobility_next_gen (1-4), econ_equality (0-10), social_conflict_severity (1-4), national_pride (1-4), news_interest (1-4) | varies |
| Vote (3) | voted_presidential, voted_general, voted_local | binary (1=voted, NA=did not) |
| Weights (1) | weight | continuous; W1=wt2 (trimmed post-strat, mean≈1, range 0.72–1.81); W4=1.0 (no weight in raw data) |

Country identifier: `country` = "KOR" (all rows)
KAMOS waves: w1=2016, w4=2019 (waves 2 and 3 not available)

**Important notes:**
- Trust scale is **0–10** (not 1–4 like ABS/LBS/WVS) — do not compare directly without rescaling
- `party_id` and `party_id_lean` are **nominal and wave-incompatible** (Saenuri Party renamed/dissolved between waves; landscape differs)
- `pol_satisfaction` direction: 1=very satisfied, 4=very unsatisfied (higher=worse)
- `econ_national`, `econ_family` direction: 1=very good, 4=poor (higher=worse)
- No interview date variable in either wave; year assigned statically

KAMOS missing value conventions: 98 and 99 treated as NA for age; other variables per-spec.
Gender coding corrected via `recode_kamos_gender_w1()` (W1 had 1=female,2=male; standardized to 1=male,2=female).

### KGSS Harmonized Dataset

```r
d <- readRDS("data/processed/kgss_harmonized.rds")
# Or: arrow::read_parquet("data/processed/kgss_harmonized.parquet")
```

**23,282 respondents, South Korea only (KOR), 158 harmonized variables across 17 survey years (2003–2025; no 2015, 2017, 2019–2020, 2022, 2024). `pol_govt_eval` (CURGOV) dropped in 2025.**

⚠️ **Scale warning**: `conf_*` variables are **1–3** (not 1–4 like ABS/WVS/LBS trust vars); do not compare without rescaling.

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Confidence (20) | conf_business, conf_legislature, conf_judiciary, conf_science, conf_military, conf_finance, conf_bluehouse, conf_civil_society, conf_clergy, conf_education, conf_labor, conf_press, conf_television, conf_medicine, conf_govt_national, conf_govt_local, conf_research, conf_prosecutors, conf_statistics, conf_election_commission | 1–3, higher=more confidence |
| Social Trust (3) | trust_fair (1–3), trust_generalized (1–4), trust_reliable (0–10) | varies; higher=more trust |
| Political Attitudes (9) | pol_govt_eval, pol_econ_sat (1–5 higher=worse), pol_ideology (1–5 liberal–conservative), pol_national_pride (1–4 higher=less proud), pol_econ_prospect, pol_pol_prospect (1–5 higher=worse), pol_northkorea_view, pol_nk_defectors, pol_unification | varies |
| Political Behavior / Partisanship (9) | party_id, party_pref (nominal year-specific codes — NOT comparable across waves), voted_presidential, voted_general, voted_local (1=voted, 2=did not), pol_satisfaction, econ_hh_satisfaction, econ_hh_outlook, pol_outlook (all 1–5 reversed, higher=better) | varies |
| Civic Attitudes — ISSP Citizenship (20) | cit_virtue_paytaxes, cit_virtue_obeylaws, cit_virtue_watchgov, cit_virtue_helpkr, cit_right_solok, cit_right_minorities, cit_right_polopts, cit_right_oppsegov (1–7 higher=more important), pol_efficacy_internal, pol_efficacy_external (1–5 reversed, higher=more efficacy), dem_now, dem_10yrs_past, dem_10yrs_future (0–10 higher=more democratic), action_petition, action_boycott, action_demonstration, action_rally, action_contact_gov (1–4 reversed, higher=more active), admin_service (1–4 reversed, higher=better), admin_corruption (1–5 higher=more corrupt) | varies |
| Role of Government (18) | gov_resp_jobs, gov_resp_prices, gov_resp_healthcare, gov_resp_elderly, gov_resp_industry, gov_resp_unemploy, gov_resp_incomegap, gov_resp_students, gov_resp_housing, gov_resp_environment (1–4 reversed, higher=more state role; 2006/2016 only), gov_spend_environment, gov_spend_health, gov_spend_police, gov_spend_education, gov_spend_defense, gov_spend_pension, gov_spend_unemployment, gov_spend_culture (1–5 reversed, higher=spend more; 7 waves 2006/2014/2016/2018/2021/2023/2025) | varies |
| National Identity — ISSP (32) | **General pride (5, 2003/2013/2023)**: natid_korean_over_other, natid_shame, natid_world_like_kr, natid_kr_better_than_most, natid_right_or_wrong (1–5 reversed, higher=more agreement; `natid_shame` inversely valenced). **Domain pride (10, 2003/2013/2023/2025)**: pride_democracy, pride_pol_influence, pride_economy, pride_social_security, pride_science, pride_sports, pride_arts, pride_military, pride_history, pride_fairness (1–4 reversed, higher=more proud). **"True Korean" criteria (6, 2003/2010/2013/2023)**: truekr_born_here, truekr_citizenship, truekr_ancestors, truekr_feels_kr, truekr_respects_law, truekr_confucian (1–4 reversed, higher=more important). **International relations (6, 2003/2013/2021/2023)**: intl_limit_imports, intl_world_govt_env, intl_own_way, intl_no_foreign_land, intl_kr_tv, intl_foreign_co_harmful (1–5 reversed, higher=agree). **Immigration (5, 2003/2010/2013/2023)**: imm_crime, imm_help_econ, imm_take_jobs, imm_cultural_contrib (1–5 reversed, higher=agree), imm_limit_number (1–5 identity, higher=want fewer immigrants — scale direction differs from other imm_* items) | varies |
| Corruption / Bribery / 청탁 (12) | **Govt anti-corruption performance (3)**: corr_anticorrupt_policy (2003–2010), corr_tax_fairness_policy (2003–2010), corr_election_transparency (2004/2014) — all 1–5 reversed, higher=better govt performance. **Corruption perceptions (5)**: corr_politicians (2006/2014/2016), corr_officials (2006/2014/2016), corr_officials_bribe (2006/2016) — 1–5 identity, higher=MORE corruption; corr_cant_succeed_without (2009/2014), corr_bribe_success (2009/2014/2021/2023/2025, **5 waves**) — 1–5 reversed, higher=more cynical. **청탁 / patronage (4, all 2006 only)**: corr_receive_requests, corr_have_connections (1–4 identity); corr_officials_fair (1–5 reversed, higher=more fair), corr_officials_nepotism (1–4 reversed, higher=LESS nepotism). **⚠ Directions are mixed across this module — read each variable's note** | varies |
| Social Inequality — ISSP (6) | ineq_gap_too_large (4 waves: 2003/2009/2011/2014, 1–5 reversed, higher=more agrees gap too large), ineq_success_factor (3 waves: 2003/2014/2016, 1–3 categorical; NOT ordinal), ineq_fair_continuum (2 waves: 2011/2014, 1–10 higher=more meritocratic preference), ineq_perc_income, ineq_perc_jobs, ineq_perc_law (3 waves each: 2005/2009/2014, 1–5 higher=perceives more inequality) | varies; ISSP rotation |
| Social Conflict — ISSP (4) | conflict_richpoor, conflict_workingclass_middleclass, conflict_labor_management, conflict_top_bottom (3 waves each: 2003/2009/2014; raw CON{WLTH,CLASS,UNION,SOC}; reversed) | 1–4, higher=perceives more serious conflict |
| Family / Gender Roles — ISSP (6) | gender_breadwinner_norm (4 waves: 2003/2008/2012/2018, raw HUBBYWRK + HBBYWK08 combined), gender_workmom_family_suffers (3 waves: 2003/2012/2016, FAMSUFFR), gender_both_earn / gender_woman_homemaker_pref / gender_divorce_best_solution / gender_cohab_no_marriage_ok (2 waves each: 2003/2012; raw TWOINCS, HOMEKID, DIVBEST, COHABOK). All 5pt reversed; higher=stronger agreement with stated proposition. ⚠ 7-pt SEXROLE1/2/123 deferred — no safe_reverse_7pt helper yet. | 1–5, higher=stronger agreement |
| Health (1) | srhealth (11 waves: 2006/2007/2009/2010/2011/2012/2013/2016/2018/2023/2025; combines HEALTHY + HEALR + HEALTH23 — all symmetric 5pt; 2021 HEALTH21 EXCLUDED, asymmetric scale) | 1–5, higher=better self-rated health |
| Wellbeing (3) | wb_happiness (6 waves: 2009/2010/2016/2021/2023/2025, 1–5 reversed higher=happier), wb_life_satisfaction (6 waves: 2006/2009/2016/2021/2023/2025, 1–5 reversed higher=more satisfied), wb_financial_satisfaction (14 waves: 2003-2025 with gaps at 2007/2013/2014, 1–5 reversed higher=more satisfied) | 1–5, higher=better |
| Demographics (12) | age, sex, education, marital_status, employment, income, region, urban_rural, religion, religious_attendance, subjective_class_6pt (1–6 higher=lower class), subjective_rank_10pt (1–10 higher=higher class) | varies |
| Identifiers (3) | resp_id (within-year), yr_resp_id (cross-year unique, format YYYYnnnnn), questionnaire_form (1=A, 2=B; 2016+ only) | nominal |
| Weight (1) | weight | continuous, mean=1; raw: FINALWT (range ~0.29–5.29) |

Country identifier: `country` = "KOR" (all rows)
Wave column: `wave` = calendar year integer (2003, 2004, ..., 2025), **not** a sequential wave index.
KGSS missing value conventions: -8=DK, -1=IAP treated as NA; legacy 88/98/99 sentinels also treated as NA in newer specs.
conf_bluehouse = confidence in the Blue House (Korea's presidential executive office).
**No interview date variable** exists in the cumulative file; year is the only temporal identifier.

**⚠️ party_id / party_pref caveats**: These are NOMINAL raw codes that DIFFER per wave (Korean party system reshuffles regularly — e.g., Saenuri dissolved 2017, 조국혁신당 emerged 2024). Use within a single wave or construct per-wave camp mappings for longitudinal analysis.

**Widest-coverage variables by module**: `gov_spend_*` items (7 waves: 2006/2014/2016/2018/2021/2023/2025); `pol_satisfaction`, `econ_hh_satisfaction`, `econ_hh_outlook` (10+ waves each); `wb_financial_satisfaction` (14 waves: best wellbeing time series). Social inequality items are ISSP-rotation (3–4 waves) — sparse by design.

### KIPA Corruption Survey (공직부패의 실태에 관한 설문조사) — initial

```r
d <- readRDS("data/processed/kipa_corruption_harmonized.rds")
# Or: arrow::read_parquet("data/processed/kipa_corruption_harmonized.parquet")
```

**18,000 respondents, South Korea only (KOR), 36 harmonized variables across 20 survey years (2004–2023).** Conducted annually by 한국행정연구원 (KIPA) since 1999; KOSSDA holds 2004-2023. The 2004-2007 cumulative file is split by year internally (n=500 each). 2008-2023 are annual (n=1,000 each).

**⚠️ SAMPLE POPULATION**: This is **NOT a general-population survey**. Respondents are corporate employees (일반기업체 종사자) and self-employed workers (자영업자) who have business contact with government agencies, sampled via stratified proportional design. **Cannot be row-bound with KGSS/KAMOS/KIPA-social** — it's a different universe. Use it as a parallel specialty survey for corruption-specific analysis or to triangulate KGSS corruption perception items.

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

Data directory: `data/kipa-corruption/raw/unzipped/<handle>/`. Year-to-handle mapping lives in `src/r/data_prep_modules/kipa-corruption/0_load_waves.R`.

**Raw variable naming: two families across years**:
- "a-family" (`a01`, `a02`, `a03`, `a13`, …): used 2010–2021 + the 2004–2007 cumulative
- "q-family" (`q1`, `q2`, `q3`, `q9`, `q13`, …): used 2008, 2009, 2022, 2023

Semantic content is stable across the naming shift. In 2022–2023 the wording was slightly broadened to include 향응/편의 (entertainment/favors) alongside 금품 (money), reflecting the Kim Young-ran Act's expanded definition. The harmonization maps per-wave raw names to stable harmonized IDs.

**Substantive signal in the 4 vars**:
- `corr_bribery_experience_1yr` shows a dramatic drop after the Kim Young-ran Act (2016): from ~3–14% of respondents reporting having given a bribe in 2004–2015 to <1% in 2018–2020. Consistent with post-law reported behavior changes.
- `corr_prevalence_perception` declines ~3.6 (2009) → ~2.9 (2020–2023).
- `corr_change_vs_last_year` drops from above-midpoint (worse) to ~2.7 (better) after 2016.

### V-Dem Core Dataset (scaffold)

```r
d <- readRDS("data/processed/vdem_core.rds")
# Or: arrow::read_parquet("data/processed/vdem_core.parquet")
# Raw: data/v-dem/raw/v15/V-Dem-CY-Full+Others-v15.rds (4,607 cols — select what you need)
```

**27,913 country-years, 202 countries, 1789–2024. Unit: country × year (NOT individual respondents).**

| Variable | Description | Scale |
|----------|-------------|-------|
| `country_name` | Full country name | string |
| `country_text_id` | ISO 3-letter alpha code (e.g. "KOR", "THA") | string |
| `COWcode` | Correlates of War numeric code | integer |
| `year` | Calendar year | integer |
| `v2x_polyarchy` | Electoral Democracy Index | 0–1 |
| `v2x_libdem` | Liberal Democracy Index | 0–1 |
| `v2x_partipdem` | Participatory Democracy Index | 0–1 |
| `v2x_delibdem` | Deliberative Democracy Index | 0–1 |
| `v2x_egaldem` | Egalitarian Democracy Index | 0–1 |
| `v2x_corr` | Political Corruption Index (higher = more corrupt) | 0–1 |
| `v2x_accountability` | Accountability Index | 0–1 |
| `v2x_freespeech` | Freedom of Expression Index | 0–1 |
| `v2x_regime` | Regime type (0=closed autocracy … 3=liberal democracy) | 0–3 |

**Notes:**
- This is a scaffold — add indices from the 4,607-column raw file as papers require
- Full variable list and definitions: `data/v-dem/raw/v15/codebook.pdf`
- For paper-specific merges, join on `country_text_id` (ISO3) + `year`
- Contemporary coverage is most complete from ~1900 onward

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

For deeper codebook tooling docs, see `src/r/codebook/` (README, QUICK_REFERENCE, SKILL_SEARCH_AND_ANALYZE).

---

## Slope Prospector (Trend Anomaly Detection)

A systematic tool for identifying interesting trend patterns across harmonized survey data. Located at `src/scripts/slope_prospector.R`. This is a prospecting tool -- findings are puzzles, not conclusions.

### What It Does

Takes long-format country-wave means and produces 10 outputs:

| Output | Purpose |
|--------|---------|
| `outlier_slopes.csv` | Country-variable pairs with unusually steep slopes (\|z\| > threshold) |
| `structural_breaks.csv` | Stable-then-broke patterns (supF test, p < .05) |
| `divergent_pairs.csv` | Variable pairs moving in opposite directions within a country |
| `acceleration.csv` | Early vs. late period slope changes; direction reversals |
| `slope_groups.csv` | Concept group coherence scores (do related vars move together?) |
| `slope_divergence.csv` | Cross-group divergences (e.g., trust rising while efficacy falls) |
| `country_clusters.csv` | Country similarity clustering on full slope vectors |
| `narrative_patterns.csv` | Matches against named theoretical signatures |
| `heatmap_slopes.png` | Full country x variable z-score heatmap |
| `dashboard_*.png` | Per-country concept group trajectory plots |

### Running the Prospector

The prospector is configured via global variables set before `source()`:

```r
# Required: long-format CSV with columns: country, wave_num, variable, mean_value [, n]
INPUT_PATH          <- "path/to/means.csv"
OUTPUT_DIR          <- "outputs/prospecting/my_run"
CONCEPT_GROUPS_PATH <- "src/scripts/concept_groups.yml"  # or concept_groups_kamos.yml

# Optional tuning
MIN_WAVES           <- 3       # minimum waves to estimate a slope
Z_THRESHOLD         <- 2.0     # outlier z-score cutoff
USE_WEIGHTED_SLOPES <- TRUE    # use n column for WLS if available
DO_CLUSTERING       <- TRUE
DO_NARRATIVE        <- TRUE
DO_DASHBOARDS       <- TRUE

source("src/scripts/slope_prospector.R")
```

### Existing Runner Scripts

| Script | Scope | Output Directory |
|--------|-------|-----------------|
| `src/scripts/run_abs_all_countries.R` | All 16 ABS countries, 315 vars, 6 waves | `outputs/prospecting/abs_all/` |
| `src/scripts/run_korea_abs.R` | All ABS countries (Korea-focused) | `outputs/prospecting/korea_abs/` |

### Concept Group Files

| File | Survey | Groups |
|------|--------|--------|
| `src/scripts/concept_groups.yml` | ABS | 20 groups (trust, democracy, efficacy, economic, media, etc.) |
| `src/scripts/concept_groups_kamos.yml` | KAMOS | 11 groups (trust, economic, political, mobility, etc.) |

### Narrative Patterns Detected

The prospector matches countries against 8 named theoretical signatures:

| Pattern | What It Detects |
|---------|----------------|
| Output Legitimacy | Economic satisfaction rising + democratic quality flat/falling |
| Demobilization Sequence | Contacting/protest collapsing + authoritarian support rising |
| Democratic Aspiration Gap | Normative democratic preference stable + empirical assessment falling |
| Hollow Citizenship | Voting stable/rising + contacting and protest falling |
| Trust Collapse | Executive and intermediary institutions both losing trust |
| Selective Legitimation | Executive trust rising + courts/parties/media falling |
| Economic Pessimism Decoupling | Present economic conditions stable + outlook deteriorating |
| Corruption Normalization | Witnessed corruption flat while systemic perception stays high |

### Input Format

The prospector expects a CSV with columns:
- `country`: country name or code
- `wave_num`: numeric wave indicator
- `variable`: harmonized variable name
- `mean_value`: country-wave mean
- `n` (optional): respondent count for weighted least squares

Runner scripts (e.g., `run_abs_all_countries.R`) handle the pivot from wide harmonized RDS to this long format.

---

## Environment Setup

**R** (primary language): Managed via `renv`. Restore with `Rscript -e "renv::restore()"`. Key packages: tidyverse, haven (SPSS I/O), here, arrow (parquet I/O).

**Python** (minimal use): Managed via `uv`. Setup: `uv sync && source .venv/bin/activate`. Lint: `ruff check src/python/`.

No R MCP is currently configured. R code is executed via `Rscript` in Bash.

## Architecture Notes

**Adding a new survey**: Each survey follows the same 3-file pipeline pattern in `src/r/data_prep_modules/{survey}/`: `0_load_waves.R` → `2_harmonize_all.R` → `99_create_final_dataset.R`. YAML specs go in `src/config/{survey}/harmonize/`. The harmonization engine (`src/r/harmonize/harmonize.R`) is shared across all surveys.

**Shared recoding functions** in `src/r/data_prep_modules/1_harmonize_funs.R`: `safe_reverse_4pt()`, `safe_reverse_5pt()`, `recode_5pt_to_4pt()`, `recode_3pt_to_4pt()`. These are referenced by name in YAML spec `fn:` fields and sourced by each survey's `2_harmonize_all.R`.

**ABS uses validated specs**: Production ABS specs are in `src/config/abs/harmonize_validated/` (28 files), not `harmonize/`.
