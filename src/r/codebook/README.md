# Codebook Analysis Module

**Purpose**: Automate analysis of search results and generation of YAML templates for variable harmonization

**Status**: Complete and tested

---

## Files in This Module

| File | Purpose | Lines |
|------|---------|-------|
| `codebook_analysis.R` | Core detection functions (scales, reversals, grouping) | 350+ |
| `codebook_workflow.R` | Integration functions (search → YAML pipeline) | 200+ |
| `test_codebook.R` | 40+ test cases covering all functions | 300+ |
| `SKILL_SEARCH_AND_ANALYZE.md` | Complete skill documentation with examples | Documentation |

---

## What This Module Does

### Problem
When you search across 6 waves for "economic condition", you get:
- 24 matches with varying variable names (q001, q1, q_1, etc.)
- Semantic labels that may flip direction (W1: 1=bad, W3: 1=good)
- Need to manually identify scales and reversals

### Solution
```r
# 3-line workflow
results <- extract_matches("economic condition", w1, w2, w3, w4, w5, w6)
yaml_str <- generate_codebook_yaml(results, concept = "economy")
cat(yaml_str)  # Review, then save to file
```

**Output**: YAML template with:
- ✅ Source variable mappings (auto-detected)
- ✅ Scale types (5-point, 4-point, etc.) with confidence scores
- ✅ Direction detection (ascending/descending)
- ✅ **Reversal flags** with explanatory comments
- ✅ Ready for user refinement

---

## Quick Start

### Import the Module

```r
# Load codebook analysis functions
source("src/r/codebook/codebook_analysis.R")
source("src/r/codebook/codebook_workflow.R")
```

### Basic Workflow

```r
# 1. Get search results (from extract_matches or similar)
results <- data.frame(
  wave = c("w1", "w2", "w3"),
  variable_name = c("q001", "q1", "q1"),
  variable_label = c("Economy?", "Economy?", "Economy?"),
  value_labels = list(
    c("1"="Bad", "5"="Good"),
    c("1"="Bad", "5"="Good"),
    c("1"="Good", "5"="Bad")  # Reversed!
  ),
  stringsAsFactors = FALSE
)

# 2. Generate YAML (with auto-detection)
yaml_str <- generate_codebook_yaml(results, concept = "economy")

# 3. View output
cat(yaml_str)

# 4. Save to file
writeLines(yaml_str, "src/config/harmonize/economy.yml")
```

### For Multiple Concepts

```r
# Define search results for each concept
econ_results <- extract_matches("economic condition", waves)
politics_results <- extract_matches("trust government", waves)
governance_results <- extract_matches("civil rights", waves)

# Batch generate YAML files
results_list <- list(
  economy = econ_results,
  politics = politics_results,
  governance = governance_results
)

batch_generate_yaml(results_list, output_dir = "src/config/harmonize/")
# Creates: economy.yml, politics.yml, governance.yml
```

---

## Functions Overview

### Main Entry Points

#### `generate_codebook_yaml(search_results, concept, save_to=NULL)`
Converts search results to YAML template with auto-detection.

**Parameters**:
- `search_results`: Data frame from extract_matches()
- `concept`: Concept area name (e.g., "economy", "politics")
- `save_to`: Optional file path to save YAML

**Returns**: Character string with YAML (if `save_to=NULL`), or saves to file

**Features**:
- Groups by question across waves
- Detects scale types and direction
- Detects reversals
- Generates ready-to-edit YAML

---

#### `analyze_search_results(search_results, concept)`
Generates markdown report of detected patterns.

