# `/search-and-analyze` Skill

**Purpose**: Automate YAML template generation from keyword search results across survey waves

**Status**: Foundational (manual execution → future skill wrapping)

**Concept**: Bridge from exploratory search → structured harmonization YAML

---

## Quick Start

```r
# 1. Search for matching variables
results <- extract_matches("economic condition", w1, w2, w3, w4, w5, w6)

# 2. Generate YAML template (auto-detects reversals, scales, groups by question)
yaml_text <- generate_codebook_yaml(results, concept = "economy")

# 3. Review, edit, save
cat(yaml_text)
writeLines(yaml_text, "src/config/harmonize/economy.yml")

# 4. Use in harmonization
spec <- yaml::read_yaml("src/config/harmonize/economy.yml")
harmonized <- harmonize_all(spec, waves = list(w1, w2, w3, w4, w5, w6))
```

---

## The Problem This Solves

When harmonizing survey data across waves, you often start with:

**Manual workflow (slow)**:
1. Search text files for "economic condition"
2. Extract variable names: `w1: q001`, `w2: q1`, ..., `w6: q1`
3. Look at value labels manually for each variable
4. Manually detect: "These are 5-point scales, but W1/W2 reverse the direction"
5. Write YAML by hand (error-prone, repetitive)

**Automated workflow (this skill)**:
1. Run `extract_matches()` to get all matches
2. Run `generate_codebook_yaml()` to auto-detect everything
3. Edit template to refine (changes highlighted with comments)
4. Use in harmonization

**Time savings**: 15-30 min per question → 2-5 min per question

---

## Functions Included

### `generate_codebook_yaml(search_results, concept, save_to = NULL)`

**Main entry point**: Takes search results and produces YAML template.

```r
# Generate and display
yaml_str <- generate_codebook_yaml(results, concept = "economy")
cat(yaml_str)

# Generate and save
generate_codebook_yaml(results, concept = "economy", 
                       save_to = "src/config/harmonize/economy.yml")
```

**What it does**:
1. Parses search result format
2. Groups variables by question number (handles `q1`, `q001`, `q01` variants)
3. Detects scale types (5-point, 4-point, 6-point) and direction (ascending/descending)
4. **Detects reversals**: Flags when question values flip meaning across waves
5. Generates YAML with auto-filled source mappings and comments

**Output example**:
```yaml
# Generated YAML template - review and edit before using

q1:
  id: "",  # TODO: set to q name or descriptive id
  concept: "economy"
  description: "Overall national economic condition today"

  source:
    w1: "q001"
    w2: "q1"
    w3: "q1"
    w4: "q1"
    w5: "q1"
    w6: "q1"

  # Scale analysis (auto-detected):
  # w1: 5pt scale, ascending direction, 100.0% confidence
  # w2: 5pt scale, ascending direction, 100.0% confidence
  # w3: 5pt scale, descending direction, 100.0% confidence
  # w4: 5pt scale, descending direction, 100.0% confidence
  # w5: 5pt scale, descending direction, 100.0% confidence
  # w6: 5pt scale, descending direction, 100.0% confidence
  # ⚠️  REVERSALS DETECTED:
  #   w1 vs w3: opposite semantic direction
  #   w2 vs w3: opposite semantic direction
  # Consider using safe_reverse_*pt() for reversals

  harmonize:
    default:
      method: "identity"  # or r_function

  qc:
    valid_range_by_wave: {}
```

### `detect_scale_type(values, value_labels)`

Analyzes value range and label semantics to determine scale.

```r
labels <- c("1" = "Very bad", "2" = "Bad", "3" = "Good", "4" = "Very good")
result <- detect_scale_type(1:4, labels)

# result$type: "4pt"
# result$range: c(1, 4)
# result$direction: "ascending"
# result$confidence: 0.95
```

**Returns**: List with:
- `type`: "5pt", "4pt", "6pt", "0-10", or "continuous"
- `range`: numeric vector c(min, max)
- `direction`: "ascending", "descending", or "unknown"
- `confidence`: numeric 0-1 (higher = more certain)

### `detect_reversals(wave_labels)`

Identifies when question scales flip semantic meaning across waves.

```r
wave_labels <- list(
  w1 = c("1" = "Very bad", "5" = "Very good"),
  w3 = c("1" = "Very good", "5" = "Very bad")  # Reversed!
)

result <- detect_reversals(wave_labels)
# result$reversed_pairs: data frame with w1 vs w3
# result$notes: character vector explaining why
```

**Returns**: List with:
- `reversed_pairs`: Data frame of wave pairs with opposite semantics
- `confidence`: Average confidence score
- `notes`: Explanatory text

