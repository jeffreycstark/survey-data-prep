# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Project**: Multi-Survey Harmonization Data Pipeline

## Surveys at a glance

| Survey | Status | Coverage | Per-survey docs |
|---|---|---|---|
| Asian Barometer (ABS) | Complete | 330 vars, 6 waves, 113,945 resp; W6 = 12 countries | [docs/surveys/abs.md](docs/surveys/abs.md) |
| World Values Survey (WVS) | Complete | 62 vars, 7 waves, 446,767 resp, 108 countries | [docs/surveys/wvs.md](docs/surveys/wvs.md) |
| Latinobarómetro (LBS) | Complete | 19 vars, 24 waves 1995–2024, 489,771 resp | [docs/surveys/lbs.md](docs/surveys/lbs.md) |
| Afrobarometer | Complete | 38 vars + 3 indices, R1–R9 + partial R10, 391,815 resp; T&M extension items R5/R8/R9 | [docs/surveys/afro.md](docs/surveys/afro.md) |
| Arab Barometer | Verbatim done; harmonization in progress | W1–W8 | [docs/surveys/arab-barometer.md](docs/surveys/arab-barometer.md) |
| KAMOS | Complete | 39 vars, 2 waves (2016, 2019), 3,500 resp | [docs/surveys/kamos.md](docs/surveys/kamos.md) |
| KGSS | Complete | 187 vars, 17 years 2003–2025, 23,282 resp | [docs/surveys/kgss.md](docs/surveys/kgss.md) |
| KIPA Corruption | Complete | 36 vars, 20 years 2004–2023; **specialty sample** | [docs/surveys/kipa-corruption.md](docs/surveys/kipa-corruption.md) |
| KINU Unification | Complete | 127 vars, 13 waves 2014–2023 (biannual 2019–2021) | [docs/surveys/kinu.md](docs/surveys/kinu.md) |
| IPUS Unification | Initial | 11 vars, 18 annual waves 2007–2024, 21,617 resp | [docs/surveys/ipus.md](docs/surveys/ipus.md) |
| Korean Unification Tri-Survey Panel (derived) | Complete | KGSS + KINU + IPUS, 46 wave-rows | [docs/surveys/korean-unification-panel.md](docs/surveys/korean-unification-panel.md) |
| Global Corruption Barometer (GCB) | Scaffold | 22 vars, 1 edition (Asia 2020), 19,416 resp, 17 countries; region-extensible | [docs/surveys/gcb.md](docs/surveys/gcb.md) |
| V-Dem v15 | Scaffold | Country-year panel, 202 countries, 1789–2024 | [docs/surveys/vdem.md](docs/surveys/vdem.md) |

⚠️ KIPA Corruption is **NOT a general-population survey** — corporate employees + self-employed with gov-business contact. Cannot row-bind with KGSS/KAMOS/KIPA-social.

---

## Project Purpose

This repo houses reusable survey data harmonization infrastructure:
- YAML-driven variable specifications (separate spec sets per survey)
- Automated scale detection, reversal detection, and recoding
- Multi-wave data loading, harmonization, and validation
- Codebook search and analysis tools

Each survey has its own data directory, YAML specs, and pipeline cycle. It is **not** a paper repo. Papers that consume the harmonized data live in separate repositories.

For the directory tree, see [docs/STRUCTURE.md](docs/STRUCTURE.md).

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

Per-survey dictionary status lives in each survey's docs page.

**Appendix A workflow:** Papers in paper-bank consume these dictionaries via the `appendix-variable-builder` skill (`scripts/appendix-variable-builder/`). The skill is an R generator (`build_appendix.R`) that joins the per-survey verbatim CSV with the harmonization YAMLs and emits paper-13-style markdown — per-wave question-ID grids, verbatim item text, response scales, harmonization notes, and shared-stem battery auto-detection. This repo owns the ground truth; paper repos only format and present. See `scripts/appendix-variable-builder/SKILL.md` for usage.

### Running pipelines

Each survey's run commands live in its docs page (e.g., [docs/surveys/kgss.md](docs/surveys/kgss.md)). The general pattern is:

```bash
Rscript src/r/data_prep_modules/{survey}/0_load_waves.R       # if applicable
Rscript src/r/data_prep_modules/{survey}/2_harmonize_all.R
Rscript src/r/data_prep_modules/{survey}/99_create_final_dataset.R
```

ABS lives at `src/r/data_prep_modules/` (no subdir). V-Dem only has step 99 (scaffold).

---

## YAML Workflow

### Generate YAML for a New Concept
```r
source("src/r/codebook/codebook_workflow.R")
results <- extract_matches("search term", w1, w2, w3, w4, w5, w6)
yaml_str <- generate_codebook_yaml(results, concept = "concept_name")
cat(yaml_str)
writeLines(yaml_str, "src/config/abs/harmonize/concept_name.yml")  # or wvs/, etc.
```

