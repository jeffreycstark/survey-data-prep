# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Project**: Multi-Survey Harmonization Data Pipeline
**Surveys**: Asian Barometer Survey (ABS, Waves 1-6) + World Values Survey (WVS, Waves 6-7) + Latinobarómetro (LBS, 5 waves: 2015-2023) + Afrobarometer (Afro, Round 9)
**Status**: ABS complete (330 vars, 6 waves, 110,721 respondents); WVS complete (61 vars, 2 waves, 186,785 respondents); LBS complete (20 vars, 5 waves, ~100k respondents); Afro complete (20 vars, 1 wave, 53,444 respondents)

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
│   │   ├── wvs/                    # WVS pipeline
│   │   │   ├── 0_load_waves.R
│   │   │   ├── 2_harmonize_all.R
│   │   │   └── 99_create_final_dataset.R
│   │   ├── lbs/                    # LBS (Latinobarómetro) pipeline
│   │   │   ├── 0_load_waves.R
│   │   │   ├── 2_harmonize_all.R
│   │   │   └── 99_create_final_dataset.R
│   │   └── afro/                   # Afrobarometer pipeline
│   │       ├── 0_load_waves.R
│   │       ├── 2_harmonize_all.R
│   │       └── 99_create_final_dataset.R
│   │
│   └── models/                 # Statistical models
│
├── config/
│   ├── abs/                    # ABS-specific config
│   │   ├── harmonize/          # ABS YAML specs (27 files)
│   │   └── harmonize_validated/
│   ├── wvs/                    # WVS-specific config
│   │   └── harmonize/          # WVS YAML specs (11 files, 61 vars)
│   ├── lbs/                    # LBS-specific config
│   │   └── harmonize/          # LBS YAML specs (5 files, 20 vars)
│   └── afro/                   # Afrobarometer-specific config
│       └── harmonize/          # Afro YAML specs (5 files, 20 vars)
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
│       ├── wave6/, wave7/      # WVS waves (parquet)
├── lbs/                        # Latinobarómetro
│   └── raw/
│       ├── 2015/ ... 2023/     # LBS waves (SPSS .sav, English)
├── afro/                       # Afrobarometer
│   └── raw/
│       └── wave9/              # Afro Round 9 (SPSS .sav)
├── external/                   # External datasets (V-Dem, COVID, etc.)
├── interim/                    # Intermediate processing
└── processed/                  # Final harmonized datasets

outputs/
├── figures/
├── tables/
├── master_w*.rds               # ABS per-wave harmonized data
├── abs_harmonized.rds          # Combined ABS dataset
├── wvs/                        # WVS per-wave master files
│   └── master_w6.rds, master_w7.rds
├── lbs/                        # LBS per-wave master files
│   └── master_w1.rds ... master_w5.rds
├── afro/                       # Afro per-wave master files
│   └── master_w9.rds
└── harmonization_validation_*  # Validation reports
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
```

### Running the Pipelines

**ABS** (6 waves, SPSS → RDS → harmonize):
```bash
Rscript src/r/data_prep_modules/0_load_waves.R
Rscript src/r/data_prep_modules/2_harmonize_all.R
Rscript src/r/data_prep_modules/99_create_final_dataset.R
```

**WVS** (2 waves, parquet → harmonize):
```bash
Rscript src/r/data_prep_modules/wvs/2_harmonize_all.R
Rscript src/r/data_prep_modules/wvs/99_create_final_dataset.R
```

**LBS** (5 waves, SPSS → harmonize):
```bash
Rscript src/r/data_prep_modules/lbs/0_load_waves.R
Rscript src/r/data_prep_modules/lbs/2_harmonize_all.R
Rscript src/r/data_prep_modules/lbs/99_create_final_dataset.R
```

**Afrobarometer** (1 wave, SPSS → harmonize):
```bash
Rscript src/r/data_prep_modules/afro/0_load_waves.R
Rscript src/r/data_prep_modules/afro/2_harmonize_all.R
Rscript src/r/data_prep_modules/afro/99_create_final_dataset.R
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

