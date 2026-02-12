# Harmonization System - Complete Summary

## What's Been Built

A complete cross-wave variable harmonization system for survey data with automated YAML-based specification and R function-based transformation engine.

## File Structure

```
src/r/harmonize/
├── harmonize.R                 # Core engine (158 lines)
│   ├── %||% operator          # Null coalescing
│   ├── apply_missing()        # Missing code handling
│   ├── harmonize_variable()   # Main harmonization function
│   └── harmonize_all()        # Batch harmonization
│
├── validate_spec.R             # Specification validation (196 lines)
│   ├── validate_harmonize_spec()     # YAML structure validation
│   └── check_recoding_functions()    # Verify functions exist
│
├── report_harmonization.R      # QC & reporting (246 lines)
│   ├── report_harmonization()        # Summary statistics
│   ├── harmonization_summary()       # Before/after comparison
│   └── check_harmonization_bounds()  # QC violations
│
├── test_harmonize.R            # Unit tests (218 lines)
│   ├── Test: identity harmonization
│   ├── Test: missing code handling
│   ├── Test: missing source variable
│   ├── Test: spec validation
│   └── Test: report generation
│
├── _load_harmonize.R           # Function loader (17 lines)
│   └── Source all harmonization functions
│
├── README.md                   # Technical reference
├── GETTING_STARTED.md          # Step-by-step walkthrough
├── SKILLS.md                   # Skill specifications
└── SUMMARY.md                  # This file

src/config/harmonize/
└── economy.yml                 # Example specification
    ├── 3 variables (econ_national_now, econ_change_1yr, econ_outlook_1yr)
    ├── Missing conventions
    └── Source mappings & harmonization rules

src/r/utils/recoding.R (UPDATED)
├── safe_reverse_3pt()          # Enhanced with validate_all
├── safe_reverse_4pt()          # Enhanced with validate_all
├── safe_reverse_5pt()          # Enhanced with validate_all
├── safe_3pt_none()             # Enhanced with validate_all
├── safe_4pt_none()             # Enhanced with validate_all
├── safe_5pt_none()             # Enhanced with validate_all
└── safe_6pt_to_4pt()           # Enhanced with validate_all
```

## Total Lines of Code

- Core functions: 158 lines (harmonize.R)
- Validation: 196 lines (validate_spec.R)
- Reporting: 246 lines (report_harmonization.R)
- Tests: 218 lines (test_harmonize.R)
- Recoding updates: Enhanced all 7 functions
- YAML spec: 3 complete examples
- **Total: ~818 lines + documentation**

## Core Workflow

```
1. USER CREATES SPEC
   /create-harmonize-spec economy
   → Interactive prompts
   → Generates YAML entry
   → Appends to src/config/harmonize/economy.yml

2. YAML SPECIFICATION
   src/config/harmonize/economy.yml
   ├── missing_conventions: {treat_as_na: [-1, 0, 7, 8, 9]}
   ├── variables:
   │   └── econ_national_now:
   │       ├── source: {w1: q001, w2: q1, ...}
   │       ├── harmonize:
   │       │   ├── default: {method: identity}
   │       │   └── by_wave:
   │       │       ├── w3: {method: r_function, fn: safe_reverse_5pt}
   │       │       └── w4-w6: (same)
   │       └── qc: {valid_range_by_wave: {w1: [1,5], ...}}
   │
3. USER APPLIES HARMONIZATION
   /harmonize-variables economy
   → Loads YAML spec
   → Validates structure
   → Applies transformations across waves
   → Generates R code or dataframe
   → Provides QC report

4. HARMONIZED VARIABLES
   econ_national_now = list(
     w1 = numeric vector (1,000 values),
     w2 = numeric vector (1,000 values),
     ...
     w6 = numeric vector (1,000 values)
   )
   
5. USER COMBINES RESULTS
   harmonized_df <- bind_cols(
     econ_national_now = econ_national_now$w1,
     econ_change_1yr = econ_change_1yr$w1,
     econ_outlook_1yr = econ_outlook_1yr$w1
   )
```

## Key Features

### 1. Flexible Specifications
- YAML-based (human-readable, version-controllable)
- Supports multiple variables per file
- Domain organization (economy.yml, politics.yml, etc.)
- Wave-specific overrides

### 2. Harmonization Methods
- **Identity**: pass through unchanged
- **R functions**: call any recoding function with:
  - Automatic data/variable_name passing
  - Optional semantic validation (regex pattern matching)
  - Full data context for missing code handling

