# survey-data-prep

Multi-survey harmonization data pipeline for cross-national survey research.

## Surveys

- **Asian Barometer Survey (ABS)**: Waves 1-6, 16 countries, 110,721 respondents, 330 harmonized variables
- **World Values Survey (WVS)**: Waves 6-7 (pipeline in development)

## What This Repo Does

1. **Loads** raw survey microdata (SPSS/Stata formats)
2. **Searches** variable names and labels across waves via codebook tools
3. **Generates** YAML harmonization specs with automated scale/reversal detection
4. **Harmonizes** variables across waves using YAML-driven recoding
5. **Validates** output with automated reports

## Setup

### R Environment
R packages are managed via `renv`:
```bash
Rscript -e "renv::restore()"
```

### Python Environment (uv)
Python utilities use `uv` with Python 3.12:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv python install 3.12.12
uv sync
source .venv/bin/activate
```

## Running the Pipeline

```bash
# Load raw survey waves
Rscript src/r/data_prep_modules/0_load_waves.R

# Harmonize all variables via YAML specs
Rscript src/r/data_prep_modules/2_harmonize_all.R

# Create final combined dataset
Rscript src/r/data_prep_modules/99_create_final_dataset.R
```

Output: `data/processed/abs_econdev_authpref.rds`

## Structure

```
src/           R/Python code (codebook tools, harmonization engine, utilities)
src/config/    YAML harmonization specifications (27 spec files)
data/raw/      Original survey microdata
data/processed/ Harmonized output datasets
outputs/       Validation reports, per-wave master files
scripts/       Pipeline orchestration
```

## YAML-Driven Harmonization

Each variable is defined in a YAML spec (`src/config/harmonize/*.yml`) that maps source variable names, recoding rules, and scale directions across waves. The codebook tools automate spec generation with scale detection and reversal detection.

See `CLAUDE.md` for detailed pipeline documentation.
