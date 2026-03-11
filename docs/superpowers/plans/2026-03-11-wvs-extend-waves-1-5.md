# WVS Extend to Waves 1-5 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend WVS harmonization from W6-W7 to W1-W7, adding ~260k respondents across 5 new waves (1981-2009).

**Architecture:** Add W1-W5 .sav loading to the existing wave loader, add w1-w5 source entries to all 11 YAML specs, update the final dataset script to handle heterogeneous country identifiers (ISO alpha in W1/W4, ISO numeric in W2/W3/W5). No changes to the shared harmonization engine — it already handles null sources.

**Tech Stack:** R (haven for .sav, arrow for parquet, countrycode for ISO conversion, dplyr/yaml for pipeline)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `src/r/data_prep_modules/wvs/0_load_waves.R` | Modify | Add W1-W5 .sav loading alongside W6-W7 parquet |
| `src/config/wvs/harmonize/institutional_trust.yml` | Modify | Add w1-w5 source entries for 19 trust variables |
| `src/config/wvs/harmonize/social_trust.yml` | Modify | Add w1-w5 source entries for 7 trust variables |
| `src/config/wvs/harmonize/democratic_attitudes.yml` | Modify | Add w1-w5 source entries (mostly null) |
| `src/config/wvs/harmonize/democratic_support.yml` | Modify | Add w1-w5 source entries for 5 variables |
| `src/config/wvs/harmonize/life_satisfaction.yml` | Modify | Add w1-w5 source entries (full coverage) |
| `src/config/wvs/harmonize/political_engagement.yml` | Modify | Add w1-w5 source entries |
| `src/config/wvs/harmonize/political_action.yml` | Modify | Add w1-w5 source entries (full coverage W1-W5) |
| `src/config/wvs/harmonize/media_consumption.yml` | Modify | Add w1-w5 as null (incompatible scales) |
| `src/config/wvs/harmonize/national_identity.yml` | Modify | Add w1-w5 source entries (full coverage) |
| `src/config/wvs/harmonize/demographics.yml` | Modify | Add w1-w5 source entries + wave-specific education recodes |
| `src/config/wvs/harmonize/weight.yml` | Modify | Add w1-w5 weight variables |
| `src/r/data_prep_modules/wvs/99_create_final_dataset.R` | Modify | Handle W1-W5 country IDs, expand master file glob |
| `src/r/utils/recoding.R` | Modify | Add `recode_marital_w4w5()` for extra marital codes |

---

## Task 1: Update Wave Loader (0_load_waves.R)

**Files:**
- Modify: `src/r/data_prep_modules/wvs/0_load_waves.R`

- [ ] **Step 1: Replace `0_load_waves.R` with version supporting W1-W7**

The new loader handles W1-W5 as .sav (via haven) and W6-W7 as parquet (existing behavior).

```r
# WVS: Load wave data
# W1-W5: SPSS .sav files via haven
# W6-W7: Apache Parquet files via arrow

library(here)

load_wvs_waves <- function() {

  # W1-W5: SPSS .sav files
  sav_waves <- list(
    w1 = here("data", "wvs", "raw", "wave1", "WV1_Data_spss_v20200208.sav"),
    w2 = here("data", "wvs", "raw", "wave2", "WV2_Data_Spss_v20180912.sav"),
    w3 = here("data", "wvs", "raw", "wave3", "WV3_Data_Spss_v20180912.sav"),
    w4 = here("data", "wvs", "raw", "wave4", "WV4_Data_spss_v20201117.sav"),
    w5 = here("data", "wvs", "raw", "wave5", "WV5_Data_Spss_v20180912.sav")
  )

  # W6-W7: Parquet files
  parquet_waves <- list(
    w6 = here("data", "wvs", "raw", "wave6", "wvs_wave6.parquet"),
    w7 = here("data", "wvs", "raw", "wave7", "wvs_wave7.parquet")
  )

  waves <- list()

  # Load .sav waves
  for (wave_name in names(sav_waves)) {
    path <- sav_waves[[wave_name]]
    cat(sprintf("Loading %s from %s ... ", wave_name, basename(path)))
    df <- haven::read_sav(path, encoding = "latin1")
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n",
                format(nrow(df), big.mark = ","), ncol(df)))
  }

  # Load parquet waves
  for (wave_name in names(parquet_waves)) {
    path <- parquet_waves[[wave_name]]
    cat(sprintf("Loading %s from %s ... ", wave_name, basename(path)))
    df <- arrow::read_parquet(path)
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n",
                format(nrow(df), big.mark = ","), ncol(df)))
  }

  cat(sprintf("\nLoaded %d WVS waves\n", length(waves)))
  waves
}
```

