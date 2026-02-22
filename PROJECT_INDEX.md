# Project Index: survey-data-prep

Generated: 2026-02-22

## 📁 Project Structure

```
survey-data-prep/
├── src/
│   ├── r/
│   │   ├── harmonize/          # Shared harmonization engine
│   │   ├── codebook/           # YAML generation tools
│   │   ├── survey/             # Survey utilities (load, codebook, missing)
│   │   ├── utils/              # Recoding, validation, search helpers
│   │   └── data_prep_modules/  # Per-survey pipeline scripts
│   │       ├── (ABS root)      # ABS: 0_load_waves, 2_harmonize_all, 99_create_final
│   │       ├── wvs/            # WVS pipeline
│   │       ├── lbs/            # Latinobarómetro pipeline
│   │       ├── afro/           # Afrobarometer pipeline
│   │       ├── kamos/          # KAMOS pipeline
│   │       └── vdem/           # V-Dem scaffold pipeline
│   ├── scripts/                # One-off scripts + slope_prospector.R
│   ├── config/
│   │   ├── abs/harmonize_validated/  # 28 production ABS YAML specs
│   │   ├── wvs/harmonize/            # 11 WVS YAML specs
│   │   ├── lbs/harmonize/            # 5 LBS YAML specs
│   │   ├── afro/harmonize/           # 5 Afro YAML specs
│   │   └── kamos/harmonize/          # 6 KAMOS YAML specs
│   └── python/                 # Minimal Python (ingest, export, validation stubs)
├── data/
│   ├── abs/raw/wave{1-6}/      # ABS SPSS .sav (gitignored)
│   ├── wvs/raw/wave{6,7}/      # WVS parquet (gitignored)
│   ├── lbs/raw/{2015-2023}/    # LBS SPSS .sav (gitignored)
│   ├── afro/raw/wave9/         # Afro SPSS .sav (gitignored)
│   ├── kamos/raw/wave{1,4}/    # KAMOS SPSS .sav (gitignored)
│   ├── v-dem/raw/v15/          # V-Dem RDS 4607 cols (gitignored)
│   ├── abs/labels/             # ABS wave label text files (W1–W6)
│   └── processed/              # Final harmonized datasets (gitignored, see below)
└── outputs/
    ├── prospecting/            # Slope prospector runs (CSVs/PNGs gitignored)
    │   ├── cambodia/           # Cambodia ABS analysis + paper memo
    │   ├── korea/              # Korea ABS analysis
    │   ├── taiwan_korea/       # Korea+Taiwan combined ABS analysis
    │   └── kamos/              # KAMOS analysis
    └── *.md                    # Harmonization validation reports
```

---

## 🚀 Pipeline Entry Points

### ABS (Asian Barometer Survey) — PRIMARY
```bash
Rscript src/r/data_prep_modules/0_load_waves.R        # SPSS → RDS per wave
Rscript src/r/data_prep_modules/2_harmonize_all.R     # Apply validated YAML specs
Rscript src/r/data_prep_modules/99_create_final_dataset.R  # → abs_harmonized.rds/.parquet
```

### WVS (World Values Survey)
```bash
Rscript src/r/data_prep_modules/wvs/2_harmonize_all.R
Rscript src/r/data_prep_modules/wvs/99_create_final_dataset.R
```

### LBS (Latinobarómetro)
```bash
Rscript src/r/data_prep_modules/lbs/0_load_waves.R
Rscript src/r/data_prep_modules/lbs/2_harmonize_all.R
Rscript src/r/data_prep_modules/lbs/99_create_final_dataset.R
```

### Afrobarometer
```bash
Rscript src/r/data_prep_modules/afro/0_load_waves.R
Rscript src/r/data_prep_modules/afro/2_harmonize_all.R
Rscript src/r/data_prep_modules/afro/99_create_final_dataset.R
```

