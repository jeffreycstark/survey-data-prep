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
src/              R/Python code (codebook tools, harmonization engine, utilities)
src/config/abs/   ABS YAML harmonization specs (27 spec files)
src/config/wvs/   WVS YAML harmonization specs (planned)
data/abs/raw/     ABS survey microdata (waves 1-6)
data/wvs/raw/     WVS survey microdata (waves 6-7)
data/processed/   Harmonized output datasets
outputs/          Validation reports, per-wave master files
scripts/          Pipeline orchestration
```

## YAML-Driven Harmonization

Each survey has its own set of YAML specs (`src/config/{survey}/harmonize/*.yml`) mapping source variable names, recoding rules, and scale directions across waves. The harmonization engine is shared; only the YAML specs differ per survey. The codebook tools automate spec generation with scale detection and reversal detection.

See `CLAUDE.md` for detailed pipeline documentation.