**186,785 respondents, 84 countries, 61 harmonized variables across waves 6-7.**

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Trust (19) | trust_churches, trust_armed_forces, trust_press, trust_television, trust_labor_unions, trust_police, trust_courts, trust_government, trust_political_parties, trust_parliament, trust_civil_service, trust_universities, trust_elections (W7), trust_major_companies, trust_banks, trust_environmental_orgs, trust_womens_orgs, trust_charitable_orgs, trust_united_nations | 1-4, higher=more trust |
| Social Trust (7) | trust_generalized_binary (1-2), trust_family, trust_neighborhood, trust_people_personally, trust_first_time, trust_another_religion, trust_another_nationality | 1-4, higher=more trust |
| Democratic Attitudes (3) | dem_importance_democracy, dem_how_democratic, dem_satisfaction_political_system (W7) | 1-10, higher=more |
| Democratic Support (5) | dem_strong_leader, dem_experts_rule, dem_army_rule, dem_democratic_system, dem_religious_law (W7) | 1-4, higher=more support for that system |
| Life Satisfaction (2) | happiness, life_satisfaction | 1-4 / 1-10, higher=better |
| Political Engagement (2) | pol_interest, pol_discuss_friends (W7) | 1-4 / 1-3, higher=more |
| Political Action (5) | action_petition, action_boycotts, action_demonstrations, action_strikes, action_other_protest (W6) | 1-3, higher=more active |
| Media Consumption (9) | info_newspaper, info_magazines (W6), info_television, info_radio, info_mobile_phone, info_email, info_internet, info_social_media (W7), info_talk_friends | 1-5, higher=more frequent |
| National Identity (1) | national_pride | 1-4, higher=more proud |
| Demographics (7) | sex, age, education_level (1-3 harmonized), income_scale (1-10), social_class, marital_status, employment_status | varies |
| Weights (1) | weight | continuous, mean ~1; raw: V258 (W6), W_WEIGHT (W7) |

Country identifier: `country` (3-letter ISO alpha codes, e.g. "USA", "CHN", "DEU")

### LBS Harmonized Dataset

```r
d <- readRDS("data/processed/lbs_harmonized.rds")
# Or: arrow::read_parquet("data/processed/lbs_harmonized.parquet")
```

**~100,000 respondents, 18 Latin American countries, 20 harmonized variables across 5 waves (2015, 2016, 2018, 2020, 2023).**

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Trust (9) | trust_churches, trust_armed_forces, trust_police, trust_courts, trust_government, trust_political_parties, trust_parliament, trust_elections, trust_president | 1-4, higher=more trust |
| Social Trust (1) | trust_generalized_binary | 1-2 |
| Democratic Attitudes | dem_importance_democracy, dem_satisfaction, dem_how_democratic | varies (1-4 ordinal or 1-10) |
| Democratic Support | dem_strong_leader, dem_democratic_system, dem_army_rule, dem_always_preferable, dem_military_support | 1-4 or binary |
| Weights (1) | weight | continuous, mean ~1; raw: WT (all waves) |

Country identifier: `country` (3-letter ISO alpha codes, e.g. "ARG", "BRA", "MEX")
LBS waves mapped: w1=2015, w2=2016, w3=2018, w4=2020, w5=2023

LBS missing value conventions: codes -5 through -1 treated as NA.
See `src/config/lbs/harmonize/LBS_VARIABLE_REVIEW.md` for WVS→LBS variable mappability assessment.

### Afrobarometer Harmonized Dataset

```r
d <- readRDS("data/processed/afro_harmonized.rds")
# Or: arrow::read_parquet("data/processed/afro_harmonized.parquet")
```

**53,444 respondents, 39 African countries, 20 harmonized variables (12 populated, 8 NA placeholders), Round 9.**

