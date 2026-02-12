# Data Prep Modules

Modular data preparation workflow for cross-wave variable harmonization.

## Overview

This directory contains a scalable, reusable approach to harmonizing variables across survey waves:

1. **Load waves** once with haven labels intact
2. **Apply harmonization logic** using simple helper functions
3. **Validate** NA handling and value ranges
4. **Strip labels** after harmonization complete
5. **Save** clean final dataset

## Files

### 0_load_waves.R
Core loading functions:
- `load_waves()` - Load all 6 waves from RDS files
- `strip_haven_labels()` - Remove haven attributes after harmonization
- `extract_var()` - Extract variable from specific wave with error handling

### 1_harmonize_funs.R
Harmonization helper functions (simple, composable):
- `safe_reverse_4pt()` - Reverse 4-point scale (4→1, 1→4)
- `safe_reverse_5pt()` - Reverse 5-point scale
- `recode_5pt_to_4pt()` - Linear rescaling from 5-point to 4-point
- `recode_3pt_to_4pt()` - Linear rescaling from 3-point to 4-point
- `harmonize_direct()` - Pass-through (no transformation)
- `validate_harmonization()` - QC check on harmonized variable

### institutional_trust.R
Complete harmonization pipeline for institutional trust variables:

**Workflow:**
1. Load all 6 waves (with haven labels)
2. Read institutional_trust.yml config (13 variables)
3. For each variable:
   - Extract source variables from each wave
   - Apply harmonization method (direct, reverse, recode)
   - Validate NA handling
   - Stack results
4. Strip haven labels
5. Save to `data/processed/institutional_trust_harmonized.rds`

**Run:** `Rscript src/r/data_prep_modules/institutional_trust.R`

## YAML Configuration Format

See `src/config/harmonize/institutional_trust.yml` for example:

```yaml
variables:
  - name: trust_civil_service              # Variable name in output
    id: TRUST_CIVIL_SERVICE                # Identifier
    label: Trust in Civil Service          # Description
    concept: institutional_trust           # Concept area

    sources:
      - wave: w1                           # Wave identifier
        variable: q011                     # Variable name in wave data
        label: "Question text"             # For validation
        validate_phrase: "civil"           # Check label contains this
      - wave: w2
        variable: q12
        label: "Question text"
        validate_phrase: "civil"

    scale:
      type: likert
      min_value: 1
      max_value: 4
      reversed: false

    harmonize:
      - method: direct                     # Options: direct, safe_reverse_4pt, safe_reverse_5pt, recode_*
```

## Example Output

```r
# After running institutional_trust.R

harmonized_data <- readRDS("data/processed/institutional_trust_harmonized.rds")

head(harmonized_data)
# Wave | trust_civil_service | trust_courts | ... (13 trust variables)
# w1   |                   3 |            2 | ...
# w1   |                   2 |            3 | ...
# w2   |                   4 |            4 | ...
```

## Adding New Harmonization Modules

To create a new data prep module (e.g., for democracy satisfaction):

1. Create `democracy_satisfaction.R` following the `institutional_trust.R` pattern
2. Source the helper functions: `0_load_waves.R` and `1_harmonize_funs.R`
3. Create corresponding YAML in `src/config/harmonize/democracy_satisfaction.yml`
4. Run: `Rscript src/r/data_prep_modules/democracy_satisfaction.R`

## Design Principles

- **Modular:** Each data prep module is independent
- **Reusable:** Helper functions work across all modules
- **Simple:** R code is concise, logic lives in YAML config
- **Validating:** NA handling checked for every variable
- **Transparent:** Labels kept during harmonization for QC, then stripped

## Integration with Analysis

After harmonization, load the processed dataset:

```r
# In analysis scripts
inst_trust <- readRDS(here::here("data", "processed", "institutional_trust_harmonized.rds"))

# Variables are clean (no haven labels, consistent scales)
inst_trust %>%
  group_by(wave) %>%
  summarise(across(starts_with("trust_"), mean, na.rm = TRUE))
```