### KAMOS (Korean Attitudes & Mobilization Opinion Survey)
```bash
Rscript src/r/data_prep_modules/kamos/0_load_waves.R
Rscript src/r/data_prep_modules/kamos/2_harmonize_all.R
Rscript src/r/data_prep_modules/kamos/99_create_final_dataset.R
```

### Slope Prospector (ad hoc)
```r
INPUT_PATH  <- "outputs/prospecting/cambodia/cambodia_means.csv"
OUTPUT_DIR  <- "outputs/prospecting/cambodia"
CONCEPT_GROUPS_PATH <- "src/scripts/concept_groups.yml"
source("src/scripts/slope_prospector.R")
```

---

## 📦 Core Modules

### `src/r/harmonize/harmonize.R`
Shared harmonization engine. Applies YAML specs to survey data.
Key function: `harmonize_all(data, spec_dir, survey)` — reads all `.yml` files in spec_dir and applies recoding/renaming.

### `src/r/harmonize/validate_spec.R`
Validates YAML specs against actual data. Catches missing source columns, scale mismatches.

### `src/r/harmonize/report_harmonization.R`
Generates QC reports after harmonization runs.

### `src/r/codebook/codebook_workflow.R`
Search → YAML generation pipeline.
Key functions: `extract_matches()`, `generate_codebook_yaml()`, `batch_generate_yaml()`

### `src/r/codebook/codebook_analysis.R`
Scale detection and reversal detection.
Key functions: `detect_scale_type()`, `detect_reversals()`, `detect_label_direction()`

### `src/r/utils/recoding.R`
Shared recoding helpers used in YAML `fn:` fields.
Key functions: `safe_reverse_4pt()`, `safe_reverse_5pt()`, `recode_5pt_to_4pt()`,
`recode_3pt_to_4pt()`, `recode_0_3_to_1_4()`, `recode_kamos_gender_w1()`

### `src/r/utils/search.R`
Variable search across waves.
Key function: `extract_matches(term, w1, w2, ...)`

### `src/scripts/slope_prospector.R`
Longitudinal trend detection tool. Takes long-format country-wave-variable means, outputs:
- OLS slopes (normalized 0–1) per country-variable
- Outlier detection (|z| > threshold)
- Structural break tests (strucchange)
- Acceleration/reversal detection
- Concept group coherence (via `concept_groups.yml`)
- Cross-group divergence table
- Heatmap PNG

**Config vars** (set before `source()`):
- `INPUT_PATH` — long CSV with cols: country, wave_num, variable, mean_value
- `OUTPUT_DIR` — output directory
- `CONCEPT_GROUPS_PATH` — path to concept groups YAML
- `EXCLUDE_VARS` — nominal/admin variables to drop
- `EXCLUDE_FROM_CROSS_GROUP` — groups omitted from cross-group pairing
- `MIN_WAVES` (default 3) — minimum waves to estimate slope
- `Z_THRESHOLD` (default 2.0) — outlier z-score cutoff

---

## 📊 Processed Datasets

| File | Survey | N rows | Variables | Notes |
|------|--------|--------|-----------|-------|
| `data/processed/abs_harmonized.rds/.parquet` | ABS W1–W6 | 110,721 | ~330 | 16 countries |
| `data/processed/wvs_harmonized.rds/.parquet` | WVS W6–7 | 186,785 | 61 | 84 countries |
| `data/processed/lbs_harmonized.rds/.parquet` | LBS 2015–2023 | ~100,000 | 20 | 18 LatAm countries |
| `data/processed/afro_harmonized.rds/.parquet` | Afro R9 | 53,444 | 20 | 39 African countries |
| `data/processed/kamos_harmonized.rds/.parquet` | KAMOS W1,4 | 3,500 | 39 | Korea only |
| `data/processed/vdem_core.rds/.parquet` | V-Dem v15 | 27,913 | 13 core | Country-year, 1789–2024 |
| `data/processed/taiwan_korea_harmonized.rds/.parquet` | ABS subset | 16,645 | 344 | Countries 3+7, all waves |

