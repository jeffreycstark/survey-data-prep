# Harmonization Module

Cross-wave variable harmonization system for Asian Barometer survey data.

## Overview

Harmonizes variables across multiple survey waves (w1-w6) by:
1. Extracting source variables from each wave
2. Handling missing codes (converting to NA)
3. Applying wave-specific transformations (e.g., reversing scales)
4. Validating results against QC bounds

## Quick Start

### Load functions
```r
source(here::here("src/r/harmonize/_load_harmonize.R"))
source(here::here("src/r/utils/_load_functions.R"))  # For recoding functions
```

### Load YAML specification
```r
library(yaml)

spec <- read_yaml("src/config/harmonize/economy.yml")
validate_harmonize_spec(spec)  # Check structure
```

### Harmonize variables
```r
# Assuming waves are loaded as: list(w1 = df1, w2 = df2, ...)

econ <- harmonize_variable(
  var_spec = spec$variables[["econ_national_now"]],
  waves = waves,
  missing_conventions = spec$missing_conventions
)

# econ$w1, econ$w2, ..., econ$w6 are harmonized vectors
```

### Combine into dataframe
```r
harmonized_data <- bind_cols(
  w1 = econ$w1,
  w2 = econ$w2,
  w3 = econ$w3,
  w4 = econ$w4,
  w5 = econ$w5,
  w6 = econ$w6
)
```

## File Structure

- `harmonize.R` - Core engine: `harmonize_variable()`, `harmonize_all()`
- `validate_spec.R` - YAML validation: `validate_harmonize_spec()`, `check_recoding_functions()`
- `report_harmonization.R` - QC reporting: `report_harmonization()`, `harmonization_summary()`, `check_harmonization_bounds()`
- `_load_harmonize.R` - Function loader
- `test_harmonize.R` - Unit tests

## YAML Specification Format

### Required fields (per variable)
```yaml
id: "variable_id"                    # Unique identifier
concept: "concept_name"              # e.g., "economy", "politics"
description: "Human-readable text"

source:                              # Source variables by wave
  w1: "q001"
  w2: "q1"
  # etc...

type: "ordinal"                      # ordinal | nominal | continuous

target_scale:                        # Optional: document expected scale
  min: 1
  max: 5
  labels: {1: "Bad", ..., 5: "Good"}

missing:
  use_convention: "treat_as_na"      # Points to missing_conventions

harmonize:
  default:
    method: "identity"               # identity | r_function
  
  by_wave:                          # Optional: wave-specific overrides
    w3:
      method: "r_function"
      fn: "safe_reverse_5pt"
      validate_all: ["econom"]       # Regex patterns to validate question text

qc:
  valid_range_by_wave:               # Optional: range validation (warn only)
    w1: [1, 5]
    w2: [1, 5]
    # etc...
```

### Missing conventions (top-level)
```yaml
missing_conventions:
  treat_as_na: [-1, 0, 7, 8, 9]
  treat_as_na_extended: [-1, 0, 97, 98, 99]
```

## Harmonization Methods

### "identity"
Pass values through unchanged (after missing code handling)

### "r_function"
Call a recoding function from `src/r/utils/recoding.R`:
- `safe_reverse_3pt()` - Reverse 3-point scale
- `safe_reverse_4pt()` - Reverse 4-point scale  
- `safe_reverse_5pt()` - Reverse 5-point scale
- `safe_3pt_none()` - Clean 3-point (no reversal)
- `safe_4pt_none()` - Clean 4-point (no reversal)
- `safe_5pt_none()` - Clean 5-point (no reversal)

All functions require:
- `x`: numeric vector
- `data`: full wave dataframe (for label extraction)
- `var_name`: source variable name in that wave
- `validate_all`: character vector of regex patterns to match against question label

## Functions Reference

### `harmonize_variable(var_spec, waves, missing_conventions)`
Harmonize single variable across all waves.

**Returns:** List with one harmonized vector per wave

### `harmonize_all(spec, waves, silent=FALSE)`
Harmonize all variables in a YAML spec.

**Returns:** List of lists (one variable per element)

### `validate_harmonize_spec(spec, var_id=NULL)`
Validate YAML specification structure.

**Returns:** TRUE (invisibly) or stops with error

### `check_recoding_functions(spec)`
Check if all required recoding functions exist.

**Returns:** Character vector of missing functions (or empty)

### `report_harmonization(harmonized, var_spec=NULL, return_tbl=FALSE)`
Generate summary statistics for harmonized variable.

**Returns:** List of stats or tibble

### `harmonization_summary(original_waves, harmonized_list, spec)`
Compare before/after harmonization across all variables.

**Returns:** Data frame with original and harmonized statistics

### `check_harmonization_bounds(harmonized, var_spec)`
Validate values fall within QC bounds (warns, doesn't coerce).

**Returns:** Data frame of violations or NULL

## Example Workflow

```r
# 1. Load functions and recoding utilities
source(here::here("src/r/harmonize/_load_harmonize.R"))
source(here::here("src/r/utils/_load_functions.R"))

# 2. Load wave data (assumed to be list(w1, w2, w3, w4, w5, w6))
waves <- load_waves()  # Your loading function

# 3. Load and validate YAML spec
spec <- yaml::read_yaml("src/config/harmonize/economy.yml")
validate_harmonize_spec(spec)
check_recoding_functions(spec)

# 4. Harmonize all variables
harmonized_list <- harmonize_all(spec, waves, silent = FALSE)

# 5. Generate report
summary <- harmonization_summary(waves, harmonized_list, spec)
print(summary)

# 6. Bind results
combined <- map_df(
  names(harmonized_list),
  ~bind_cols(
    var_id = .x,
    harmonized_list[[.x]]
  )
)
```

## Tags

Variables can be tagged for indexing:
- `core` - Essential variables
- `candidate_index:DOMAIN` - Candidate for composite index
- Any custom tags for organization

## Testing

Run tests:
```r
source(here::here("src/r/harmonize/test_harmonize.R"))
# In RStudio: Run as test file
```

## Configuration

Edit YAML files in `src/config/harmonize/`:
- `economy.yml` - Economic variables
- Add additional files by domain as needed

## Notes

- All harmonization is non-destructive (original data unchanged)
- QC violations produce warnings but don't halt execution
- Missing codes must be defined in `missing_conventions`
- Recoding functions perform semantic validation against question labels