- [ ] **Step 2: Verify loader works**

Run: `Rscript -e "source('src/r/data_prep_modules/wvs/0_load_waves.R'); w <- load_wvs_waves(); cat(names(w))"`
Expected: `w1 w2 w3 w4 w5 w6 w7` printed, with row counts for all 7 waves.

- [ ] **Step 3: Commit**

```bash
git add src/r/data_prep_modules/wvs/0_load_waves.R
git commit -m "feat: Extend WVS wave loader to W1-W7 (add .sav loading for W1-W5)"
```

---

## Task 2: Add Marital Status Recode Function

**Files:**
- Modify: `src/r/utils/recoding.R`

W4 marital_status has extra codes (7=combined divorced/sep/widow, 10=living apart) and W5 has (7=combined, 8=living apart). These need collapsing to the standard 1-6 scheme.

- [ ] **Step 1: Add `recode_marital_w4w5()` to recoding.R**

Append after `recode_gender_binary` (around line 1611):

```r
recode_marital_w4w5 <- function(x,
                                data = NULL,
                                var_name = NULL,
                                missing_codes = c(-5, -4, -3, -2, -1),
                                validate_all = NULL) {
  dplyr::case_when(
    x %in% missing_codes ~ NA_real_,
    x %in% 1:6 ~ as.numeric(x),  # Standard codes pass through
    x == 7 ~ 3,                    # Combined divorced/separated/widow → Divorced
    x == 8 ~ 4,                    # Living apart → Separated
    x == 10 ~ 4,                   # Living apart (W4 code) → Separated
    TRUE ~ NA_real_
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/r/utils/recoding.R
git commit -m "feat: Add recode_marital_w4w5() for WVS W4/W5 extra marital codes"
```

---

## Task 3: Update YAML Specs — Institutional Trust

**Files:**
- Modify: `src/config/wvs/harmonize/institutional_trust.yml`

Add w1-w5 source entries to all 19 variables. The mapping (from codebook research):

| Variable | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| trust_churches | V135 | V272 | V135 | V147 | V131 |
| trust_armed_forces | V136 | V273 | V136 | V148 | V132 |
| trust_press | V138 | V276 | V138 | V149 | V133 |
| trust_television | null | V283 | V139 | V150 | V134 |
| trust_labor_unions | V140 | V277 | V140 | V151 | V135 |
| trust_police | V141 | V278 | V141 | V152 | V136 |
| trust_courts | V137 | V275 | V137 | null | V137 |
| trust_government | null | V289 | V142 | V153 | V138 |
| trust_political_parties | null | V285 | V143 | V154 | V139 |
| trust_parliament | V144 | V279 | V144 | V155 | V140 |
| trust_civil_service | V145 | V280 | V145 | V156 | V141 |
| trust_universities | null | null | null | null | null |
| trust_elections | null | null | null | null | null |
| trust_major_companies | V146 | V281 | V146 | V157 | V142 |
| trust_banks | null | null | null | null | null |
| trust_environmental_orgs | null | null | V147 | V158 | V143 |
| trust_womens_orgs | null | null | V148 | V159 | V144 |
| trust_charitable_orgs | null | null | null | null | V145 |
| trust_united_nations | null | null | V150 | V162 | V147 |

- [ ] **Step 1: Add w1-w5 source entries to each variable's source block**

For each variable, change:
```yaml
    source:
      w6: V108
      w7: Q64
```
To:
```yaml
    source:
      w1: V135
      w2: V272
      w3: V135
      w4: V147
      w5: V131
      w6: V108
      w7: Q64
```