### 3. Missing Code Handling
- Named conventions (treat_as_na, treat_as_na_extended, custom)
- Converts specified codes to NA
- Applied after numeric coercion

### 4. Quality Control
- Valid range checking (by wave)
- Before/after comparison
- QC reports with summary statistics
- Warnings (non-blocking) for violations

### 5. Semantic Validation
- Validates question text against patterns
- Ensures reversal is semantically correct
- Prevents mistakes in scale direction

### 6. User-Friendly Skills
- `/create-harmonize-spec`: Interactive YAML creation
- `/harmonize-variables`: Automated code generation
- Both with validation and error handling

## Usage Quick Reference

### Load Functions
```r
source(here::here("src/r/harmonize/_load_harmonize.R"))
source(here::here("src/r/utils/_load_functions.R"))
library(yaml)
```

### Validate Specification
```r
spec <- read_yaml("src/config/harmonize/economy.yml")
validate_harmonize_spec(spec)
check_recoding_functions(spec)
```

### Harmonize Single Variable
```r
econ <- harmonize_variable(
  var_spec = spec$variables[["econ_national_now"]],
  waves = waves,  # list(w1=df1, w2=df2, ...)
  missing_conventions = spec$missing_conventions
)
# Result: list(w1=vector, w2=vector, ..., w6=vector)
```

### Generate Report
```r
report_harmonization(econ, var_spec, return_tbl = TRUE)
check_harmonization_bounds(econ, var_spec)
```

### Harmonize All
```r
all_vars <- harmonize_all(spec, waves, silent = FALSE)
# Result: list(var1=list(w1=v, ...), var2=list(...), ...)
```

## Testing

Run unit tests:
```r
source(here::here("src/r/harmonize/test_harmonize.R"))
# 7 test suites covering:
# - Identity harmonization
# - Missing code handling
# - Missing source variables
# - Specification validation
# - Type validation
# - Report generation
```

## Extensibility

### Adding Variables
Edit YAML or use `/create-harmonize-spec` to interactively add new entries

### Adding Domains
Create new YAML file in `src/config/harmonize/[domain].yml`

### Custom Recoding Functions
Define in `src/r/utils/recoding.R`, then reference in YAML:
```yaml
harmonize:
  by_wave:
    w3:
      method: r_function
      fn: my_custom_function
      validate_all: ["pattern"]
```

### Custom Missing Conventions
Add to YAML `missing_conventions`:
```yaml
missing_conventions:
  treat_as_na: [-1, 0, 7, 8, 9]
  treat_as_na_extended: [-1, 0, 97, 98, 99]
  custom_convention: [999, 888, 777]
```

## Documentation Files

| File | Purpose | Audience |
|------|---------|----------|
| README.md | Technical reference | Developers |
| GETTING_STARTED.md | Step-by-step walkthrough | End users |
| SKILLS.md | Skill specifications | Skill implementers |
| SUMMARY.md | High-level overview | Everyone |

## Next Steps (User Actions)

1. **Test the system** with your actual wave data
   - Load waves as list(w1, w2, w3, w4, w5, w6)
   - Run GETTING_STARTED.md examples
   
2. **Create YAML specs** for your domains
   - Use `/create-harmonize-spec` or edit YAML directly
   - Run `validate_harmonize_spec()` to check
   
3. **Harmonize variables** using `/harmonize-variables`
   - Select domain and variables
   - Choose output format
   - Generate QC reports

4. **Build composite indices** from harmonized variables
   - Use `create_validated_composite()` from data_prep_helpers.R
   - Validate with Cronbach's alpha

5. **Iterate and refine**
   - Add more variables
   - Adjust harmonization rules
   - Review QC reports

## Integration Points

This system integrates with existing project infrastructure:

- **Recoding functions** (src/r/utils/recoding.R) - Enhanced with validate_all
- **Data prep helpers** (src/r/utils/data_prep_helpers.R) - For composites
- **Survey utilities** (src/r/survey/) - Can use with harmonized data
- **Quarto workflow** - Can embed harmonization code in papers

## Key Advantages

✓ **YAML-based** - Specifications are transparent and version-controllable
✓ **Reusable** - Define once, apply across entire analysis
✓ **Maintainable** - Changes in one place update all uses
✓ **Validated** - Multiple checks prevent errors
✓ **Auditable** - QC reports document all transformations
✓ **Automated** - Skills reduce manual coding
✓ **Testable** - Unit tests ensure correctness
✓ **Extensible** - Easy to add new methods or conventions

---

**System Ready.** Waiting for your feedback on what you see when you start using it.