### Batch Process Multiple Concepts
```r
source("src/r/codebook/codebook_workflow.R")
results_list <- list(
  economy = extract_matches("economic condition", w1, w2, w3, w4, w5, w6),
  politics = extract_matches("trust government", w1, w2, w3, w4, w5, w6)
)
batch_generate_yaml(results_list, output_dir = "src/config/abs/harmonize/")
```

For deeper codebook tooling docs, see `src/r/codebook/` (README, QUICK_REFERENCE, SKILL_SEARCH_AND_ANALYZE).

---

## Cross-survey scale gotchas

The single most error-prone area. Read before merging or comparing across surveys.

- **Trust scales differ across surveys**:
  - ABS / WVS / LBS / Afro / KINU institutional trust: **1–4**, higher=more trust.
  - KAMOS trust: **0–10**, higher=more trust.
  - KGSS `conf_*`: **1–3**, higher=more confidence.
  - Do not combine without rescaling.
- **Korean unification direction**:
  - IPUS `uni_necessity` and KINU `uni_necessity`: higher=more pro-unification ✓
  - KGSS `pol_unification`: higher=LESS pro-unification (OPPOSITE; reverse before comparing).
  - The pre-built `korean_unification_panel.rds` already aligns directions.
- **`subjective_class_6pt` direction is OPPOSITE between KGSS and KINU**.
- **KIPA judiciary mislabel**: English SPSS labels mistranslate 사법부 (judiciary) as "legislature". Korean-label matching is correct.
- **ABS system-support battery direction**: the four agree/disagree items — `system_capable`, `system_prefer`, `system_proud`, `system_deserves_support` — all share raw coding **1=Strongly agree → 4=Strongly disagree** and are **reversed** in harmonization (`safe_reverse_4pt`) so higher = more system support. `system_needs_change` is a *different* item (raw 1=works fine → 4=should be replaced), **not** reversed → higher = more desire for change. ⚠️ Historical bug: `system_deserves_support` was harmonized **without** reversal until 2026-06-20 (fixed `safe_4pt_none` → `safe_reverse_4pt`). Any paper `analysis_data.rds` built before that date carries this one item backwards (opposite its three battery-mates); re-run against the corrected `abs_harmonized.rds`. Some papers applied a manual `5 - system_deserves_support` to compensate for the bug — those will **double-reverse** (become wrong) when re-run against fixed data, so remove the manual reversal there.

---

## Paper-time lookups (`src/r/lookups/`)

Some context is deliberately not baked into harmonized RDS files — coalition labels are contested, crosswalks are partial, and downstream papers may want to choose-at-load rather than disagree-and-override. These lookups live in `src/r/lookups/` and are joined on demand.

- **Cross-wave party lineage** — `join_party_crosswalk()` adds `party_lineage` and `coalition` columns from `data/processed/party_id_crosswalk.csv` (Korea / Taiwan / Thailand × W2-W6). Other (country × wave) combos get NA + a one-time warning. Country-code map at `data/lookups/abs_country_codes.csv`. See `src/r/lookups/README.md` for usage.

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

## Slope Prospector

Trend-anomaly detection tool over harmonized country-wave means. Produces 10 outputs (outlier slopes, structural breaks, divergent pairs, acceleration, concept-group coherence, country clusters, narrative-pattern matches, heatmaps, dashboards). See [docs/SLOPE_PROSPECTOR.md](docs/SLOPE_PROSPECTOR.md). **Findings are puzzles, not conclusions.**

---

## Environment Setup

**R** (primary language): Managed via `renv`. Restore with `Rscript -e "renv::restore()"`. Key packages: tidyverse, haven (SPSS I/O), here, arrow (parquet I/O).

**Python** (minimal use): Managed via `uv`. Setup: `uv sync && source .venv/bin/activate`. Lint: `ruff check src/python/`.

No R MCP is currently configured. R code is executed via `Rscript` in Bash.

## Architecture Notes

**Adding a new survey**: Each survey follows the same 3-file pipeline pattern in `src/r/data_prep_modules/{survey}/`: `0_load_waves.R` → `2_harmonize_all.R` → `99_create_final_dataset.R`. YAML specs go in `src/config/{survey}/harmonize/`. The harmonization engine (`src/r/harmonize/harmonize.R`) is shared across all surveys.

**Shared recoding functions** live in `src/r/utils/recoding.R`: `safe_reverse_3pt/4pt/5pt/6pt()`, `safe_3pt/4pt/5pt/6pt_none()`, plus ~90 wave- and survey-specific helpers (`recode_w*_*`, `collapse_*`). These are referenced by name in YAML spec `fn:` fields and reach each survey via `src/r/utils/_load_functions.R`, sourced from each `2_harmonize_all.R`.

**ABS uses validated specs**: Production ABS specs are in `src/config/abs/harmonize_validated/` (28 files), not `harmonize/`.
