# Using the Harmonized Democracy Satisfaction Data

**File**: `data/processed/democracy_satisfaction_harmonized.rds`  
**Format**: R RDS (binary R format)  
**Variables**: 3 satisfaction measures  
**Observations**: 110,721 (combined across 6 waves)  
**Date Created**: 2026-01-07

## Quick Start

```r
# Load the harmonized data
harmonized <- readRDS('data/processed/democracy_satisfaction_harmonized.rds')

# View variable names
names(harmonized)
# Output: "dem_sat_national"  "gov_sat_national"  "hh_income_sat"

# Access democracy satisfaction for all waves
dem_sat <- harmonized$dem_sat_national
str(dem_sat)
# Output: List of 6 named vectors (w1, w2, w3, w4, w5, w6)

# Extract Wave 3 democracy satisfaction as a vector
dem_sat_w3 <- dem_sat$w3
summary(dem_sat_w3)
```

## Variable Descriptions

### 1. dem_sat_national (Democracy Satisfaction) ✅ RECOMMENDED

**Scale**: 4-point ordinal  
**Question**: "How satisfied are you with the way democracy works in your country?"  
**Values**:
- 1 = Not at all satisfied
- 2 = Not very satisfied  
- 3 = Fairly satisfied
- 4 = Very satisfied
- NA = Missing

**Data Quality**: Excellent
- 92.6%-97.1% valid data across waves
- Mean ~2.2 (slightly below midpoint)
- Consistent across all 6 waves

**Special Notes**:
- Waves 1-2: Scale was reversed before harmonization
- Waves 3-6: Used as-is (already correct direction)
- Missing codes (-1, 0, 7, 8, 9) converted to NA

---

### 2. gov_sat_national (Government Satisfaction) ⚠️ USE WITH CAUTION

**Scale**: Varies by wave (4-5 point ordinal or 10-point)  
**Question**: "How satisfied are you with government's handling of key issues?"  
**Values**: 1-4 (or 1-10 in W3-W5), NA = Missing

**⚠️ CRITICAL ISSUES**:
- **Wave 1**: 5-point scale, 28.5% missing
- **Wave 2**: 92.5% missing (data quality issue)
- **Wave 3-5**: 10-point scale (NOT 4-point as expected)
- **Wave 6**: 4-point scale, 5.5% missing

**Data Quality**: Poor (requires careful handling)
- Only 57.5% valid data overall
- Scale inconsistencies across waves
- W2 almost entirely missing

**Recommended Use**:
- For exploratory analysis only
- Collapse W3-W5 to 4-point before analysis
- Consider excluding W2 due to data loss
- Document any scale conversions in publications

---

### 3. hh_income_sat (Household Income Satisfaction) 🚨 NOT RECOMMENDED

**Scale**: 4-point ordinal (when available)  
**Question**: "How satisfied are you with your household's income?"  
**Values**: 1-4, NA = Missing

**🚨 CRITICAL ISSUES**:
- **Waves 1, 5, 6**: 100% missing (no source data)
- **Wave 2**: 7.3% missing (usable)
- **Wave 3-4**: 37.5%-47.8% missing (partial)
- Source variable names may be incorrect

**Data Quality**: Very poor
- Only 37.3% usable data
- 3 waves completely missing
- Inconsistent availability

**Recommended Use**:
- ❌ NOT RECOMMENDED for analysis
- Verify source variable names before use
- Consider alternative income satisfaction measures
- Consult codebook for correct variable locations

---

## Code Examples

### Example 1: Compare democracy satisfaction across waves

```r
harmonized <- readRDS('data/processed/democracy_satisfaction_harmonized.rds')
dem_sat <- harmonized$dem_sat_national

# Create summary table
library(tidyverse)

summary_table <- tibble(
  wave = names(dem_sat),
  n = sapply(dem_sat, length),
  valid = sapply(dem_sat, ~sum(!is.na(.))),
  missing = sapply(dem_sat, ~sum(is.na(.))),
  mean = sapply(dem_sat, ~mean(., na.rm=TRUE)),
  sd = sapply(dem_sat, ~sd(., na.rm=TRUE))
)

print(summary_table)
```