**Returns**: Formatted markdown text with:
- Summary (# matches, waves, questions)
- Question-by-question analysis
- Scale detection results
- Reversal flags
- Recommendations

**Use for**: Reviewing what system detected before editing

---

### Detection Functions

#### `detect_scale_type(values, value_labels)`
Analyzes numeric range and semantic labels to determine scale.

**Returns**:
```r
list(
  type = "5pt",           # "5pt", "4pt", "6pt", "0-10", etc.
  range = c(1, 5),        # numeric vector
  direction = "ascending", # "ascending", "descending", "unknown"
  confidence = 0.95       # 0-1 score
)
```

**Details**:
- Uses both numeric range and semantic keywords
- Ascending = 1=bad → 5=good
- Descending = 1=good → 5=bad
- Confidence = (unique values) / (max - min + 1)

---

#### `detect_reversals(wave_labels)`
Compares semantic meaning across waves to identify flips.

**Input**: List of value label vectors per wave
```r
list(
  w1 = c("1"="Very bad", ..., "5"="Very good"),
  w2 = c("1"="Very bad", ..., "5"="Very good"),
  w3 = c("1"="Very good", ..., "5"="Very bad")  # Reversed!
)
```

**Returns**:
```r
list(
  reversed_pairs = data.frame(
    wave_1 = "w1",
    wave_2 = "w3",
    confidence = 0.9
  ),
  confidence = 0.9,  # Average
  notes = c("w1 vs w3: opposite semantic direction")
)
```

---

#### `group_by_question(search_df)`
Organizes search results by question number across waves.

**Handles** multiple patterns:
- `q1`, `q01`, `q001`, `Q1` all → `q1`
- Groups w1-w6 under same question

**Returns**: List of question groups
```r
list(
  q1 = list(
    w1 = list(var_name = "q001", label = "...", value_labels = ...),
    w2 = list(var_name = "q1", label = "...", value_labels = ...),
    ...
  ),
  q2 = list(...),
  ...
)
```

---

### Parsing & Utility Functions

#### `parse_search_results(search_results)`
Normalizes search result format to standard data frame.

**Handles**: Different column names (Wave vs wave, Variable_Name vs variable_name, etc.)

**Returns**: Data frame with normalized columns: wave, var_name, label, value_labels

---

#### `batch_generate_yaml(search_results_list, output_dir)`
Process multiple concepts at once.

**Input**: Named list of search result data frames
```r
list(
  economy = econ_df,
  politics = politics_df,
  governance = governance_df
)
```

**Output**: Creates files in output_dir with names matching keys
- economy.yml
- politics.yml
- governance.yml

---

## YAML Output Format

Generated YAML has this structure:

```yaml
# Generated YAML template - review and edit before using

q1:  # Question number
  id: "",  # TODO: user fills in
  concept: "economy"
  description: "Question text from first wave"
  
  source:
    w1: "q001"
    w2: "q1"
    ...
  
  # Scale analysis (auto-detected):
  # w1: 5pt scale, ascending direction, 100.0% confidence
  # w2: 5pt scale, ascending direction, 100.0% confidence
  # w3: 5pt scale, descending direction, 100.0% confidence
  # ⚠️  REVERSALS DETECTED:
  #   w1 vs w3: opposite semantic direction
  
  harmonize:
    default:
      method: "identity"  # user edits
    by_wave: {}
  
  qc:
    valid_range_by_wave: {}
```

**User edits**:
1. Fill `id` field
2. Confirm/adjust `harmonize` methods
3. Add `validate_all` if using r_function
4. Set QC bounds if needed

---

## Testing

Run tests with:

```r
# Load test suite
source("src/r/codebook/test_codebook.R")

# All tests included in file via testthat
# To run:
testthat::test_file("src/r/codebook/test_codebook.R")
```

**Coverage**:
- Scale detection (5-point, 4-point, 6-point)
- Direction detection (ascending/descending)
- Reversal detection (semantic opposite)
- Question number extraction (q1, q001, q01, etc.)
- Grouping by question
- YAML generation
- Parsing and normalization
- End-to-end workflow

---

## Workflow Integration

### Position in Harmonization Pipeline

```
extract_matches()
      ↓
[THIS MODULE] → detect scales, reversals, group by question
      ↓
generate_codebook_yaml() → YAML template
      ↓
User: review & edit YAML
      ↓
harmonize_all() → harmonized variables
```

### Related Modules

- **search.R**: Provides `extract_matches()` function
- **harmonize.R**: Uses YAML specs from this module
- **validate_spec.R**: Validates generated YAML before use
- **report_harmonization.R**: QC reports on harmonized data

---

## Limitations

1. **Semantic detection**: English keywords only (hardcoded in `detect_label_direction()`)
2. **Value labels required**: Needs actual label text to detect reversals
3. **No automatic refinement**: Generated YAML needs manual review
4. **Simple heuristics**: May have false positives/negatives on ambiguous cases

**User philosophy**:
> "If there is an extreme outlier in the verbiage, I can edit the YAML later by hand."

This module is designed to do ~90% of the work automatically, leaving edge cases for human review.

---

## Configuration

No configuration needed - all functions are pure R with no external dependencies beyond `stringr`, `dplyr`, `yaml`.

---

## See Also

- `SKILL_SEARCH_AND_ANALYZE.md`: Complete skill documentation
- `src/r/harmonize/`: Harmonization engine using generated YAML
- `src/r/utils/recoding.R`: Recoding functions referenced in YAML
- `src/config/harmonize/`: Where generated YAML files are stored