### `group_by_question(search_df)`

Organizes search results by question number across waves.

```r
grouped <- group_by_question(parsed_results)

# Result structure:
# grouped$q1:
#   w1: list(var_name = "q001", label = "...", value_labels = ...)
#   w2: list(var_name = "q1", label = "...", value_labels = ...)
#   ...
# grouped$q2: ...
```

### `analyze_search_results(search_results, concept)`

Generates human-readable markdown report of analysis.

```r
report <- analyze_search_results(results, concept = "economy")
cat(report)
```

**Useful for**: Reviewing what the system detected before editing YAML.

### `batch_generate_yaml(search_results_list, output_dir)`

Process multiple concept areas at once.

```r
results_list <- list(
  economy = econ_results,
  politics = politics_results,
  governance = governance_results
)

batch_generate_yaml(results_list, output_dir = "src/config/harmonize/")
# Creates: economy.yml, politics.yml, governance.yml
```

---

## Workflow: Search to Harmonization

### Step 1: Search for Variables

```r
source("src/r/utils/search.R")  # or wherever extract_matches is defined

# Search across all 6 waves
results <- extract_matches(
  keyword = "economic condition",
  w1, w2, w3, w4, w5, w6
)

# Results format (example):
#   wave | variable_name | variable_label              | value_labels
#   -----|---------------|-----------------------------|-----------
#   w1   | q001          | "Overall national economy..." | c("1"="Very bad", ..., "5"="Very good")
#   w2   | q1            | "Overall national economy..." | c("1"="Very bad", ..., "5"="Very good")
#   w3   | q1            | "Overall national economy..." | c("1"="Very good", ..., "5"="Very bad")
#   ...
```

### Step 2: Analyze and Generate YAML

```r
source("src/r/codebook/codebook_workflow.R")

# Option A: Display template for review
yaml_str <- generate_codebook_yaml(results, concept = "economy")
cat(yaml_str)

# Option B: Save directly
generate_codebook_yaml(results, concept = "economy",
                       save_to = "src/config/harmonize/economy.yml")
```

### Step 3: Review Generated YAML

**What to look for**:
- ✅ Source variables correct for each wave?
- ✅ Question labels make sense?
- ✅ Scale types detected correctly? (Look for comments with confidence scores)
- ⚠️ Reversals flagged appropriately? (Not all semantic differences are reversals)

**What to edit**:
1. **Fill `id` field**: Use question number (`q1`, `q2`) or descriptive name (`econ_national`, etc.)
2. **Confirm `harmonize` method**: 
   - Leave as `identity` if no reversal
   - Set `method: r_function` with `fn: safe_reverse_*pt` if reversal detected
3. **Add `validate_all`** (optional but recommended):
   ```yaml
   harmonize:
     default:
       method: r_function
       fn: safe_reverse_5pt
       validate_all: ["econom"]  # Checks label contains "econom"
   ```
4. **Set `valid_range_by_wave`** if needed:
   ```yaml
   qc:
     valid_range_by_wave:
       w1: [1, 5]
       w2: [1, 5]
       ...
   ```

### Step 4: Use in Harmonization

```r
source("src/r/harmonize/harmonize.R")

# Load YAML spec
spec <- yaml::read_yaml("src/config/harmonize/economy.yml")

# Load wave data
waves <- list(
  w1 = readRDS("data/processed/w1.rds"),
  w2 = readRDS("data/processed/w2.rds"),
  w3 = readRDS("data/processed/w3.rds"),
  w4 = readRDS("data/processed/w4.rds"),
  w5 = readRDS("data/processed/w5.rds"),
  w6 = readRDS("data/processed/w6.rds")
)

# Harmonize
harmonized <- harmonize_all(spec, waves = waves)

# Harmonized output (example for econ_national_now):
#   w1: numeric(n1) with values 1-5 (after reversal applied where needed)
#   w2: numeric(n2) with values 1-5
#   w3: numeric(n3) with values 1-5
#   ...
```

---

## Auto-Detection Details

### Scale Type Detection

**Algorithm**:
1. Extract numeric range (min, max) from data
2. Count unique values
3. Map to standard scale types:
   - Range [1,5] with 3+ unique → "5pt"
   - Range [1,4] with 3+ unique → "4pt"
   - Range [1,6] with 3+ unique → "6pt"
   - Range [0,10] → "0-10"
   - Other → "continuous"
4. Calculate confidence = (unique values) / (max - min + 1)

**Limitations**:
- Requires reasonably complete data (sparse values reduce confidence)
- Off-scale values (e.g., "98" = missing) may be misclassified

### Reversal Detection