### Example 2: Combine waves for analysis

```r
# Create a single data frame with all waves
all_dem_sat <- tibble(
  wave = rep(names(dem_sat), sapply(dem_sat, length)),
  democracy_sat = unlist(dem_sat),
  obs_id = rep(1:12217, 1),  # Adjust based on actual n per wave
  repeat(1:19798, 1),
  # ... etc for each wave
)

# Better approach: add country/respondent ID from original data
# Load original waves and merge with harmonized data
```

### Example 3: Scale reversals verification

```r
# Waves 1-2 were reversed. Check if this worked:
dem_sat <- harmonized$dem_sat_national

cat("Wave 1 (should be ascending after reversal):\n")
cat("Min:", min(dem_sat$w1, na.rm=T), "\n")
cat("Max:", max(dem_sat$w1, na.rm=T), "\n")
cat("Mean:", mean(dem_sat$w1, na.rm=T), "\n")

cat("\nWave 3 (descending, no reversal):\n")
cat("Min:", min(dem_sat$w3, na.rm=T), "\n")
cat("Max:", max(dem_sat$w3, na.rm=T), "\n")
cat("Mean:", mean(dem_sat$w3, na.rm=T), "\n")

# Means should be similar if reversal worked correctly
```

---

## Data Quality Flags

| Variable | Quality | Valid Data | Issues |
|----------|---------|-----------|--------|
| dem_sat_national | ✅ EXCELLENT | 92.9% | None - ready to use |
| gov_sat_national | ⚠️ POOR | 57.5% | Scale varies, W2 missing 92.5% |
| hh_income_sat | 🚨 CRITICAL | 37.3% | W1/W5/W6 100% missing |

---

## Wave Information

| Wave | Label | N Obs | Years |
|------|-------|-------|-------|
| W1 | Wave 1 | 12,217 | 2005-2006 |
| W2 | Wave 2 | 19,798 | 2010-2012 |
| W3 | Wave 3 | 19,436 | 2014-2016 |
| W4 | Wave 4 | 20,667 | 2016-2019 |
| W5 | Wave 5 | 26,951 | 2019-2021 |
| W6 | Wave 6 | 11,652 | 2021-2023 |

---

## Linking to Original Data

To add country, respondent, and other variables:

```r
# Load harmonized data
harmonized <- readRDS('data/processed/democracy_satisfaction_harmonized.rds')

# Load Wave 3 original data  
library(haven)
w3_original <- read_sav('data/raw/wave3/ABS3 merge20250609.sav')

# Combine: add dem_sat to wave 3
w3_combined <- w3_original %>%
  mutate(
    dem_sat_national = harmonized$dem_sat_national$w3
  )
```

---

## Troubleshooting

**Q: Why are some waves missing NA?**  
A: Missing codes (-1, 0, 7, 8, 9) are automatically converted to NA during harmonization.

**Q: Can I combine all waves into one dataset?**  
A: You can, but you'll lose wave-specific information. Better to keep separate and merge with respondent IDs from original data.

**Q: The gov_sat values are very large (up to 99) - what's wrong?**  
A: Waves 3-5 have a 10-point scale (values 1-10) where the 4-point was expected. Values 97-99 are missing codes. This is documented in HARMONIZATION_RESULTS_SUMMARY.md.

**Q: Why is hh_income_sat mostly missing?**  
A: Source variable names may be incorrect. Verify in the YAML config and wave codebooks.

---

## For More Information

- **Technical details**: See `HARMONIZATION_RESULTS_SUMMARY.md`
- **Configuration**: See `src/config/harmonize/democracy_satisfaction.yml`
- **Script used**: See `src/scripts/harmonize_democracy_satisfaction.R`
- **System docs**: See `src/r/harmonize/README.md`

---

## Contact & Support

For questions about the harmonization process or data quality issues, refer to the harmonization documentation in the `src/r/harmonize/` directory.