Use `null` for waves where the variable doesn't exist. All W1-W5 trust items use the same 1-4 scale (1=A great deal → 4=None at all) as W6, so the existing `safe_reverse_4pt` default applies without wave-specific overrides.

Update the header comment from "Waves 6-7" to "Waves 1-7".

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/institutional_trust.yml
git commit -m "feat: Add W1-W5 source mappings to WVS institutional trust spec"
```

---

## Task 4: Update YAML Specs — Social Trust

**Files:**
- Modify: `src/config/wvs/harmonize/social_trust.yml`

| Variable | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| trust_generalized_binary | V27 | V94 | V27 | V25 | V23 |
| trust_family | null | null | null | null | V125 |
| trust_neighborhood | null | null | null | null | V126 |
| trust_people_personally | null | null | null | null | V127 |
| trust_first_time | null | null | null | null | V128 |
| trust_another_religion | null | null | null | null | V129 |
| trust_another_nationality | null | null | null | null | V130 |

- [ ] **Step 1: Add w1-w5 source entries**

trust_generalized_binary is available in all waves (same 1=trusted/2=careful binary). Interpersonal trust items (family through nationality) only start at W5 with the same 1-4 scale as W6-W7.

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/social_trust.yml
git commit -m "feat: Add W1-W5 source mappings to WVS social trust spec"
```

---

## Task 5: Update YAML Specs — Democratic Attitudes

**Files:**
- Modify: `src/config/wvs/harmonize/democratic_attitudes.yml`

| Variable | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| dem_importance_democracy | null | null | null | null | V162 |
| dem_how_democratic | null | null | null | null | V163 |
| dem_satisfaction_political_system | null | null | null | null | null |

- [ ] **Step 1: Add w1-w5 source entries**

dem_importance_democracy and dem_how_democratic start at W5 (same 1-10 scale, identity method). dem_satisfaction_political_system remains W7 only.

**DAG paper note:** Gap construction requires both dem_importance_democracy and dem_how_democratic, so the WVS gap score is W5-W7 only. This is by design — the null entries for W1-W4 ensure gap construction returns NA for those waves.

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/democratic_attitudes.yml
git commit -m "feat: Add W1-W5 source mappings to WVS democratic attitudes spec"
```

---

## Task 6: Update YAML Specs — Democratic Support

**Files:**
- Modify: `src/config/wvs/harmonize/democratic_support.yml`

| Variable | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| dem_strong_leader | null | null | V154 | V164 | V148 |
| dem_experts_rule | null | null | V155 | V165 | V149 |
| dem_army_rule | null | null | V156 | V166 | V150 |
| dem_democratic_system | null | null | V157 | V167 | V151 |
| dem_religious_law | null | null | null | null | null |

- [ ] **Step 1: Add w1-w5 source entries**

W3-W5 use same 1-4 scale (1=Very good → 4=Very bad) as W6. Same `safe_reverse_4pt` applies. dem_religious_law stays W7 only (W5's V153 is 1-10 scale, incompatible).

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/democratic_support.yml
git commit -m "feat: Add W1-W5 source mappings to WVS democratic support spec"
```

---

## Task 7: Update YAML Specs — Life Satisfaction

**Files:**
- Modify: `src/config/wvs/harmonize/life_satisfaction.yml`

| Variable | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| happiness | V10 | V18 | V10 | V11 | V10 |
| life_satisfaction | V65 | V96 | V65 | V81 | V22 |

- [ ] **Step 1: Add w1-w5 source entries**

Both available in all waves. happiness is 1-4 (same reverse), life_satisfaction is 1-10 (identity). Same methods apply.

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/life_satisfaction.yml
git commit -m "feat: Add W1-W5 source mappings to WVS life satisfaction spec"
```

---

## Task 8: Update YAML Specs — Political Engagement

**Files:**
- Modify: `src/config/wvs/harmonize/political_engagement.yml`

| Variable | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| pol_interest | V117 | V241 | V117 | V133 | V95 |
| pol_discuss_friends | V37 | V10 | V37 | V32 | null |

- [ ] **Step 1: Add w1-w5 source entries**

pol_interest: all waves, same 1-4 scale, same `safe_reverse_4pt`.
pol_discuss_friends: W1-W4 available (same 1-3 scale, same `safe_reverse_3pt`), W5 null. Update the note — it was previously listed as W7-only but actually W1-W4 + W7.

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/political_engagement.yml
git commit -m "feat: Add W1-W5 source mappings to WVS political engagement spec"
```

