# Getting Started with Harmonization

Complete walkthrough of the harmonization system.

## What You Have

```
src/r/harmonize/
├── harmonize.R              # Core engine
├── validate_spec.R          # YAML validation
├── report_harmonization.R   # QC & reporting
├── test_harmonize.R         # Unit tests
├── _load_harmonize.R        # Function loader
├── README.md                # Technical documentation
├── SKILLS.md                # Skill specifications
└── GETTING_STARTED.md       # This file

src/config/harmonize/
└── economy.yml              # Example spec with 3 variables

src/r/utils/
├── recoding.R               # Reversal/identity functions (updated)
└── _load_functions.R        # Function loader
```

## Step 1: Load Functions (Interactive R Session)

```r
# Load harmonization functions
source(here::here("src/r/harmonize/_load_harmonize.R"))

# Load recoding utilities (safe_reverse_*pt, etc.)
source(here::here("src/r/utils/_load_functions.R"))

# Load YAML parsing
library(yaml)
library(dplyr)
```

**What you'll see:**
```
✓ Harmonization functions loaded:
  - harmonize_variable()
  - harmonize_all()
  - validate_harmonize_spec()
  - check_recoding_functions()
  - report_harmonization()
  - harmonization_summary()
  - check_harmonization_bounds()
```

## Step 2: Validate Your YAML Spec

```r
# Load the economy specification
spec <- read_yaml("src/config/harmonize/economy.yml")

# Validate structure
validate_harmonize_spec(spec)

# Check that recoding functions exist
missing <- check_recoding_functions(spec)
if (length(missing) > 0) {
  warning("Missing functions: ", paste(missing, collapse = ", "))
}
```

**What you'll see:**
```
[1] TRUE

# No output means validation passed
# If missing functions, you'd see warnings
```

## Step 3: Prepare Wave Data

Assuming your wave data is already loaded as a named list:

```r
# This is what the harmonization expects:
waves <- list(
  w1 = readRDS("data/processed/w1.rds"),
  w2 = readRDS("data/processed/w2.rds"),
  w3 = readRDS("data/processed/w3.rds"),
  w4 = readRDS("data/processed/w4.rds"),
  w5 = readRDS("data/processed/w5.rds"),
  w6 = readRDS("data/processed/w6.rds")
)

# Check structure
names(waves)  # Should show: "w1" "w2" "w3" "w4" "w5" "w6"
```

## Step 4: Harmonize Single Variable

```r
# Get one variable spec
var_spec <- spec$variables[["econ_national_now"]]

# Harmonize across all waves
econ_national <- harmonize_variable(
  var_spec = var_spec,
  waves = waves,
  missing_conventions = spec$missing_conventions
)

# Check result
str(econ_national)
```

**What you'll see:**
```
List of 6
 $ w1: num [1:1000] 1 2 3 4 5 1 2 3 4 5 ...
 $ w2: num [1:1000] 1 2 3 4 5 1 2 3 4 5 ...
 $ w3: num [1:1000] 5 4 3 2 1 5 4 3 2 1 ...
 $ w4: num [1:1000] 5 4 3 2 1 5 4 3 2 1 ...
 $ w5: num [1:1000] 5 4 3 2 1 5 4 3 2 1 ...
 $ w6: num [1:1000] 5 4 3 2 1 5 4 3 2 1 ...
```

## Step 5: Generate QC Report

```r
# Get summary statistics
report_harmonization(econ_national, var_spec, return_tbl = TRUE)
```

**What you'll see:**
```
# A tibble: 6 × 9
  wave      n n_valid n_missing pct_missing  mean    sd   min   max
  <chr> <int>   <int>     <int>       <dbl> <dbl> <dbl> <dbl> <dbl>
1 w1     1000     985        15         1.5  2.45  1.23     1     5
2 w2     1000     992         8         0.8  2.38  1.25     1     5
3 w3     1000     988        12         1.2  2.56  1.19     1     5
4 w4     1000     991         9         0.9  2.52  1.21     1     5
5 w5     1000     989        11         1.1  2.41  1.24     1     5
6 w6     1000     990        10         1.0  2.44  1.22     1     5
```

## Step 6: Check QC Bounds

```r
# Validate against valid_range_by_wave
bounds <- check_harmonization_bounds(econ_national, var_spec)
bounds  # NULL if no violations, or data frame showing violations
```

**What you'll see:**
```
ℹ️  All values within valid ranges
NULL

# Or if there are violations:
# A tibble: 2 × 5
  wave  n_violations valid_range n_below_min n_above_max
  <chr>        <int> <chr>             <int>       <int>
1 w3               2 [1, 5]               0           2
2 w5               1 [1, 5]               0           1
```

## Step 7: Harmonize All Variables

```r
# Harmonize everything in the spec
all_harmonized <- harmonize_all(spec, waves, silent = FALSE)

# Check result
names(all_harmonized)  # One element per variable
```

**What you'll see:**
```
Harmonizing: econ_national_now
Harmonizing: econ_change_1yr
Harmonizing: econ_outlook_1yr

# Each contains: list(w1 = ..., w2 = ..., ..., w6 = ...)
```

## Step 8: Bind Into Dataframe

### Option A: Single variable, single wave
```r
# Get w1 data for one variable
w1_econ <- data.frame(
  econ_national_now = all_harmonized$econ_national_now$w1,
  econ_change_1yr = all_harmonized$econ_change_1yr$w1,
  econ_outlook_1yr = all_harmonized$econ_outlook_1yr$w1
)

head(w1_econ)
```

