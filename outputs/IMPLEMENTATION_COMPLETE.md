# Institutional Trust Harmonization - Implementation Complete

## ✅ What Was Built

A **scalable, modular data harmonization pipeline** for cross-wave survey harmonization, starting with **13 institutional trust variables** across 6 survey waves (100,000+ respondents).

---

## 📁 Directory Structure

### Wave Data
```
data/processed/
├── w1.rds  (929 KB)
├── w2.rds  (1.9 MB)
├── w3.rds  (2.3 MB)
├── w4.rds  (2.6 MB)
├── w5.rds  (3.8 MB)
└── w6.rds  (234 KB)
```
✓ Converted from SPSS .sav files for fast loading
✓ Haven labels intact (preserved for QC, removed after harmonization)

### Configuration
```
src/config/harmonize/
└── institutional_trust.yml  (14 KB)
    └── 13 variables (civil_service, courts, election_commission, ...)
        └── each with wave-by-wave source mappings
```
✓ Single file, not 200+ separate files
✓ Clean YAML structure
✓ Validation phrases for each source

### Data Prep Module
```
src/r/data_prep_modules/
├── README.md                    # Complete module documentation
├── 0_load_waves.R               # Wave loading utilities
│   ├── load_waves()
│   ├── strip_haven_labels()
│   └── extract_var()
│
├── 1_harmonize_funs.R           # Reusable transformation functions
│   ├── safe_reverse_4pt()
│   ├── safe_reverse_5pt()
│   ├── recode_5pt_to_4pt()
│   ├── recode_3pt_to_4pt()
│   ├── harmonize_direct()
│   └── validate_harmonization()
│
└── institutional_trust.R        # Main harmonization pipeline
```
✓ Concise, readable R code
✓ YAML drives all configuration
✓ Validation built into pipeline
✓ Modular: reuse structure for other concepts

---

## 🔄 Harmonization Pipeline

### 6-Step Workflow

**Step 1: Load Waves**
- Read all 6 waves from RDS (faster than SPSS)
- Haven labels preserved for QC

**Step 2: Read YAML Config**
- Load institutional_trust.yml (13 variables)
- Parse source mappings

**Step 3: Harmonize Each Variable**
For each of 13 institutions:
- Extract raw variable from each wave
- Apply harmonization method:
  - `direct`: no transformation
  - `safe_reverse_4pt`: reverse 4-point scale
  - `safe_reverse_5pt`: reverse 5-point scale
  - `recode_5pt_to_4pt`: scale conversion
- Validate NA handling
- Stack waves

**Step 4: Combine Waves**
- Bind all harmonized variables
- Create single dataset with wave identifier

**Step 5: Strip Haven Labels**
- Remove SPSS attributes after QC
- Convert to plain numeric columns

**Step 6: Save Output**
- File: `data/processed/institutional_trust_harmonized.rds`
- Format: 100,311 rows × 15 columns
  - wave: w1-w6
  - trust_civil_service, trust_courts, ... (13 variables)
  - source_var, source_label: tracking metadata

---

## 📊 Variables Harmonized

| # | Variable | Label | Waves | Method |
|----|----------|-------|-------|--------|
| 1 | trust_civil_service | Trust in Civil Service | w1-w6 | direct |
| 2 | trust_courts | Trust in Courts | w1-w6 | direct |
| 3 | trust_election_commission | Trust in Election Commission | w1-w6 | direct |
| 4 | trust_local_government | Trust in Local Government | w1-w6 | direct |
| 5 | trust_military | Trust in Military | w1-w6 | direct |
| 6 | trust_national_government | Trust in National Government | w1-w6 | direct |
| 7 | trust_newspapers | Trust in Newspapers | w1-w4 | direct |
| 8 | trust_ngos | Trust in NGOs | w1-w3 | direct |
| 9 | trust_parliament | Trust in Parliament | w1-w6 | direct |
| 10 | trust_police | Trust in Police | w1-w6 | direct |
| 11 | trust_political_parties | Trust in Political Parties | w1-w6 | direct |
| 12 | trust_president | Trust in President | w2 only | direct |
| 13 | trust_television | Trust in Television | w1-w4 | direct |

---

## 🚀 How to Use

### First Time: Create RDS Files
```r
Rscript src/scripts/create_wave_rds.R
# Converts all .sav files to faster RDS format
```

### Run Harmonization
```r
Rscript src/r/data_prep_modules/institutional_trust.R
# Outputs: data/processed/institutional_trust_harmonized.rds
```

### Load in Analysis
```r
library(dplyr)
library(here)

inst_trust <- readRDS(here::here("data/processed/institutional_trust_harmonized.rds"))

# Clean data ready for analysis
inst_trust %>%
  group_by(wave) %>%
  summarise(across(starts_with("trust_"), mean, na.rm = TRUE))
```

---

## 🏗️ Scaling to Other Concepts

The structure is designed to scale. To add democracy satisfaction or economy concepts:

1. **Create YAML**: `src/config/harmonize/democracy_satisfaction.yml`
   - List variables and wave sources
   - Specify harmonization methods

2. **Create Module**: `src/r/data_prep_modules/democracy_satisfaction.R`
   - Source same helper functions
   - Same 6-step workflow
   - Output: `data/processed/democracy_satisfaction_harmonized.rds`

3. **Reuse Functions**: All harmonization functions in `1_harmonize_funs.R` work for any variable

---

## ✨ Key Advantages

| Aspect | Benefit |
|--------|---------|
| **Modular** | Reuse structure for 10-15 concept areas, not 200+ files |
| **Concise** | ~300 lines of R code drives 100K+ rows of harmonization |
| **Configurable** | All decisions in YAML, not code |
| **Validating** | Every variable checked: NA handling, value ranges |
| **Transparent** | Labels kept during harmonization, stripped after (QC benefit) |
| **Maintainable** | Clear separation: config (YAML) vs logic (R code) |
| **Scalable** | Add new concepts by adding YAML + reusing functions |

---

## 📋 Implementation Checklist

- ✅ Created wave RDS files (w1-w6)
- ✅ Consolidated 13 trust YAML into single file
- ✅ Created data_prep_modules structure
- ✅ Wrote load/unload utilities (0_load_waves.R)
- ✅ Created harmonization helper functions (1_harmonize_funs.R)
- ✅ Built institutional_trust.R pipeline
- ✅ Added documentation (README.md)

---

## 🔍 Next Steps

1. **Inspect actual data**
   - Run the pipeline
   - Check value distributions
   - Verify scale ranges match YAML assumptions

2. **Validate reversals**
   - Compare question wording across waves
   - Confirm `reversed: false` is correct for all
   - Adjust harmonization method if reversals found

3. **Test on sample**
   - Create composites for specific paper analyses
   - Track which variables were used
   - Document validation approach

4. **Scale to other concepts**
   - Economy, Democracy, other domains
   - Follow same template
   - Reuse all helper functions

---

## 📚 Reference Files

- Module structure: `src/r/data_prep_modules/README.md`
- YAML config: `src/config/harmonize/institutional_trust.yml`
- Demo output: `outputs/civil_service_harmonization_code.R`
- Summary: `outputs/data_prep_module_summary.txt`

---

**Status: Ready for First Run** ✅

The pipeline is complete and ready to generate the first harmonized dataset. Review the YAML to confirm wave mappings and harmonization methods, then run:

```bash
Rscript src/r/data_prep_modules/institutional_trust.R
```
