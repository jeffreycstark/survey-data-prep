# Democracy Satisfaction Harmonization Results

**Execution Date**: 2026-01-07  
**Status**: ✅ Complete (with data quality alerts)

## Executive Summary

Successfully harmonized 3 satisfaction variables across 6 waves of the Asian Barometer Survey. The process revealed important data quality issues that require review and possible manual adjustment.

## Variables Harmonized

### 1. Democracy Satisfaction (dem_sat_national) ✅ EXCELLENT

**Status**: Cleanly harmonized with high data quality

**Waves**: All 6 waves (W1-W6)

**Scale**: 4-point ordinal (1=Not at all satisfied → 4=Very satisfied)

**Data Quality**:
| Wave | N Obs | Valid | Missing | % Missing | Mean | SD |
|------|-------|-------|---------|-----------|------|-----|
| W1 | 12,217 | 11,313 | 904 | 7.4% | 2.26 | 0.72 |
| W2 | 19,798 | 17,963 | 1,835 | 9.3% | 2.18 | 0.73 |
| W3 | 19,436 | 18,496 | 940 | 4.8% | 2.22 | 0.73 |
| W4 | 20,667 | 18,998 | 1,669 | 8.1% | 2.25 | 0.71 |
| W5 | 26,951 | 24,885 | 2,066 | 7.7% | 2.22 | 0.71 |
| W6 | 11,652 | 11,314 | 338 | 2.9% | 2.24 | 0.76 |

**Harmonization Actions**:
- W1-W2: Reversed scale (ascending → descending) using `safe_reverse_4pt()`
- W3-W6: Identity pass-through (already descending)

**Quality Notes**:
- ✅ Consistent scale across all waves
- ✅ Consistent means (~2.2) indicating similar response patterns
- ✅ Low missing data (2.9%-9.3%)
- ✅ Reversals successfully applied for waves 1-2

---

### 2. Government Satisfaction (gov_sat_national) ⚠️ SCALE MISMATCH ALERT

**Status**: Harmonized but with significant data quality issues

**Waves**: All 6 waves (W1-W6)

**Scale Issues**:
- W1: 5-point scale (includes "Half and Half" option)
- W2: 4-point scale
- W3-W5: **10-point scale** (values 1-10 plus missing codes 97, 98, 99)
- W6: 4-point scale

**Data Quality**:
| Wave | N Obs | Valid | Missing | % Missing | Mean | Range | Notes |
|------|-------|-------|---------|-----------|------|-------|-------|
| W1 | 12,217 | 8,731 | 3,486 | 28.5% | 2.48 | 1-5 | 5-point scale |
| W2 | 19,798 | 1,488 | 18,310 | **92.5%** | 1.98 | 1-4 | ⚠️ Mostly missing |
| W3 | 19,436 | 11,562 | 7,874 | 40.5% | 17.5 | 1-99 | ⚠️ 10-point scale |
| W4 | 20,667 | 13,011 | 7,656 | 37.0% | 19.8 | 1-99 | ⚠️ 10-point scale |
| W5 | 26,951 | 17,868 | 9,083 | 33.7% | 19.9 | 1-99 | ⚠️ 10-point scale |
| W6 | 11,652 | 11,015 | 637 | 5.5% | 2.44 | 1-4 | 4-point scale |

**Critical Issues**:
1. **Wave 2 data loss**: 92.5% missing - possible variable mismatch or data collection issue
2. **Scale inconsistency (W3-W5)**: 10-point scale vs. expected 4-point scale
3. **Reversal status uncertain**: W2 may need reversal relative to W3-W5

**Recommendation**:
- ⚠️ **MANUAL REVIEW REQUIRED** - Verify source variable names in waves 2-5
- Consider collapse transformation (10-point → 4-point) for W3-W5
- Investigate W2 missing data (92.5% loss suggests wrong variable)

---

### 3. Household Income Satisfaction (hh_income_sat) 🚨 CRITICAL ISSUES

**Status**: Partial harmonization with severe data quality problems

**Waves**: Only W2-W4 have usable data; W1, W5, W6 completely missing

**Scale**: 4-point ordinal (when available)

**Data Quality**:
| Wave | N Obs | Valid | Missing | % Missing | Mean | Status |
|------|-------|-------|---------|-----------|------|--------|
| W1 | 12,217 | 0 | 12,217 | **100%** | NaN | ❌ No data |
| W2 | 19,798 | 18,356 | 1,442 | 7.3% | 2.22 | ✅ Good |
| W3 | 19,436 | 12,140 | 7,296 | 37.5% | 2.42 | ⚠️ Partial |
| W4 | 20,667 | 10,795 | 9,872 | 47.8% | 2.08 | ⚠️ Partial |
| W5 | 26,951 | 0 | 26,951 | **100%** | NaN | ❌ No data |
| W6 | 11,652 | 0 | 11,652 | **100%** | NaN | ❌ No data |

**Critical Issues**:
1. **W1**: Source variable `se9a` not found (100% missing)
2. **W5**: Source variable `se9a` not found (100% missing)
3. **W6**: Source variable `SE14a` not found (100% missing)
4. **W3-W4**: Only partial data available (37.5%-47.8% missing)

**Recommendation**:
- 🚨 **CRITICAL REVIEW REQUIRED** - Source variable names may be incorrect
- Search for alternative variable names (e.g., `se_9a`, `se9b`, `income_sat`)
- Verify variable availability in wave datasets
- Consider whether this variable is compatible across all 6 waves

---

## Data Files Generated

### Harmonized Data
- **Location**: `data/processed/democracy_satisfaction_harmonized.rds`
- **Format**: R RDS (preserves structure and attributes)
- **Structure**: Named list with 3 elements
  ```r
  harmonized <- list(
    dem_sat_national = list(w1=vector, w2=vector, ..., w6=vector),
    gov_sat_national = list(w1=vector, w2=vector, ..., w6=vector),
    hh_income_sat = list(w1=vector, w2=vector, ..., w6=vector)
  )
  ```

### Summary Report
- **Location**: `outputs/democracy_satisfaction_harmonization_summary.txt`
- **Contents**: Wave-by-wave statistics for each variable

---

## Next Steps

### Immediate Actions
1. ✅ **dem_sat_national**: Ready for analysis - excellent data quality
2. ⚠️ **gov_sat_national**: 
   - Verify source variables in YAML config
   - Determine appropriate collapse function (10-point → 4-point)
   - Investigate W2 data loss
3. 🚨 **hh_income_sat**:
   - Search codebook for correct variable names (W1, W5, W6)
   - Verify variable exists in SPSS files
   - Consider whether variable is truly comparable across waves

### Recommended Improvements
1. Update YAML spec with findings
2. Add data quality flags to each variable
3. Create separate harmonization spec for 10-point variables
4. Document variable mapping decisions
5. Test with subset of data for validation

---

## Technical Details

**Configuration**: `src/config/harmonize/democracy_satisfaction.yml`

**System**: Cross-wave harmonization using R with:
- `safe_reverse_4pt()` for scale reversals
- Missing code handling (-1, 0, 7, 8, 9)
- QC validation of valid ranges
- Detailed reporting per wave

**Execution Time**: ~30 seconds for 6 waves, 110,000+ observations

---

## Appendix: Missing Code Convention

Standard missing codes treated as NA across all waves:
- -1: Refusal
- 0: No answer
- 7: Not applicable
- 8: Don't know
- 9: Missing

*Note: Waves 3-5 also use 97, 98, 99 codes for some variables*