**What you'll see:**
```
  econ_national_now econ_change_1yr econ_outlook_1yr
1                 1               1                1
2                 2               2                2
3                 3               3                3
4                 4               4                4
5                 5               5                5
6                 1              NA                1
```

### Option B: All variables, cross-wave format
```r
# Stack all waves together
harmonized_long <- bind_rows(
  lapply(names(all_harmonized), function(var_id) {
    var_data <- all_harmonized[[var_id]]
    
    bind_rows(
      lapply(names(var_data), function(wave) {
        data.frame(
          var_id = var_id,
          wave = wave,
          value = var_data[[wave]]
        )
      })
    )
  })
)

head(harmonized_long)
```

**What you'll see:**
```
           var_id wave value
1 econ_national_now   w1     1
2 econ_national_now   w1     2
3 econ_national_now   w1     3
4 econ_national_now   w1     4
5 econ_national_now   w1     5
6 econ_national_now   w1     1
```

### Option C: Wide format (all variables as columns)
```r
# Create wide dataframe with all harmonized variables
harmonized_wide <- data.frame(
  row.names = seq_len(nrow(waves$w1))
)

for (var_id in names(all_harmonized)) {
  for (wave in names(all_harmonized[[var_id]])) {
    col_name <- paste0(var_id, "_", wave)
    harmonized_wide[[col_name]] <- all_harmonized[[var_id]][[wave]]
  }
}

head(harmonized_wide)
```

**What you'll see:**
```
  econ_national_now_w1 econ_change_1yr_w1 econ_outlook_1yr_w1 econ_national_now_w2
1                    1                  1                   1                    1
2                    2                  2                   2                    2
3                    3                  3                   3                    3
4                    4                  4                   4                    4
5                    5                  5                   5                    5
6                    1                 NA                   1                    1
...
```

## Step 9: Generate Full Comparison Report

```r
# Compare before/after harmonization
comp <- harmonization_summary(waves, all_harmonized, spec)
print(comp, n = Inf)  # Show all rows
```

**What you'll see:**
```
# A tibble: 18 × 13
   var_id              concept wave source_var orig_n orig_n_missing orig_mean
   <chr>               <chr>   <chr> <chr>      <int>          <int>      <dbl>
 1 econ_national_now   economy w1    q001        1000             15       2.45
 2 econ_national_now   economy w2    q1          1000              8       2.38
 3 econ_national_now   economy w3    q1          1000             12       2.56
 4 econ_national_now   economy w4    q1          1000              9       2.52
 5 econ_national_now   economy w5    q1          1000             11       2.41
 6 econ_national_now   economy w6    q1          1000             10       2.44
 7 econ_change_1yr     economy w1    q002        1000             15       2.42
 ...
   orig_range harm_n harm_n_missing harm_mean harm_range
   <chr>       <int>          <int>      <dbl> <chr>
 1 [1, 5]       1000             15       2.45 [1, 5]
 2 [1, 5]       1000              8       2.38 [1, 5]
 3 [1, 5]       1000             12       2.56 [1, 5]
 4 [1, 5]       1000              9       2.52 [1, 5]
 5 [1, 5]       1000             11       2.41 [1, 5]
 6 [1, 5]       1000             10       2.44 [1, 5]
 ...
```

## Next Steps

### Adding New Variables

Use `/create-harmonize-spec` skill to interactively create new YAML entries:
- Prompts guide you through structure
- Validates inputs before appending to file
- Confirms successful creation

### Adding New Domains

Create new YAML files:
```bash
touch src/config/harmonize/politics.yml
# Edit following economy.yml structure
```

### Creating Composite Indices

Use harmonized variables to create composites:
```r
source(here::here("src/r/utils/data_prep_helpers.R"))

# Create composite from harmonized variables
economy_index <- create_validated_composite(
  data = harmonized_wide,
  vars = c("econ_national_now_w1", "econ_change_1yr_w1", "econ_outlook_1yr_w1"),
  composite_name = "economy_index_w1",
  min_alpha = 0.60,
  method = "cronbach"
)
```

### Running Tests

```r
source(here::here("src/r/harmonize/test_harmonize.R"))
```

## Troubleshooting

**Q: "Recoding function not found"**
A: Check that recoding functions are loaded:
```r
source(here::here("src/r/utils/_load_functions.R"))
```

**Q: Variable has missing source**
A: Check YAML spec - source variables must be in each wave's dataframe
```r
names(waves$w1)  # Should contain "q001"
names(waves$w3)  # Should contain "q1"
```

**Q: All values becoming NA**
A: Check missing code conventions:
```r
spec$missing_conventions  # What codes trigger NA conversion?
```

**Q: Values outside valid range warning**
A: This is expected - warnings don't stop execution. Check:
```r
bounds <- check_harmonization_bounds(econ_national, var_spec)
```

## Key Concepts

- **Source**: variable name IN EACH WAVE (can differ across waves)
- **Target**: standardized harmonized variable (same across waves)
- **Reversal**: e.g., 5pt → 4pt → 3pt → 2pt → 1pt (for scale reversals)
- **Identity**: pass through without transformation
- **Missing codes**: defined in `missing_conventions`, converted to NA
- **QC bounds**: valid range enforcement (warns, doesn't coerce)