---

## Task 9: Update YAML Specs — Political Action

**Files:**
- Modify: `src/config/wvs/harmonize/political_action.yml`

| Variable | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| action_petition | V118 | V242 | V118 | V134 | V96 |
| action_boycotts | V119 | V243 | V119 | V135 | V97 |
| action_demonstrations | V120 | V244 | V120 | V136 | V98 |
| action_strikes | V121 | V245 | V121 | V137 | null |
| action_other_protest | null | null | null | null | V99 |

- [ ] **Step 1: Add w1-w5 source entries**

All use same 1-3 scale (1=Have done → 3=Would never), same `safe_reverse_3pt`. action_strikes drops in W5, action_other_protest appears in W5.

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/political_action.yml
git commit -m "feat: Add W1-W5 source mappings to WVS political action spec"
```

---

## Task 10: Update YAML Specs — Media Consumption

**Files:**
- Modify: `src/config/wvs/harmonize/media_consumption.yml`

- [ ] **Step 1: Add w1-w5 as null for all 9 variables**

W1-W4 have no comparable per-medium items. W5 uses a binary (1/2) scale incompatible with W6's 1-5 frequency scale. Set all w1-w5 to null.

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/media_consumption.yml
git commit -m "feat: Add W1-W5 source mappings to WVS media consumption spec (all null — incompatible scales)"
```

---

## Task 11: Update YAML Specs — National Identity

**Files:**
- Modify: `src/config/wvs/harmonize/national_identity.yml`

| Variable | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| national_pride | V205 | V322 | V205 | V216 | V209 |

- [ ] **Step 1: Add w1-w5 source entries**

Same 1-4 scale + code 5 (not a national) → NA. Same recode mapping applies.

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/national_identity.yml
git commit -m "feat: Add W1-W5 source mappings to WVS national identity spec"
```

---

## Task 12: Update YAML Specs — Demographics

**Files:**
- Modify: `src/config/wvs/harmonize/demographics.yml`

| Variable | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| sex | V214 | V353 | V214 | V223 | V235 |
| age | V216 | V355 | V216 | V225 | V237 |
| education_level | null | V375 | V217 | V226 | V238 |
| income_scale | V227 | V363 | V227 | V236 | V253 |
| social_class | null | null | V226 | V235 | V252 |
| marital_status | V89 | V181 | V89 | V106 | V55 |
| employment_status | V220 | V358 | V220 | V229 | V241 |

- [ ] **Step 1: Add w1-w5 source entries with wave-specific overrides**

Key notes:
- **W1 education_level**: null (no categorical attainment variable exists)
- **W1 social_class**: null (only 3-level, incompatible with 5-level scale)
- **W2 social_class**: null (variable doesn't exist)
- **education_level W2-W5**: All use 1-9 scale (same as W6 V248), so W6's recode mapping applies. Add by_wave entries for w2-w5 using the same mapping as w6.
- **social_class W3-W5**: Same 1=Upper → 5=Lower as W6, so `safe_reverse_5pt` default applies.
- **marital_status W4/W5**: Need `recode_marital_w4w5` to collapse extra codes (7, 8, 10).
- **sex, age, income_scale, employment_status**: identity method, same across all waves.

```yaml
# education_level by_wave additions:
        w2:
          method: recode
          mapping:
            1: 1
            2: 1
            3: 1
            4: 2
            5: 2
            6: 2
            7: 2
            8: 3
            9: 3
          note: "W2 V375: same 1-9 scheme as W6"
        w3:
          method: recode
          mapping: {1: 1, 2: 1, 3: 1, 4: 2, 5: 2, 6: 2, 7: 2, 8: 3, 9: 3}
          note: "W3 V217: same 1-9 scheme as W6"
        w4:
          method: recode
          mapping: {1: 1, 2: 1, 3: 1, 4: 2, 5: 2, 6: 2, 7: 2, 8: 3, 9: 3}
          note: "W4 V226: same 1-9 scheme as W6"
        w5:
          method: recode
          mapping: {1: 1, 2: 1, 3: 1, 4: 2, 5: 2, 6: 2, 7: 2, 8: 3, 9: 3}
          note: "W5 V238: same 1-9 scheme as W6"
