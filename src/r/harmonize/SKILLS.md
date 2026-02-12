# Harmonization Skills

Two companion skills for creating and applying variable harmonization specifications.

## Skill 1: `/create-harmonize-spec`

**Purpose:** Create or update a harmonization YAML specification entry

**Input:** Interactive prompts and/or variable descriptions

**Output:** YAML entry appended to `src/config/harmonize/[domain].yml`

### Usage

```
/create-harmonize-spec economy  # Create in economy.yml
/create-harmonize-spec politics # Create in politics.yml
```

### Interactive Questions

1. **Variable ID**
   - Prompt: "Variable identifier (lowercase, underscores)?"
   - Example: `econ_national_now`

2. **Concept**
   - Prompt: "Concept/domain (economy, politics, society, etc)?"
   - Example: `economy`

3. **Description**
   - Prompt: "Human-readable description?"
   - Example: "Overall national economic condition today"

4. **Wave sources**
   - Prompt: "Source variables by wave (w1: q001, w2: q1, ...)?"
   - Format: "w1: q001, w2: q1, w3: q1, ..."

5. **Variable type**
   - Prompt: "Type? (ordinal/nominal/continuous)"
   - Example: `ordinal`

6. **Target scale** (if ordinal)
   - Prompt: "Min value?"
   - Prompt: "Max value?"
   - Prompt: "Labels? (min: label, 2: label, ..., max: label)"

7. **Missing convention**
   - Prompt: "Missing codes convention?"
   - Options: `treat_as_na`, `treat_as_na_extended`, or custom

8. **Harmonization method**
   - Prompt: "Default method? (identity/r_function)"
   - If `r_function`:
     - Prompt: "Function name? (e.g., safe_reverse_5pt)"
     - Prompt: "Validation patterns? (comma-separated regex patterns)"

9. **Wave-specific rules** (optional)
   - Prompt: "Override method for any waves? (w3, w4, w5, w6)"
   - For each: repeat #8

10. **QC bounds** (optional)
    - Prompt: "Add valid_range_by_wave? (y/n)"
    - If yes, for each wave: "Valid range for [wave]? (e.g., 1-5)"

11. **Tags**
    - Prompt: "Tags? (core, candidate_index:economy, ...)"

### Implementation Strategy

The skill should:

