# Gemini CLI - Project Context: survey-data-prep

## Project Overview
This repository is a **Multi-Survey Harmonization Data Pipeline** designed for cross-national survey research. It provides a reusable infrastructure for loading, searching, harmonizing, and validating microdata from various global survey projects.

## Core Mandates & Principles
- **Absolute Precedence**: Instructions in this `GEMINI.md` file take precedence over general tool defaults.
- **Architectural Consistency**: Adhere to the established 3-stage pipeline pattern for each survey: `0_load_waves.R` -> `2_harmonize_all.R` -> `99_create_final_dataset.R`.
- **YAML-Driven**: Harmonization logic MUST be defined in YAML specs within `src/config/{survey}/harmonize/`.
- **Shared Engine**: Use the shared harmonization engine in `src/r/harmonize/harmonize.R`. Do not duplicate harmonization logic.
- **R-First**: This is primarily an R project using `renv`. Python is used sparingly for utilities.
- **Validation**: Every harmonization change must be validated using `src/r/harmonize/validate_spec.R` and `report_harmonization.R`.

## Technical Stack
- **Language**: R (primary), Python (secondary)
- **Environment Management**: `renv` (R), `uv` (Python)
- **Data Formats**: SPSS (.sav), Stata (.dta), Parquet, RDS
- **Key Libraries**: `tidyverse`, `haven`, `here`, `arrow`, `yaml`

## Project Structure
- `src/r/harmonize/`: Shared harmonization engine.
- `src/r/codebook/`: Tools for searching variables and generating YAML specs.
- `src/r/data_prep_modules/{survey}/`: Survey-specific pipeline scripts.
- `src/config/{survey}/harmonize/`: YAML harmonization specifications.
- `data/{survey}/raw/`: Original survey microdata (ignored by git).
- `data/processed/`: Final harmonized output files.
- `outputs/`: Intermediate master files and validation reports.

## Supported Surveys
- **ABS**: Asian Barometer Survey (Waves 1-6) - *Production ready*
- **WVS**: World Values Survey (Waves 6-7) - *Production ready*
- **LBS**: Latinobarómetro (2015-2023) - *Production ready*
- **Afro**: Afrobarometer (Round 9) - *Production ready*
- **KAMOS**: Korean Attitudes and Mobilization Opinion Survey (Waves 1, 4) - *Production ready*
- **V-Dem**: Varieties of Democracy (v15) - *Scaffolded*

## Common Workflows

### Running a Survey Pipeline (e.g., ABS)
1. Load data: `Rscript src/r/data_prep_modules/0_load_waves.R`
2. Harmonize: `Rscript src/r/data_prep_modules/2_harmonize_all.R`
3. Finalize: `Rscript src/r/data_prep_modules/99_create_final_dataset.R`

### Generating New Harmonization Specs
Use the codebook tools in `src/r/codebook/codebook_workflow.R` to search for variables and generate initial YAML templates.

## Security & Privacy
- **Raw Data**: Never commit raw survey data (`data/*/raw/`).
- **Secrets**: No API keys or credentials should be present or committed.

## Reference Documentation
- `CLAUDE.md`: Detailed pipeline documentation and survey-specific details.
- `README.md`: High-level project overview and setup instructions.
- `src/r/codebook/*.md`: Documentation for codebook and search tools.
