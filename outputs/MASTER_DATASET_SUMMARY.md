# Master Harmonized Dataset Report

**Date**: 2026-01-07 21:11:31

## Executive Summary

Successfully extracted and combined all harmonized variables into master datasets.

### Consolidated Variable Count: **15**

### Key Statistics

| Metric | Value |
|--------|-------|
| Concepts | 10 |
| **Consolidated Variables** | **15** |
| Variable-Wave Combinations | 84 |
| Total Data Points (Long Format) | 1397201 |

## Consolidated Variables by Concept

| Concept | Variables | Wave Combinations |
|---------|-----------|------------------|
| authoritarianism_democracy_scale | 1 | 2 |
| community_leader_contact | 1 | 6 |
| democracy_satisfaction | 3 | 16 |
| economy | 3 | 18 |
| government_leader_accountability | 2 | 12 |
| hierarchical_obedience | 1 | 6 |
| local_government_corruption | 1 | 6 |
| national_government_corruption | 1 | 6 |
| strong_leader_preference | 1 | 6 |
| upright_leader_discretion | 1 | 6 |

## Output Datasets

### Wave-Specific Files (Wide Format - Recommended)
- `master_w1.rds` - 12217 rows × 14 columns
- `master_w2.rds` - 19798 rows × 15 columns
- `master_w3.rds` - 19436 rows × 14 columns
- `master_w4.rds` - 20667 rows × 14 columns
- `master_w5.rds` - 26951 rows × 13 columns
- `master_w6.rds` - 1242 rows × 14 columns

### Combined Format
- `master_long_format.rds` - Long format (1397201 rows × 4 columns)
- `master_long_format.csv` - CSV export

### Metadata
- `master_variable_metadata.csv` - Variable definitions

## Complete Variable Listing

### authoritarianism_democracy_scale (1 variables)

- `authoritarianism_democracy_scale_authoritarianism_democracy_scale` (2 waves: w1,w2)

### community_leader_contact (1 variables)

- `community_leader_contact_community_leader_contact` (6 waves: w1,w2,w3,w4,w5,w6)

### democracy_satisfaction (3 variables)

- `democracy_satisfaction_dem_sat_national` (6 waves: w1,w2,w3,w4,w5,w6)
- `democracy_satisfaction_gov_sat_national` (6 waves: w1,w2,w3,w4,w5,w6)
- `democracy_satisfaction_hh_income_sat` (4 waves: w2,w3,w4,w6)

### economy (3 variables)

- `economy_econ_national_now` (6 waves: w1,w2,w3,w4,w5,w6)
- `economy_econ_change_1yr` (6 waves: w1,w2,w3,w4,w5,w6)
- `economy_econ_outlook_1yr` (6 waves: w1,w2,w3,w4,w5,w6)

### government_leader_accountability (2 variables)

- `government_leader_accountability_government_leader_judicial_constraint` (6 waves: w1,w2,w3,w4,w5,w6)
- `government_leader_accountability_government_leader_law_breaking_frequency` (6 waves: w1,w2,w3,w4,w5,w6)

### hierarchical_obedience (1 variables)

- `hierarchical_obedience_hierarchical_obedience` (6 waves: w1,w2,w3,w4,w5,w6)

### local_government_corruption (1 variables)

- `local_government_corruption_local_govt_corruption` (6 waves: w1,w2,w3,w4,w5,w6)

### national_government_corruption (1 variables)

- `national_government_corruption_national_govt_corruption` (6 waves: w1,w2,w3,w4,w5,w6)

### strong_leader_preference (1 variables)

- `strong_leader_preference_strong_leader_preference` (6 waves: w1,w2,w3,w4,w5,w6)

### upright_leader_discretion (1 variables)

- `upright_leader_discretion_upright_leader_discretion` (6 waves: w1,w2,w3,w4,w5,w6)


## Data Structure

### Wave-Specific Datasets (Recommended)
Each wave file contains all available variables for that wave in wide format:
```r
# Load wave-specific data
w1_data <- readRDS('outputs/master_w1.rds')
# Each column is a consolidated variable
# Each row is a respondent
```

### Long Format
Alternative stacked format with columns:
- `variable` - variable name
- `wave` - wave (w1-w6)
- `row_id` - respondent ID
- `value` - variable value

## Usage Examples

```r
# Load and inspect
w1 <- readRDS('outputs/master_w1.rds')
dim(w1)  # Check dimensions
names(w1)  # List variables

# Cross-wave analysis
w1_vars <- readRDS('outputs/master_w1.rds')
w2_vars <- readRDS('outputs/master_w2.rds')

# Get specific variable across waves
econ_w1 <- w1_vars$economy_econ_national_now
econ_w2 <- w2_vars$economy_econ_national_now
```

---

**Report Generated**: 2026-01-07 21:11:31
**Total Consolidated Variables: 15**