```

```yaml
# marital_status by_wave additions:
        w4:
          method: r_function
          fn: recode_marital_w4w5
          note: "W4 V106 has extra codes 7 (combined) and 10 (living apart)"
        w5:
          method: r_function
          fn: recode_marital_w4w5
          note: "W5 V55 has extra codes 7 (combined) and 8 (living apart)"
```

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/demographics.yml
git commit -m "feat: Add W1-W5 source mappings to WVS demographics spec"
```

---

## Task 13: Update YAML Specs — Weight

**Files:**
- Modify: `src/config/wvs/harmonize/weight.yml`

| Variable | W1 | W2 | W3 | W4 | W5 |
|---|---|---|---|---|---|
| weight | V236 | V376 | V236 | V245 | V259 |

- [ ] **Step 1: Add w1-w5 source entries**

All identity method, continuous. Increase valid_range max from 25 to 35 (W4 weights go up to ~32).

- [ ] **Step 2: Commit**

```bash
git add src/config/wvs/harmonize/weight.yml
git commit -m "feat: Add W1-W5 source mappings to WVS weight spec"
```

---

## Task 14: Update Final Dataset Script (99_create_final_dataset.R)

**Files:**
- Modify: `src/r/data_prep_modules/wvs/99_create_final_dataset.R`

Changes needed:
1. Expand master file glob from `w[67]` to `w[1-7]`
2. Handle country identifiers per-wave:
   - W1: `COUNTRY_ISO` column from .sav (ISO alpha-3 directly)
   - W2: `V2` column (ISO 3166 numeric) → convert via `countrycode`
   - W3: `V2` column (ISO 3166 numeric) → convert via `countrycode`
   - W4: `B_COUNTRY_ALPHA` column from .sav (ISO alpha-3 directly)
   - W5: `V2` column (ISO 3166 numeric) → convert via `countrycode`
   - W6-W7: `B_COUNTRY_ALPHA` from parquet (existing behavior)

- [ ] **Step 1: Rewrite 99_create_final_dataset.R**

Key changes:

```r
# Line 23: expand glob
wave_files <- sort(list.files(output_dir, pattern = "^master_w[1-7]\\.rds$", full.names = TRUE))

# Lines 44-63: replace country extraction block with per-wave logic
cat("\nAdding country identifiers...\n")

# Define country source per wave
country_sources <- list(
  w1 = list(file = here("data", "wvs", "raw", "wave1", "WV1_Data_spss_v20200208.sav"),
            type = "sav", col = "COUNTRY_ISO", format = "iso3c"),
  w2 = list(file = here("data", "wvs", "raw", "wave2", "WV2_Data_Spss_v20180912.sav"),
            type = "sav", col = "V2", format = "iso3n"),
  w3 = list(file = here("data", "wvs", "raw", "wave3", "WV3_Data_Spss_v20180912.sav"),
            type = "sav", col = "V2", format = "iso3n"),
  w4 = list(file = here("data", "wvs", "raw", "wave4", "WV4_Data_spss_v20201117.sav"),
            type = "sav", col = "B_COUNTRY_ALPHA", format = "iso3c"),
  w5 = list(file = here("data", "wvs", "raw", "wave5", "WV5_Data_Spss_v20180912.sav"),
            type = "sav", col = "V2", format = "iso3n"),
  w6 = list(file = here("data", "wvs", "raw", "wave6", "wvs_wave6.parquet"),
            type = "parquet", col = "B_COUNTRY_ALPHA", format = "iso3c"),
  w7 = list(file = here("data", "wvs", "raw", "wave7", "wvs_wave7.parquet"),
            type = "parquet", col = "B_COUNTRY_ALPHA", format = "iso3c")
)

for (wave_name in names(wave_list)) {
  src <- country_sources[[wave_name]]

  # Read country column from raw data
  if (src$type == "parquet") {
    raw <- arrow::read_parquet(src$file, col_select = src$col)
    country_raw <- raw[[src$col]]
  } else {
    raw <- haven::read_sav(src$file, col_select = src$col, encoding = "latin1")
    country_raw <- as.numeric(haven::zap_labels(raw[[src$col]]))
    # For alpha columns, keep as character
    if (src$format == "iso3c") {
      country_raw <- as.character(haven::as_factor(raw[[src$col]]))
    }
  }

  # Convert to ISO alpha-3 if needed
  if (src$format == "iso3n") {
    country <- countrycode::countrycode(country_raw, origin = "iso3n",
                                         destination = "iso3c", warn = FALSE)
  } else {
    country <- country_raw
  }

  if (length(country) != nrow(wave_list[[wave_name]])) {
    warning(sprintf("Row count mismatch for %s: master=%d, raw=%d",
                    wave_name, nrow(wave_list[[wave_name]]), length(country)))
  } else {
    wave_list[[wave_name]]$country <- country
    n_countries <- length(unique(na.omit(country)))
    cat(sprintf("  %s: %d countries\n", wave_name, n_countries))
  }
}
```