| Category | Variables | Scale |
|----------|-----------|-------|
| Institutional Trust (8 of 9) | trust_president, trust_parliament, trust_elections, trust_police, trust_armed_forces, trust_courts, trust_churches, trust_political_parties | 1-4, higher=more trust |
| Institutional Trust (NA) | trust_government | NA (no equivalent) |
| Social Trust (NA) | trust_generalized_binary | NA (no equivalent) |
| Democratic Attitudes (3) | dem_support_preferable (1-3), dem_satisfaction (1-4), dem_how_democratic_qual (1-4) | varies |
| Democratic Attitudes (NA) | dem_how_democratic_10pt, dem_best_system | NA (no equivalent) |
| Democratic Support (NA) | dem_nondem_ok, dem_military_support, dem_solves_problems, pol_say_what_think | NA (scale mismatch or no equivalent) |
| Weights (1) | weight | continuous, mean ~1; raw: withinwt_hh |

Country identifier: `country` (3-letter ISO alpha codes)
Afro wave: w9 = Round 9 (2021-2023), year = 2022

Country codes (39 countries):
2=AGO, 3=BEN, 4=BWA, 5=BFA, 6=CPV, 7=CMR, 8=COG, 9=CIV, 10=SWZ, 11=ETH, 12=GAB, 13=GMB, 14=GHA, 15=GIN, 16=KEN, 17=LSO, 18=LBR, 19=MDG, 20=MWI, 21=MLI, 22=MRT, 23=MUS, 24=MAR, 25=MOZ, 26=NAM, 27=NER, 28=NGA, 29=STP, 30=SEN, 31=SYC, 32=SLE, 33=ZAF, 34=SDN, 35=TZA, 36=TGO, 37=TUN, 38=UGA, 39=ZMB, 40=ZWE

Afro missing value conventions: codes -1, 8, 9, 98, 99, 998, 999 treated as NA.
Trust variables use `recode_0_3_to_1_4()` (raw 0-3 scale shifted +1 to 1-4).

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

---

## Codebook Documentation

| Doc | Purpose |
|-----|---------|
| `src/r/codebook/QUICK_REFERENCE.md` | Fast lookup, cheat sheet |
| `src/r/codebook/SKILL_SEARCH_AND_ANALYZE.md` | Complete skill docs |
| `src/r/codebook/README.md` | Technical reference |
| `src/r/codebook/REAL_EXAMPLE_WALKTHROUGH.md` | Real data walkthrough |
| `src/r/codebook/BUILD_SUMMARY.md` | Build statistics |
| `src/r/codebook/INDEX.md` | Function index |

---

## Configuration

### Scale Detection
- Automatically identifies 5pt, 4pt, 6pt, 0-10, continuous scales
- Reversal detection via semantic keywords (bad/good, agree/disagree)
- All detections include 0-1 confidence scores

### Customization
- Confidence thresholds → YAML generation settings
- Keywords → `detect_label_direction()` in `codebook_analysis.R`
- Scale types → `detect_scale_type()` mapping logic

---

## Environment Setup

**R** (primary language): Managed via `renv`. Restore with `Rscript -e "renv::restore()"`. Key packages: tidyverse, haven (SPSS I/O), here, arrow (parquet I/O).

**Python** (minimal use): Managed via `uv`. Setup: `uv sync && source .venv/bin/activate`. Lint: `ruff check src/python/`.

No R MCP is currently configured. R code is executed via `Rscript` in Bash.

## Architecture Notes

**Adding a new survey**: Each survey follows the same 3-file pipeline pattern in `src/r/data_prep_modules/{survey}/`: `0_load_waves.R` → `2_harmonize_all.R` → `99_create_final_dataset.R`. YAML specs go in `src/config/{survey}/harmonize/`. The harmonization engine (`src/r/harmonize/harmonize.R`) is shared across all surveys.

**Shared recoding functions** in `src/r/data_prep_modules/1_harmonize_funs.R`: `safe_reverse_4pt()`, `safe_reverse_5pt()`, `recode_5pt_to_4pt()`, `recode_3pt_to_4pt()`. These are referenced by name in YAML spec `fn:` fields and sourced by each survey's `2_harmonize_all.R`.

**ABS uses validated specs**: Production ABS specs are in `src/config/abs/harmonize_validated/` (28 files), not `harmonize/`.
