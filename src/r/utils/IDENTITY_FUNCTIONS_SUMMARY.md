# Identity Recoding Functions Summary

## New Functions Added to R/utils/recoding.R

### 1. safe_3pt_none()
**Purpose:** Handle 3-point scale variables without reversal (identity function)

**Behavior:**
- Valid values (1-3): Preserved as-is
- Missing codes (-1, 0, 7, 8, 9): Converted to NA
- Optional keyword validation

**Example:**
```r
x <- c(1, 2, 3, -1, 8, NA)
safe_3pt_none(x)
# Returns: 1, 2, 3, NA, NA, NA
```

### 2. safe_4pt_none()
**Purpose:** Handle 4-point scale variables without reversal (identity function)

**Behavior:**
- Valid values (1-4): Preserved as-is
- Missing codes (-1, 0, 7, 8, 9): Converted to NA
- Optional keyword validation

**Example:**
```r
x <- c(1, 2, 3, 4, -1, 8, NA)
safe_4pt_none(x)
# Returns: 1, 2, 3, 4, NA, NA, NA
```

### 3. safe_5pt_none()
**Purpose:** Handle 5-point scale variables without reversal (identity function)

**Behavior:**
- Valid values (1-5): Preserved as-is
- Missing codes (-1, 0, 7, 8, 9): Converted to NA
- Optional keyword validation

**Example:**
```r
x <- c(1, 2, 3, 4, 5, -1, 8, NA)
safe_5pt_none(x)
# Returns: 1, 2, 3, 4, 5, NA, NA, NA
```

## Function Signatures

All three functions share the same signature:

```r
safe_Npt_none(x,
              missing_codes = c(-1, 0, 7, 8, 9),
              validate_keyword = NULL,
              question_text = NULL,
              var_name = NULL)
```

**Parameters:**
- `x`: Numeric vector to recode
- `missing_codes`: Vector of codes to convert to NA (default: c(-1, 0, 7, 8, 9))
- `validate_keyword`: Optional keyword to check in question text
- `question_text`: Named vector of question texts for validation
- `var_name`: Variable name for validation error messages

## Integration with trust.R

Updated `get_recode_function()` in `R/concepts/trust.R` to support these new functions:

```r
switch(key,
  "3pt_reverse" = safe_reverse_3pt,
  "3pt_none" = safe_3pt_none,      # NEW
  "4pt_reverse" = safe_reverse_4pt,
  "4pt_none" = safe_4pt_none,      # NEW
  "5pt_reverse" = safe_reverse_5pt,
  "5pt_none" = safe_5pt_none,      # NEW
  ...
)
```

## Use Cases

These functions are useful for variables that:
1. Already have the correct directionality (no reversal needed)
2. Need missing code cleaning
3. Should preserve original scale values

**Common examples:**
- Demographic variables (age categories, education levels)
- Behavioral frequencies already coded as 1=Never to 5=Always
- Satisfaction measures where 1=Very dissatisfied to 4=Very satisfied (correct direction)

## Test Results

All functions tested successfully:
- ✓ Valid values preserved (no reversal)
- ✓ Missing codes converted to NA
- ✓ Comparison with reversal functions shows correct identity behavior

Run tests: `Rscript R/utils/test_identity_functions.R`

## Note on Duplicate Function

⚠️ **Issue found:** `safe_reverse_4pt` is defined twice in recoding.R (lines 28-47 and 48-71). The second definition (48-71) is active. Consider removing the duplicate.

## Crosswalk Usage

In the harmonization crosswalk CSV, use:
- `scale_type`: "3pt", "4pt", or "5pt"
- `recode_needed`: "none"

Example:
```csv
wave,concept_domain,raw_variable,scale_type,recode_needed,notes
6,demographic,age_group,3pt,none,"Already coded 1=Young to 3=Old"
6,satisfaction,life_satisfaction,4pt,none,"1=Very dissatisfied to 4=Very satisfied"
```