1. **Gather information** via interactive prompts or parse a template
2. **Validate inputs** (variable ID format, valid type, etc.)
3. **Check existing** entries (prevent duplicates)
4. **Generate YAML** block matching format in `economy.yml`
5. **Append to file** (or create if domain file doesn't exist)
6. **Display result** and confirm success

### Template Alternative

User can provide structured input:
```
Variable ID: econ_national_now
Concept: economy
Description: Overall national economic condition today
Source: w1:q001, w2:q1, w3:q1, w4:q1, w5:q1, w6:q1
Type: ordinal
Target Scale: 1-5 (1=Very bad, 2=Bad, 3=So so, 4=Good, 5=Very good)
Missing Convention: treat_as_na
Default Method: identity
Wave Overrides:
  - w3: safe_reverse_5pt, validate: ["econom"]
  - w4: safe_reverse_5pt, validate: ["econom"]
  - w5: safe_reverse_5pt, validate: ["econom"]
  - w6: safe_reverse_5pt, validate: ["econom"]
Valid Ranges:
  - w1: 1-5
  - w2: 1-5
  - w3: 1-5
  - w4: 1-5
  - w5: 1-5
  - w6: 1-5
Tags: core, candidate_index:economy
```

---

## Skill 2: `/harmonize-variables`

**Purpose:** Apply harmonization specifications to data and produce harmonized variables

**Input:** 
- Domain (economy/politics/etc.) or specific YAML file
- Optional: specific variables to harmonize
- Optional: output format preferences

**Output:** 
- R code chunk ready to paste
- OR harmonized data saved to file
- Plus QC report

### Usage

```
/harmonize-variables economy              # All variables in economy.yml

/harmonize-variables economy econ_national_now  # Specific variable

/harmonize-variables politics              # All variables in politics.yml

/harmonize-variables all                   # All domains
```

### Interactive Workflow

1. **Select domain/file**
   - Prompt: "Which domain? (economy/politics/society/...)"
   - Shows available variables in that file

2. **Select variables**
   - Prompt: "Which variables? (all/specific: comma-separated IDs)"

3. **Confirm wave data**
   - Prompt: "Wave data structure? (list named w1,w2,... or separate vars?)"
   - Assumes: `waves <- list(w1 = df1, w2 = df2, ...)`

4. **Output format**
   - Prompt: "Output format? (code-chunk/harmonized-dataframe/bind-cols)"
   - Code chunk: generates R code to paste
   - Dataframe: saves combined result to RDS
   - Bind-cols: shows dplyr::bind_cols() example

5. **QC report**
   - Prompt: "Generate QC report? (y/n)"
   - If yes: shows before/after comparison

### Generated Output

**Option 1: Code Chunk (default)**
```r
# Load functions
source(here::here("src/r/harmonize/_load_harmonize.R"))
source(here::here("src/r/utils/_load_functions.R"))

# Load spec
spec <- yaml::read_yaml("src/config/harmonize/economy.yml")
validate_harmonize_spec(spec)

# Harmonize variables
econ_national_now <- harmonize_variable(
  var_spec = spec$variables[["econ_national_now"]],
  waves = waves,
  missing_conventions = spec$missing_conventions
)

econ_change_1yr <- harmonize_variable(
  var_spec = spec$variables[["econ_change_1yr"]],
  waves = waves,
  missing_conventions = spec$missing_conventions
)

# Combine
harmonized_econ <- dplyr::bind_cols(
  econ_national_now = econ_national_now$w1,
  econ_change_1yr = econ_change_1yr$w1,
  .name_repair = "minimal"
)
```

**Option 2: Harmonized Dataframe**
```r
# [above code runs, then:]

harmonized_econ_full <- bind_cols(
  bind_cols(
    wave = "w1",
    econ_national_now$w1,
    econ_change_1yr$w1
  ),
  bind_cols(
    wave = "w2",
    econ_national_now$w2,
    econ_change_1yr$w2
  ),
  # ... etc for all waves
)

saveRDS(harmonized_econ_full, "data/processed/harmonized_economy.rds")
```

**Option 3: QC Report**
```
Harmonization Report: Economy Domain
================================================================================

Variables harmonized: 3
Total observations: 6,000 (1,000 per wave)

SUMMARY BY VARIABLE:

econ_national_now
  w1: n=1000, valid=995 (99.5%), mean=2.45, range=[1,5]
  w2: n=1000, valid=998 (99.8%), mean=2.38, range=[1,5]
  w3: n=1000, valid=992 (99.2%), mean=2.56, range=[1,5] ⚠️  2 values out of range
  ...

TRANSFORMATIONS APPLIED:
  econ_national_now:
    w3: safe_reverse_5pt() [converted to common scale]
    w4: safe_reverse_5pt()
    w5: safe_reverse_5pt()
    w6: safe_reverse_5pt()

WARNINGS:
  ⚠️  econ_national_now (w3): 2 values outside valid range [1,5]
```

### Implementation Strategy

The skill should:

1. **Validate spec file** exists and is valid
2. **List available variables** with descriptions
3. **Confirm wave data** structure
4. **Load recoding functions** from `src/r/utils/`
5. **Generate code** appropriate to output format
6. **Check recoding functions** exist (validate_all patterns optional)
7. **Show preview** of what will happen
8. **Generate output** (code chunk, data, or both)
9. **Include QC report** option

---

## Implementation Notes

### Shared Infrastructure

Both skills use:
- `validate_harmonize_spec()` - Check YAML structure
- `check_recoding_functions()` - Check function availability
- `report_harmonization()` - Generate reports
- YAML parsing: `yaml::read_yaml()`

### Error Handling

Handle gracefully:
- Missing YAML file
- Invalid specification
- Missing recoding functions
- Non-existent source variables
- Data type mismatches

### User Experience

**For `/create-harmonize-spec`:**
- Show template example
- Warn if variable ID already exists
- Preview YAML before appending
- Suggest related variables (by domain)
- Validate before writing

**For `/harmonize-variables`:**
- Show available variables with descriptions
- Confirm recoding functions before running
- Display before/after summaries
- Warn about scale reversals
- Save intermediate results (optionally)

---

## Testing the Skills

### Test Scenario 1: Create new variable
```
/create-harmonize-spec economy
→ Variable ID: inflation_perception
→ Concept: economy
→ Description: Perception of inflation rate
→ Source: w1:q101, w2:q50, ...
→ Type: ordinal
→ [... continue with prompts ...]
✓ Entry added to src/config/harmonize/economy.yml
```

### Test Scenario 2: Harmonize variables
```
/harmonize-variables economy
→ Select variables: all
→ Output format: code-chunk
→ Generate QC report: yes
→ [Displays code chunk ready to paste]
→ [Shows before/after comparison]
```

### Test Scenario 3: Validate existing spec
```
/harmonize-variables all
→ Checking specifications...
✓ economy.yml: 3 variables, all valid
✓ politics.yml: 5 variables, all valid
→ [Shows summary of available variables]
```