Also add `library(countrycode)` to the imports at top.

- [ ] **Step 2: Verify script runs end-to-end**

Run: `Rscript src/r/data_prep_modules/wvs/99_create_final_dataset.R`
Expected: 7 waves loaded, ~446k total rows, country codes present for all waves.

- [ ] **Step 3: Commit**

```bash
git add src/r/data_prep_modules/wvs/99_create_final_dataset.R
git commit -m "feat: Update WVS final dataset script for W1-W7 with heterogeneous country IDs"
```

---

## Task 15: Run Full Pipeline and Validate

- [ ] **Step 1: Run harmonization pipeline**

```bash
Rscript src/r/data_prep_modules/wvs/2_harmonize_all.R
```

Expected: 7 waves loaded, 11 specs processed, 61 variables, master files saved for w1-w7.

- [ ] **Step 2: Run final dataset creation**

```bash
Rscript src/r/data_prep_modules/wvs/99_create_final_dataset.R
```

Expected: ~446k rows, ~63 columns, 7 waves.

- [ ] **Step 3: Validate output**

```r
Rscript -e "
d <- readRDS('data/processed/wvs_harmonized.rds')
cat('Total:', nrow(d), 'rows,', ncol(d), 'cols\n\n')

# Wave counts
print(table(d\$wave))

# Countries per wave
library(dplyr)
d %>% group_by(wave) %>%
  summarise(n=n(), countries=n_distinct(country, na.rm=TRUE)) %>%
  print()

# Key variable coverage
vars <- c('trust_churches', 'trust_government', 'dem_importance_democracy',
          'dem_strong_leader', 'happiness', 'pol_interest', 'action_petition',
          'national_pride', 'education_level')
for (v in vars) {
  tab <- table(d\$wave, !is.na(d[[v]]))
  cat('\n', v, ':\n')
  print(tab)
}
"
```

Validate:
- trust_churches: non-NA in W1-W7
- trust_government: non-NA in W2-W7, all NA in W1
- dem_importance_democracy: non-NA in W5-W7, all NA in W1-W4
- dem_strong_leader: non-NA in W3-W7, all NA in W1-W2
- happiness, pol_interest, action_petition, national_pride: non-NA in W1-W7
- education_level: non-NA in W2-W7, all NA in W1

- [ ] **Step 4: Commit final output**

```bash
git add data/processed/wvs_harmonized.rds data/processed/wvs_harmonized.parquet
git commit -m "feat: WVS harmonized dataset extended to W1-W7 (~447k respondents, 7 waves)"
```

---

## Task 16: Update CLAUDE.md Documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update WVS section**

Update the WVS status line, respondent count, wave count, and variable coverage table. Note that the effective sample for the DAG paper gap score is W5-W7 only.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: Update CLAUDE.md for WVS W1-W7 extension"
```
