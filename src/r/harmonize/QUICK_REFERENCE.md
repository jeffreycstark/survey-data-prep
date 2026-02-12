# Quick Reference Card

## Setup (one-time)
```r
source(here::here("src/r/harmonize/_load_harmonize.R"))
source(here::here("src/r/utils/_load_functions.R"))
library(yaml); library(dplyr)

# Prepare wave data
waves <- list(
  w1 = readRDS("data/processed/w1.rds"),
  w2 = readRDS("data/processed/w2.rds"),
  w3 = readRDS("data/processed/w3.rds"),
  w4 = readRDS("data/processed/w4.rds"),
  w5 = readRDS("data/processed/w5.rds"),
  w6 = readRDS("data/processed/w6.rds")
)
```

## Load Specification
```r
spec <- read_yaml("src/config/harmonize/economy.yml")
validate_harmonize_spec(spec)      # Check structure
check_recoding_functions(spec)      # Check functions exist
```

## Harmonize Variables

### One variable
```r
econ <- harmonize_variable(
  spec$variables[["econ_national_now"]],
  waves, spec$missing_conventions
)
```

### All variables in spec
```r
all_vars <- harmonize_all(spec, waves)
```

## Quality Control

### View summary stats
```r
report_harmonization(econ, return_tbl = TRUE)
```

### Check valid ranges
```r
check_harmonization_bounds(econ, var_spec)
```

### Before/after comparison
```r
harmonization_summary(waves, all_vars, spec)
```

## Combine Results

### Single wave, multiple variables
```r
w1_df <- data.frame(
  econ_now = all_vars$econ_national_now$w1,
  econ_change = all_vars$econ_change_1yr$w1,
  econ_outlook = all_vars$econ_outlook_1yr$w1
)
```

### All waves, wide format
```r
wide_df <- data.frame(row.names = seq_len(nrow(waves$w1)))
for (var_id in names(all_vars)) {
  for (wave in names(all_vars[[var_id]])) {
    wide_df[[paste0(var_id, "_", wave)]] <- 
      all_vars[[var_id]][[wave]]
  }
}
```

## Common Tasks

| Task | Command |
|------|---------|
| Create new variable | `/create-harmonize-spec economy` |
| Harmonize all | `all_vars <- harmonize_all(spec, waves)` |
| Check spec | `validate_harmonize_spec(spec)` |
| Get summary | `report_harmonization(econ, return_tbl=T)` |
| Find violations | `check_harmonization_bounds(econ, spec)` |
| Make composite | `create_validated_composite(data, vars, ...)` |

## YAML Template
```yaml
missing_conventions:
  treat_as_na: [-1, 0, 7, 8, 9]

variables:
  var_id:
    id: "var_id"
    concept: "domain"
    description: "text"
    source: {w1: q001, w2: q1, w3: q1, ...}
    type: "ordinal"
    target_scale: {min: 1, max: 5, labels: {...}}
    missing: {use_convention: "treat_as_na"}
    harmonize:
      default: {method: "identity"}
      by_wave:
        w3: {method: "r_function", fn: "safe_reverse_5pt", 
             validate_all: ["econom"]}
    qc: {valid_range_by_wave: {w1: [1,5], ...}}
    tags: ["core", "candidate_index:economy"]
```

## Functions at a Glance

| Function | Input | Output | Use For |
|----------|-------|--------|---------|
| `harmonize_variable()` | var_spec, waves, conventions | list(w1=v, w2=v, ...) | Harmonize 1 variable |
| `harmonize_all()` | spec, waves | list(var1=..., var2=...) | Harmonize all |
| `validate_harmonize_spec()` | spec | TRUE or error | Check YAML |
| `check_recoding_functions()` | spec | char vector | Verify functions |
| `report_harmonization()` | harmonized, spec | tbl or print | Summary stats |
| `check_harmonization_bounds()` | harmonized, spec | tbl or NULL | QC violations |
| `harmonization_summary()` | orig, harm, spec | data.frame | Before/after |
| `apply_missing()` | x, codes | numeric | Clean codes |

## Recoding Functions (from src/r/utils/)

```r
safe_reverse_3pt(x, data, var_name, validate_all=c("pattern"))
safe_reverse_4pt(x, data, var_name, validate_all=c("pattern"))
safe_reverse_5pt(x, data, var_name, validate_all=c("pattern"))
safe_3pt_none(x, data, var_name, validate_all=c("pattern"))
safe_4pt_none(x, data, var_name, validate_all=c("pattern"))
safe_5pt_none(x, data, var_name, validate_all=c("pattern"))
safe_6pt_to_4pt(x, data, var_name, validate_all=c("pattern"))
```

All expect: named list waves, question labels in attr(data[[var_name]], "label")

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Function not found | `source(here::here("src/r/..."))` |
| YAML invalid | `validate_harmonize_spec(spec)` |
| Values becoming NA | Check `spec$missing_conventions` |
| Source not found | Check variable names in waves |
| Reversal wrong way | Check `validate_all` pattern in YAML |

## Files

- `src/r/harmonize/harmonize.R` - Core functions
- `src/r/harmonize/validate_spec.R` - Validators
- `src/r/harmonize/report_harmonization.R` - QC reports
- `src/r/harmonize/_load_harmonize.R` - Load all
- `src/config/harmonize/economy.yml` - Example spec