**Algorithm**:
1. Extract value labels for each wave
2. Parse semantic content of lowest-value label
3. Look for opposite keywords:
   - Negative: "bad", "poor", "low", "disagree", "distrust"
   - Positive: "good", "excellent", "high", "agree", "trust"
4. If Wave 1 starts with "bad" and Wave 3 starts with "good" → REVERSED

**Limitations**:
- Based on English semantic keywords (may need tuning for translations)
- Not all scale differences are reversals (e.g., "agree/disagree" vs "yes/no")
- User should manually confirm flagged reversals

**User guidance**:
> "If there is an extreme outlier in the verbiage, I can edit the YAML later by hand."
> 
> — Your approach to auto-detection (good enough, user refines)

---

## Complete Example

### Data: 24 matches for "economic condition" across 6 waves

```
W1: q001 - "How would you rate the overall economic condition of our country today?"
    Scale: 1=Very bad, 2=Bad, 3=Neither good nor bad, 4=Good, 5=Very good

W2: q1 - "How would you rate the overall economic condition of our country today?"
    Scale: 1=Very bad, 2=Bad, 3=Neither good nor bad, 4=Good, 5=Very good

W3: q1 - "How would you rate the overall economic condition of our country today?"
    Scale: 1=Very good, 2=Good, 3=Neither good nor bad, 4=Bad, 5=Very bad
    
[... W4-W6 similar to W3 ...]
```

### Run workflow:

```r
# Step 1: Search
source("src/r/utils/search.R")
results <- extract_matches("economic condition", w1, w2, w3, w4, w5, w6)
# Returns data frame with 6 rows (one per wave)

# Step 2-3: Generate and view
source("src/r/codebook/codebook_workflow.R")
yaml_str <- generate_codebook_yaml(results, concept = "economy")

# Output includes:
#   - All 6 waves grouped under q1
#   - Scale detection: all detected as 5pt with correct confidence
#   - REVERSAL DETECTION: W1,W2 have ascending; W3-W6 have descending
#   - Suggested: use safe_reverse_5pt for W3-W6
```

### Step 4: Edit YAML

Fill in id, confirm harmonize method:

```yaml
q1:
  id: "econ_national_now"  # FILLED IN
  concept: "economy"
  description: "Overall national economic condition of our country today"
  
  source:
    w1: "q001"
    w2: "q1"
    w3: "q1"
    w4: "q1"
    w5: "q1"
    w6: "q1"
  
  # ... scale comments ...
  
  harmonize:
    default:
      method: "identity"  # W1, W2
    by_wave:
      w3:
        method: "r_function"  # FILLED IN
        fn: "safe_reverse_5pt"
        validate_all: ["econom"]
      w4:
        method: "r_function"
        fn: "safe_reverse_5pt"
        validate_all: ["econom"]
      w5:
        method: "r_function"
        fn: "safe_reverse_5pt"
        validate_all: ["econom"]
      w6:
        method: "r_function"
        fn: "safe_reverse_5pt"
        validate_all: ["econom"]
```

---

## Limitations & Future Work

### Current Limitations

1. **Simple keyword matching**: Relies on semantic parsing of English labels
2. **No alias handling**: Doesn't account for known question renames (e.g., Q01 → Q1)
3. **Manual YAML refinement**: Generated templates need editing before use
4. **No data validation**: Doesn't check against actual survey data values

### Future Enhancements

1. **Skill wrapper**: Auto-run from `/search-and-analyze` command
2. **Interactive refinement**: Prompt user for confidence threshold, accept/reject suggestions
3. **Codebook integration**: Read SPSS/Stata codebooks directly instead of parsed labels
4. **Question registry**: Build reference database of known question renames
5. **Machine learning**: Train on past harmonizations to improve detection

---

## Technical Notes

### Dependencies

- `dplyr` (data manipulation)
- `stringr` (pattern matching)
- `yaml` (read/write YAML)

### Source Files

- `codebook_analysis.R`: Core detection functions (scales, reversals)
- `codebook_workflow.R`: Workflow integration (search → YAML)
- `test_codebook.R`: 40+ test cases

### Error Handling

All public functions return structured output:

```r
# Success case
list(type = "5pt", range = c(1,5), direction = "ascending", confidence = 0.95)

# Failure case (missing data)
list(type = NA_character_, range = NA, direction = NA, confidence = 0)
```

---

## See Also

- `/create-harmonize-spec`: Manual YAML creation with validation
- `/harmonize-variables`: Apply harmonization to wave data
- `safe_reverse_3pt`, `safe_reverse_4pt`, `safe_reverse_5pt`: Recoding functions
