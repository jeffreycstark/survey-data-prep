# survey-data-prep — Claude Navigation Guide

**Project**: Multi-Survey Harmonization Data Pipeline
**Surveys**: Asian Barometer Survey (ABS, Waves 1-6) + World Values Survey (WVS, Waves 6-7) + Russian survey (TBD)
**Status**: ABS pipeline complete (330 variables, 6 waves, 110,721 respondents); WVS pipeline planned

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
│   │   ├── 0_load_waves.R
│   │   ├── 2_harmonize_all.R
│   │   └── 99_create_final_dataset.R
│   │
│   └── models/                 # Statistical models
│
├── config/
│   ├── abs/                    # ABS-specific config
│   │   ├── harmonize/          # ABS YAML specs (27 files)
│   │   └── harmonize_validated/
│   └── wvs/                    # WVS-specific config (planned)
│       ├── harmonize/
│       └── harmonize_validated/
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
├── external/                   # External datasets (V-Dem, COVID, etc.)
├── interim/                    # Intermediate processing
└── processed/                  # Final harmonized datasets

outputs/
├── figures/
├── tables/
├── master_w*.rds               # Per-wave harmonized data
├── abs_econdev_authpref.rds    # Combined ABS dataset
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

### Running the Pipeline

```bash
Rscript src/r/data_prep_modules/0_load_waves.R
Rscript src/r/data_prep_modules/2_harmonize_all.R
Rscript src/r/data_prep_modules/99_create_final_dataset.R
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
d <- readRDS("data/processed/abs_econdev_authpref.rds")
# Or: arrow::read_parquet("data/processed/abs_econdev_authpref.parquet")
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

### Country Codes
1=Japan, 2=Hong Kong, 3=Korea, 4=China, 5=Mongolia, 6=Philippines, 7=Taiwan, 8=Thailand, 9=Indonesia, 10=Singapore, 11=Vietnam, 12=Cambodia, 13=Malaysia, 14=Myanmar, 15=Australia, 18=India

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

## Note on R
No R MCP is currently configured. R code is executed via `Rscript` in Bash.