**ABS country codes**: 1=Japan, 2=HK, 3=Korea, 4=China, 5=Mongolia, 6=Philippines,
7=Taiwan, 8=Thailand, 9=Indonesia, 10=Singapore, 11=Vietnam, 12=Cambodia,
13=Malaysia, 14=Myanmar, 15=Australia, 18=India

---

## 🔧 Configuration

### YAML Spec Format (`src/config/{survey}/harmonize_validated/*.yml`)
```yaml
variables:
  - id: trust_president         # harmonized variable name
    description: "..."
    source:
      w1: q47a                  # raw variable name per wave (null = not asked)
      w2: q45a
    scale: {min: 1, max: 4}
    harmonize:
      default: {method: direct} # or: reverse_4pt, recode, fn
      exceptions:
        w3: {method: recode, mapping: {1: 4, 2: 3, 3: 2, 4: 1}}
```

### Concept Groups (`src/scripts/concept_groups.yml`)
Maps harmonized variable names → thematic groups for prospector analysis.
Survey-specific: `concept_groups_kamos.yml` for KAMOS.

---

## 📚 Key Documentation

| Doc | Purpose |
|-----|---------|
| `CLAUDE.md` | Full project reference (datasets, variables, pipelines) |
| `src/r/codebook/QUICK_REFERENCE.md` | Codebook workflow cheat sheet |
| `src/r/harmonize/README.md` | Harmonization engine docs |
| `src/config/abs/harmonize/YAML_SPECIFICATION_v2.md` | YAML spec format reference |
| `src/config/lbs/harmonize/LBS_VARIABLE_REVIEW.md` | LBS→WVS mappability |
| `outputs/prospecting/cambodia/cambodia_paper_memo.md` | Cambodia paper prospecting |

---

## 🔗 Key Dependencies (R)

| Package | Purpose |
|---------|---------|
| `tidyverse` | Data manipulation throughout |
| `haven` | SPSS .sav file I/O |
| `arrow` | Parquet I/O |
| `yaml` | YAML spec parsing |
| `strucchange` | Structural break tests in prospector |
| `broom` | Tidy model outputs |
| `patchwork` | Plot composition |

Managed via `renv`. Restore: `Rscript -e "renv::restore()"`

---

## 📝 Quick Start: Adding a New Survey

1. Create `src/r/data_prep_modules/{survey}/0_load_waves.R` — load SPSS/parquet → RDS
2. Create `src/config/{survey}/harmonize/*.yml` — variable specs
3. Create `src/r/data_prep_modules/{survey}/2_harmonize_all.R` — source harmonize engine
4. Create `src/r/data_prep_modules/{survey}/99_create_final_dataset.R` — combine → processed/
5. Run pipeline, validate with `src/r/harmonize/validate_spec.R`

## 📝 Quick Start: Running the Slope Prospector on a New Country

```r
library(tidyverse)
d <- readRDS("data/processed/abs_harmonized.rds") %>% filter(country == 12)  # Cambodia=12
long <- d %>%
  select(wave, where(is.numeric), -country, -weight, -weight_cross) %>%
  pivot_longer(-wave, names_to="variable", values_to="value") %>%
  group_by(wave, variable) %>%
  summarise(mean_value = mean(value, na.rm=TRUE), n = sum(!is.na(value)), .groups="drop") %>%
  filter(n >= 30) %>%
  mutate(country = "Cambodia", wave_num = as.integer(wave)) %>%
  select(country, wave_num, variable, mean_value)
write_csv(long, "outputs/prospecting/cambodia/cambodia_means.csv")

INPUT_PATH <- "outputs/prospecting/cambodia/cambodia_means.csv"
OUTPUT_DIR <- "outputs/prospecting/cambodia"
CONCEPT_GROUPS_PATH <- "src/scripts/concept_groups.yml"
source("src/scripts/slope_prospector.R")
```
